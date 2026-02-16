{
  config,
  nixosModules,
  ...
}:
let
  domain = "pb.${config.networking.domain}";
  port = config.ports.pastebin;
in
{
  imports = [ nixosModules.services.traefik ];

  # MicroBin: A fast, feature-rich pastebin written in Rust.
  # Supports:
  # - CLI upload: cat file | curl -X POST -F "content=@-" https://pb.dora.im
  # - Web file upload
  # - Self-destruction, encryption, etc.
  virtualisation.oci-containers.containers.microbin = {
    image = "danielszabo99/microbin:latest";
    ports = [ "${toString port}:8080" ];
    volumes = [ "/var/lib/microbin:/app/data" ];
    environment = {
      MICROBIN_DOMAIN = domain;
      MICROBIN_PORT = "8080";
      MICROBIN_EDITABLE = "true";
      MICROBIN_FOOTER_TEXT = "Doraemon's Pastebin";
      MICROBIN_SHOW_READ_STATS = "true";
      MICROBIN_HIGHLIGHTJS = "true";
      MICROBIN_LIST_PASTES = "true";
      MICROBIN_ENCRYPTION_DEFAULT = "true";
      # MICROBIN_ADMIN_PASSWORD = "{{HOMEPAGE_VAR_PASSWORD}}";
    };
    environmentFiles = [ config.sops.templates."microbin-env".path ];
  };

  sops.templates."microbin-env".content = ''
    MICROBIN_ADMIN_PASSWORD=${config.sops.placeholder."password"}
  '';

  services.traefik.proxies.microbin = {
    rule = "Host(`${domain}`)";
    target = "http://localhost:${toString port}";
  };

  environment.global-persistence.directories = [
    "/var/lib/microbin"
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/microbin 0755 root root -"
  ];
}
