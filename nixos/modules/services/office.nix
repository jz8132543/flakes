{
  ...
}:
{
  config,
  pkgs,
  lib,
  nixosModules,
  ...
}:
with lib;
let
  x11Fonts = pkgs.runCommand "X11-fonts" { preferLocalBuild = true; } ''
    mkdir -p "$out"
    font_regexp='.*\.\(ttf\|ttc\|otf\|pcf\|pfa\|pfb\|bdf\)\(\.gz\)?'
    find ${toString config.fonts.packages} -regex "$font_regexp" \
      -exec cp '{}' "$out" \;
    cd "$out"
    ${pkgs.gzip}/bin/gunzip -f *.gz
    ${pkgs.xorg.mkfontscale}/bin/mkfontscale
    ${pkgs.xorg.mkfontdir}/bin/mkfontdir
    cat $(find ${pkgs.xorg.fontalias}/ -name fonts.alias) >fonts.alias
  '';
in
{
  imports = [ nixosModules.desktop.fonts ];
  system.activationScripts.mkFontsLink = {
    deps = [ "binsh" ];
    text = ''
      mkdir -p /usr/share/fonts
      cp -r ${x11Fonts} /usr/share/fonts/
    '';
  };
  services.collabora-online = {
    enable = true;
    port = config.ports.office; # default
    # package = mkFHSEnv pkgs.collabora-online;
    settings = {
      # Rely on reverse proxy for SSL
      ssl = {
        enable = false;
        termination = true;
      };

      # Listen on loopback interface only, and accept requests from ::1
      net = {
        listen = "loopback";
        post_allow.host = [ "::1" ];
      };

      # Restrict loading documents from WOPI Host nextcloud.example.com
      storage.wopi = {
        "@allow" = true;
        host = [ "https://alist.${config.networking.domain}" ];
      };

      # Set FQDN of server
      server_name = "office.${config.networking.domain}";
    };
  };

  # virtualisation.oci-containers.containers = {
  #   onlyoffice = {
  #     image = "onlyoffice/documentserver";
  #     ports = [ "127.0.0.1:${toString config.ports.onlyoffice}:80" ];
  #     # environmentFiles = [ config.sops.templates."kindle-sender".path ];
  #     # volumes = [
  #     #   "/var/lib/kindle-sender/kindle-sender.log:/app/default.log:rw"
  #     #   "/var/lib/kindle-sender/:/app/storage/:rw"
  #     # ];
  #     log-driver = "journald";
  #   };
  # };
  # sops.secrets = {
  #   "onlyoffice/jwtSecretFile" = {
  #     owner = "onlyoffice";
  #   };
  # };
  # services.onlyoffice = {
  #   enable = true;
  #   hostname = "office.${config.networking.domain}";
  #   port = config.ports.onlyoffice;
  #
  #   postgresHost = PG;
  #   postgresName = "onlyoffice";
  #   postgresUser = "onlyoffice";
  #
  #   jwtSecretFile = config.sops.secrets."onlyoffice/jwtSecretFile".path;
  # };
  # sops.templates."alist-config" = {
  #   mode = "0644";
  #   owner = "alist";
  #   path = "/var/lib/alist/config.json";
  #   content = ''
  #     DB_TYPE=postgres
  #     DB_HOST=${PG}
  #     DB_NAME=onlyoffice
  #     DB_USER=onlyoffice
  #     JWT_SECRET=${config.sops.placeholder."onlyoffice/jwtSecretFile"}
  #   '';
  # };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      office = {
        rule = "Host(`office.${config.networking.domain}`)";
        entryPoints = [ "https" ];
        service = "office";
      };
    };
    services = {
      office.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.office}"; } ];
      };
    };
  };
}
