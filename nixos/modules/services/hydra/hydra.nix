{
  config,
  lib,
  pkgs,
  ...
}: let
  hydra-hook = pkgs.substituteAll {
    src = ./hook.sh;
    isExecutable = true;
    inherit (pkgs.stdenvNoCC) shell;
    inherit (pkgs) jq systemd postgresql;
  };
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
          <runcommand>
            command = "${hydra-hook}"
          </runcommand>
        '';
      };
      # allow evaluator and queue-runner to access nix-access-tokens
      systemd.services.hydra-evaluator.serviceConfig.SupplementaryGroups = [config.users.groups.nix-access-tokens.name];
      systemd.services.hydra-queue-runner.serviceConfig.SupplementaryGroups = [
        config.users.groups.nix-access-tokens.name
        config.users.groups.hydra-builder-client.name
      ];
      sops.templates."hydra-extra-config" = {
        group = "hydra";
        mode = "440";
        content = ''
          <github_authorization>
            jz8132543 = Bearer ${config.sops.placeholder."hydra/github-token"}
          </github_authorization>
        '';
      };
      nix.settings.secret-key-files = [
        "${config.sops.secrets."hydra/cache-dora-im".path}"
      ];
      nix.settings.allowed-uris = [
        "https://github.com/" # for nix-index-database
        "https://gitlab.com/" # for home-manager nmd source
        "https://git.sr.ht/" # for home-manager nmd source
      ];
      sops.secrets = {
        "hydra/cache-dora-im" = {};
        "hydra/github-token" = {};
      };
      nix.settings.trusted-users = ["@hydra"];
    }

    {
      # email notifications
      services.hydra.extraConfig = ''
        email_notification = 1
      '';
      systemd.services.hydra-notify.serviceConfig.EnvironmentFile = config.sops.templates."hydra-email".path;
      sops.templates."hydra-email".content = ''
        EMAIL_SENDER_TRANSPORT=SMTP
        EMAIL_SENDER_TRANSPORT_sasl_username=hydra@dora.im
        EMAIL_SENDER_TRANSPORT_sasl_password=${config.sops.placeholder."hydra/mail"}
        EMAIL_SENDER_TRANSPORT_host=smtp.ts.li7g.com
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
        };
        services = {
          hydra.loadBalancer = {
            passHostHeader = true;
            servers = [{url = "http://localhost:${toString config.ports.hydra}";}];
          };
        };
      };
    }
  ];
}
