{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.services.easytier-web;
in
{
  options.services.easytier-web = {
    enable = mkEnableOption "EasyTier web interface";
    port = mkOption {
      type = types.port;
      default = config.ports.easytier-web;
      description = "Port to listen on.";
    };
  };

  config = mkIf cfg.enable {
    sops.secrets.password = { };

    sops.templates."easytier-web-env" = {
      content = ''
        ET_ADMIN_PASS=${config.sops.placeholder."password"}
      '';
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/easytier-web 0755 root root -"
    ];

    virtualisation.oci-containers.containers.easytier-web = {
      image = "easytier/easytier:latest";
      entrypoint = "easytier-web-embed";
      ports = [
        "0.0.0.0:${toString cfg.port}:11211"
      ];
      volumes = [
        "/var/lib/easytier-web:/app"
      ];
      environment = {
        ET_ADMIN_USER = "i";
      };
      environmentFiles = [
        config.sops.templates."easytier-web-env".path
      ];
    };
  };
}
