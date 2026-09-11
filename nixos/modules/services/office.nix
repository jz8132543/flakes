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
    ${pkgs.mkfontscale}/bin/mkfontscale
    ${pkgs.mkfontdir}/bin/mkfontdir
    cat $(find ${pkgs.fontalias}/ -name fonts.alias) >fonts.alias
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
  virtualisation.oci-containers.containers.eurooffice = {
    image = "ghcr.io/euro-office/documentserver:latest";
    ports = [ "127.0.0.1:${toString config.ports.office}:80" ];
    environment = {
      USE_UNAUTHORIZED_STORAGE = "true";
    };
    extraOptions = [
      "--add-host=cloud.${config.networking.domain}:host-gateway"
    ];
    log-driver = "journald";
  };

  services.traefik.proxies.office = {
    rule = "Host(`office.${config.networking.domain}`)";
    target = "http://localhost:${toString config.ports.office}";
  };
}
