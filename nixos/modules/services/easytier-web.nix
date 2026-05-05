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

    virtualisation.oci-containers.containers.easytier-web = {
      image = "easytier/easytier-web:latest";
      ports = [
        "127.0.0.1:${toString cfg.port}:11211"
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

    services.traefik.proxies.easytier-web = {
      rule = "(Host(`${config.networking.fqdn}`) || Host(`et.${config.networking.domain}`)) && (Path(`/et`) || PathPrefix(`/et/`))";
      target = "http://127.0.0.1:${toString cfg.port}";
      middlewares = [
        "auth"
        "easytier-web-stripprefix"
      ];
    };

    services.traefik.dynamicConfigOptions.http.middlewares.easytier-web-stripprefix.stripPrefix.prefixes =
      [ "/et" ];
  };
}
