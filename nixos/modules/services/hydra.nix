{
  PG ? "postgres.mag",
  hydraURL ? null,
  notificationSender ? "services@dora.im",
  hydraHost ? null,
  cacheHost ? null,
  cacheBind ? "127.0.0.1:5000",
  githubUser ? "jz8132543",
  githubTokenSecretName ? "hydra/github-token",
  cacheSecretName ? "hydra/cache-dora-im",
  builderMachineSecretName ? "hydra/builder_private_key",
  builderMachineEntry ? null,
  enableGithubAuth ? true,
  enableEmail ? true,
  enableTraefik ? true,
  enableBuilderMachine ? true,
  extraHydraConfig ? ''
    <githubstatus>
      jobs = misc:flakes:.*
      excludeBuildFromContext = 1
      useShortContext = 1
    </githubstatus>
    <dynamicruncommand>
      enable = 1
    </dynamicruncommand>
  '',
  ...
}:
{
  config,
  lib,
  ...
}:
let
  inherit (config.networking) domain;
  resolvedHydraHost = if hydraHost == null then "hydra.${domain}" else hydraHost;
  resolvedCacheHost = if cacheHost == null then "cache.${domain}" else cacheHost;
  resolvedHydraURL = if hydraURL == null then "https://${resolvedHydraHost}" else hydraURL;
  resolvedBuilderMachineEntry =
    if builderMachineEntry == null then
      "nix-ssh@${resolvedHydraHost}  x86_64-linux,i686-linux /etc/${keyFile} 4 1 kvm,nixos-test,benchmark,big-parallel"
    else
      builderMachineEntry;
  hydraUser = config.users.users.hydra.name;
  hydraGroup = config.users.users.hydra.group;
  keyFile = "nix-build-machines/hydra-builder/key";
  machineFile = "nix-build-machines/hydra-builder/machines";
  cacheSecretPath = config.sops.secrets."${cacheSecretName}".path;
in
{
  config = lib.mkMerge [
    {
      services.hydra = {
        enable = true;
        listenHost = "127.0.0.1";
        port = config.ports.hydra;
        hydraURL = resolvedHydraURL;
        inherit notificationSender;
        useSubstitutes = true;
        dbi = "dbi:Pg:dbname=hydra;host=${PG};user=hydra;";
        buildMachinesFiles = [
          "/etc/nix/machines"
        ]
        ++ lib.optional enableBuilderMachine "/etc/nix-build-machines/hydra-builder/machines";
        extraConfig = lib.concatStringsSep "\n\n" (
          lib.filter (s: s != "") [
            (lib.optionalString enableGithubAuth ''
              Include "${config.sops.templates."hydra-extra-config".path}"
            '')
            extraHydraConfig
            (lib.optionalString enableEmail ''
              email_notification = 1
            '')
          ]
        );
      };
      users.users = {
        hydra-queue-runner.extraGroups = [ hydraGroup ];
        hydra-www.extraGroups = [ hydraGroup ];
      };
      nix.settings.secret-key-files = [ cacheSecretPath ];
      nix.settings.allowed-uris = [
        "http://"
        "https://"
      ];
      sops.secrets = {
        "${cacheSecretName}" = {
          owner = hydraUser;
          group = hydraGroup;
          mode = "0440";
        };
      }
      // lib.optionalAttrs enableGithubAuth {
        "${githubTokenSecretName}" = {
          owner = hydraUser;
          group = hydraGroup;
          mode = "0440";
        };
      }
      // lib.optionalAttrs enableBuilderMachine {
        "${builderMachineSecretName}" = {
          neededForUsers = true;
        };
      };
      systemd.services."hydra-init" = {
        after = [
          "postgresql.service"
          "tailscaled.service"
        ];
        serviceConfig.Restart = lib.mkForce "on-failure";
        serviceConfig.Type = lib.mkForce "simple";
      };
    }

    (lib.mkIf enableGithubAuth {
      sops.templates."hydra-extra-config" = {
        group = "hydra";
        mode = "440";
        content = ''
          <github_authorization>
            ${githubUser} = Bearer ${config.sops.placeholder."${githubTokenSecretName}"}
          </github_authorization>
        '';
      };
    })

    (lib.mkIf enableEmail {
      systemd.services.hydra-notify.serviceConfig.EnvironmentFile =
        config.sops.templates."hydra-email".path;
      sops.templates."hydra-email".content = ''
        EMAIL_SENDER_TRANSPORT=SMTP
        EMAIL_SENDER_TRANSPORT_sasl_username=${notificationSender}
        EMAIL_SENDER_TRANSPORT_sasl_password=${config.sops.placeholder."mail/services"}
        EMAIL_SENDER_TRANSPORT_host=${config.lib.self.data.mail.smtp};
        EMAIL_SENDER_TRANSPORT_port=${toString config.ports.smtp}
        EMAIL_SENDER_TRANSPORT_ssl=on
      '';
    })

    {
      services = {
        harmonia.cache = {
          enable = true;
          signKeyPaths = [ cacheSecretPath ];
          settings = {
            bind = cacheBind;
          };
        };
      };
    }

    (lib.mkIf enableTraefik {
      services.traefik.proxies = {
        hydra = {
          rule = "Host(`" + resolvedHydraHost + "`)";
          target = "http://localhost:${toString config.ports.hydra}";
        };
        harmonia = {
          rule = "Host(`" + resolvedCacheHost + "`)";
          target = "http://${cacheBind}";
        };
      };
    })

    (lib.mkIf enableBuilderMachine {
      environment.etc.${keyFile} = {
        mode = "440";
        user = hydraUser;
        group = hydraGroup;
        source = config.sops.secrets."${builderMachineSecretName}".path;
      };
      environment.etc.${machineFile}.text = resolvedBuilderMachineEntry;
    })

    {
      programs.ssh = with lib.strings; {
        extraConfig = ''
          CanonicalDomains ${concatStringsSep " " config.networking.search}
          CanonicalizeHostname yes
          LogLevel ERROR
          StrictHostKeyChecking no
          Match canonical final Host ${
            concatMapStringsSep "," (
              x:
              concatStrings [
                "*."
                x
              ]
            ) config.environment.domains
          }
            Port 1022
            HashKnownHosts no
            UserKnownHostsFile /dev/null
        '';
      };
    }
  ];
}
