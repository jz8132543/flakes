{ lib, pkgs, config, ... }: {
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_15;
    enableTCPIP = true;
  };
  networking.firewall = {
    allowedTCPPorts = [ 5432 ];
  };
  environment.systemPackages = [ config.services.postgresql.package ];

  environment.persistence."/nix/persist" = {
    directories = [
      "/var/lib/postgresql"
    ];
  };
}
