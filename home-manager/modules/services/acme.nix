{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.acme;
in
{
  options.services.acme = {
    enable = lib.mkEnableOption "ACME certificate management using lego";

    email = lib.mkOption {
      type = lib.types.str;
      default = "blackhole@dora.im";
      description = "Email address for ACME registration.";
    };

    certs = lib.mkOption {
      default = { };
      description = "Attribute set of certificates to manage.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            domain = lib.mkOption {
              type = lib.types.str;
              description = "The main domain for the certificate.";
            };
            extraDomainNames = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Extra domain names for the certificate.";
            };
            aliasNames = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Symlink the resulting certificate to these names (useful for wildcards).";
            };
            dnsProvider = lib.mkOption {
              type = lib.types.str;
              default = "cloudflare";
              description = "The DNS provider for lego (e.g., cloudflare).";
            };
            credentialsFile = lib.mkOption {
              type = lib.types.str;
              default = config.sops.templates.acme-credentials.path;
              description = "Path to a file containing environment variables for the DNS provider.";
            };
          };
        }
      );
    };

    directory = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/acme";
      description = "Directory to store certificates.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.lego ];

    systemd.user.services = lib.mapAttrs' (
      name: cert:
      lib.nameValuePair "acme-${name}" {
        Unit = {
          Description = "ACME certificate renewal for ${cert.domain}";
          After = [ "network.target" ];
        };

        Service = {
          Type = "oneshot";
          EnvironmentFile = cert.credentialsFile;
          ExecStart =
            let
              domains = [ cert.domain ] ++ cert.extraDomainNames;
              domainArgs = builtins.concatStringsSep " " (map (d: "--domains ${d}") domains);
              # lego naming: *.dora.im becomes _.dora.im.crt
              legoName = lib.replaceStrings [ "*" ] [ "_" ] cert.domain;
              certPath = "${cfg.directory}/certificates/${legoName}.crt";
            in
            pkgs.writeShellScript "acme-${name}-start" ''
              set -e
              if [ ! -f "${certPath}" ]; then
                echo "Certificate ${certPath} not found. Running initial setup..."
                ${pkgs.lego}/bin/lego --email ${cfg.email} --accept-tos --path ${cfg.directory} --dns ${cert.dnsProvider} ${domainArgs} run
              else
                echo "Certificate ${certPath} found. Checking for renewal..."
                ${pkgs.lego}/bin/lego --email ${cfg.email} --accept-tos --path ${cfg.directory} --dns ${cert.dnsProvider} ${domainArgs} renew --renew-days 30
              fi

              # Create aliases
              ${builtins.concatStringsSep "\n" (
                map (alias: ''
                  ln -sf "${legoName}.crt" "${cfg.directory}/certificates/${alias}.crt"
                  ln -sf "${legoName}.key" "${cfg.directory}/certificates/${alias}.key"
                '') cert.aliasNames
              )}
            '';
        };

        Install = {
          WantedBy = [ "default.target" ];
        };
      }
    ) cfg.certs;

    systemd.user.timers = lib.mapAttrs' (
      name: cert:
      lib.nameValuePair "acme-${name}" {
        Unit = {
          Description = "Daily ACME renewal for ${cert.domain}";
        };
        Timer = {
          OnCalendar = "daily";
          Persistent = true;
        };
        Install = {
          WantedBy = [ "timers.target" ];
        };
      }
    ) cfg.certs;

    sops.templates.acme-credentials.content = ''
      CLOUDFLARE_DNS_API_TOKEN=${config.sops.placeholder."traefik/cloudflare_token"}
    '';

    sops.secrets."traefik/cloudflare_token" = {
    };
  };
}
