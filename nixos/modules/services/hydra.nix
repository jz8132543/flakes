{
  config,
  lib,
  pkgs,
  ...
}: let
  hydraUser = config.users.users.hydra.name;
  hydraGroup = config.users.users.hydra.group;
  keyFile = "nix-build-machines/hydra-builder/key";
  machineFile = "nix-build-machines/hydra-builder/machines";
in {
  config = lib.mkMerge [
    {
      services.hydra = {
        enable = true;
        package = pkgs.hydra-master;
        listenHost = "127.0.0.1";
        port = config.ports.hydra;
        hydraURL = "https://hydra.dora.im";
        notificationSender = "hydra@dora.im";
        useSubstitutes = true;
        dbi = "dbi:Pg:dbname=hydra;host=postgres.dora.im;user=hydra;";
        buildMachinesFiles = [
          "/etc/nix/machines"
          "/etc/nix-build-machines/hydra-builder/machines"
        ];
        extraConfig = ''
          Include "${config.sops.templates."hydra-extra-config".path}"

          <githubstatus>
            jobs = misc:flakes:.*
            excludeBuildFromContext = 1
            useShortContext = 1
          </githubstatus>
          <dynamicruncommand>
            enable = 1
          </dynamicruncommand>
        '';
      };
      users.users = {
        hydra-queue-runner.extraGroups = [hydraGroup];
        hydra-www.extraGroups = [hydraGroup];
      };
      sops.templates."hydra-extra-config" = {
        group = "hydra";
        mode = "440";
        content = ''
          <github_authorization>
            jz8132543 = Bearer ${config.sops.placeholder."hydra/github-token"}
          </github_authorization>
        '';
      };
      nix.settings.secret-key-files = ["${config.sops.secrets."hydra/cache-dora-im".path}"];
      nix.settings.allowed-uris = ["http://" "https://"];
      sops.secrets = {
        "hydra/cache-dora-im" = {
          owner = hydraUser;
          group = hydraGroup;
          mode = "0440";
        };
        "hydra/github-token" = {
          owner = hydraUser;
          group = hydraGroup;
          mode = "0440";
        };
        "hydra/builder_private_key" = {
          neededForUsers = true;
        };
      };
      environment.etc.${keyFile} = {
        mode = "440";
        user = hydraUser;
        group = hydraGroup;
        source = config.sops.secrets."hydra/builder_private_key".path;
      };
      environment.etc.${machineFile}.text = ''
        nix-ssh@fra0  x86_64-linux,i686-linux /etc/${keyFile} 4 1 kvm,nixos-test,benchmark,big-parallel
      '';
    }

    {
      services = {
        nix-serve = {
          enable = true;
          secretKeyFile = config.sops.secrets."hydra/cache-dora-im".path;
        };
      };
    }

    {
      # email notifications
      services.hydra.extraConfig = ''
        email_notification = 1
      '';
      systemd.services.hydra-init.after = ["tailscaled.service" "postgresql.service"];
      systemd.services.hydra-notify.serviceConfig.EnvironmentFile = config.sops.templates."hydra-email".path;
      sops.templates."hydra-email".content = ''
        EMAIL_SENDER_TRANSPORT=SMTP
        EMAIL_SENDER_TRANSPORT_sasl_username=hydra@dora.im
        EMAIL_SENDER_TRANSPORT_sasl_password=${config.sops.placeholder."hydra/mail"}
        EMAIL_SENDER_TRANSPORT_host=${config.lib.self.data.mail.smtp};
        EMAIL_SENDER_TRANSPORT_port=${toString config.ports.smtp}
        EMAIL_SENDER_TRANSPORT_ssl=on
      '';
      sops.secrets."hydra/mail" = {};
    }

    {
      services.traefik.dynamicConfigOptions.http = {
        routers = {
          hydra = {
            rule = "Host(`hydra.dora.im`)";
            entryPoints = ["https"];
            service = "hydra";
          };
          nix-serve = {
            rule = "Host(`cache.dora.im`)";
            entryPoints = ["https"];
            service = "nix-serve";
          };
        };
        services = {
          hydra.loadBalancer = {
            passHostHeader = true;
            servers = [{url = "http://localhost:${toString config.ports.hydra}";}];
          };
          nix-serve.loadBalancer = {
            passHostHeader = true;
            servers = [{url = "http://localhost:${toString config.services.nix-serve.port}";}];
          };
        };
      };
      systemd.services."hydra-init" = {
        after = ["postgresql.service" "tailscaled.service"];
        serviceConfig.Restart = lib.mkForce "on-failure";
        serviceConfig.Type = lib.mkForce "simple";
      };
    }

    {
      programs.ssh = {
        extraConfig = ''
          CanonicalDomains dora.im ts.dora.im
          CanonicalizeHostname yes
          LogLevel ERROR
          StrictHostKeyChecking no
          Match canonical final Host *.dora.im,*.ts.dora.im
            Port 1022
            HashKnownHosts no
            UserKnownHostsFile /dev/null
        '';
      };
    }
  ];
}
