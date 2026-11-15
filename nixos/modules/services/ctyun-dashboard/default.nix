{
  config,
  lib,
  nixosModules,
  pkgs,
  ...
}:
let
  cfg = config.services.ctyun-dashboard;
in
{
  imports = [
    nixosModules.services.podman
    nixosModules.services.traefik
    nixosModules.services.restic
  ];

  options.services.ctyun-dashboard = {
    enable = lib.mkEnableOption "ctyun-dashboard cloud desktop management";

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/muyicn/ctyun-dashboard@sha256:9e7754442659e7b7cec98a53f0c3729437e3764e9a081f5b2820a3621703daf0";
      description = "Container image, pinned to upstream revision 827a07d.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "ctyun.${config.networking.domain}";
      description = "Public hostname for the dashboard.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = config.ports.ctyun-dashboard;
      description = "Loopback port exposed to Traefik.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/ctyun-dashboard";
      description = "Persistent accounts, encryption keys and login sessions.";
    };

    adminPasswordSecretKey = lib.mkOption {
      type = lib.types.str;
      default = "password";
      description = "SOPS secret used to create the i administrator when missing.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.${cfg.adminPasswordSecretKey} = { };

    virtualisation.oci-containers.containers.ctyun-dashboard = {
      inherit (cfg) image;
      autoStart = true;
      ports = [ "127.0.0.1:${toString cfg.port}:8571" ];
      # Digest-pinned images must not participate in registry auto-updates.
      labels."io.containers.autoupdate" = "";
      environment = {
        TZ = config.time.timeZone;
        PORT = "8571";
        CTYUN_DATA_DIR = "/app/data";
      };
      volumes = [ "${cfg.dataDir}:/app/data" ];
      extraOptions = [
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
        "--umask=0077"
      ];
    };

    systemd.services.podman-ctyun-dashboard = {
      after = [
        "systemd-tmpfiles-setup.service"
        "sops-install-secrets.service"
      ];
      requires = [ "sops-install-secrets.service" ];
      unitConfig.RequiresMountsFor = [ cfg.dataDir ];
      serviceConfig.UMask = "0077";
      preStart = ''
        ${pkgs.python3}/bin/python3 ${./init.py} \
          ${lib.escapeShellArg cfg.dataDir} \
          ${lib.escapeShellArg config.sops.secrets.${cfg.adminPasswordSecretKey}.path}
      '';
    };

    services.traefik.proxies.ctyun-dashboard = {
      rule = "Host(`${cfg.domain}`)";
      target = "http://127.0.0.1:${toString cfg.port}";
    };

    # These upstream endpoints bypass application authentication. Keep them
    # unreachable publicly without interfering with normal Bearer tokens/SSE.
    services.traefik.dynamicConfigOptions.http.routers.ctyun-dashboard-unsafe = {
      rule = "Host(`${cfg.domain}`) && (Path(`/api/keeper/restart`) || Path(`/api/ctyun-proxy`))";
      priority = 1000;
      entryPoints = [
        "https"
        "https-alt"
      ];
      service = "noop@internal";
      tls = if config.environment.isNAT then { } else { certResolver = "zerossl"; };
    };

    # Remove only this deployment's temporary overrides on a normal NixOS
    # switch, so they cannot mask future declarative service/proxy updates.
    system.activationScripts.ctyun-dashboard-bootstrap-cleanup = lib.stringAfter [ "etc" ] ''
      for unit in \
        podman-ctyun-dashboard.service \
        multi-user.target.wants/podman-ctyun-dashboard.service \
        traefik.service.d/ctyun-dashboard-bootstrap.conf; do
        file="/etc/systemd/system.control/$unit"
        case "$(${pkgs.coreutils}/bin/readlink "$file" || true)" in
          /nix/store/*-ctyun-dashboard-deployment/*) ${pkgs.coreutils}/bin/rm -f "$file" ;;
        esac
      done
    '';

    systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0700 root root -" ];
    environment.global-persistence.directories = [ cfg.dataDir ];
    services.restic.backups.borgbase.paths = [ cfg.dataDir ];
  };
}
