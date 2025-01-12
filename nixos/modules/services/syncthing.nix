{
  config,
  nixosModules,
  lib,
  ...
}:
let
  DATA_DIR = "/mnt/alist/189P/Sync";
in
{
  imports = [ nixosModules.services.rclone ];
  services.syncthing = {
    enable = true;
    guiAddress = "127.0.0.1:${toString config.ports.syncthing}";
    configDir = "/var/lib/syncthing";
    dataDir = "${DATA_DIR}";
    settings.gui.insecureSkipHostcheck = true;
    overrideDevices = false;
    overrideFolders = false;
  };
  # fix 'mkdir ***: Input/output error at /nix/store/sll7fxa3fgbrjacmn3hbqi2avjlqij2k-update-users-groups.pl line 237.'
  users.users.syncthing.createHome = lib.mkForce false;
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      syncthing = {
        rule = "Host(`${config.networking.fqdn}`) && PathPrefix(`/syncthing`)";
        entryPoints = [ "https" ];
        service = "syncthing";
        middlewares = [
          "strip-prefix"
        ];
      };
    };
    services = {
      syncthing.loadBalancer = {
        passHostHeader = true;
        servers = [ { url = "http://localhost:${toString config.ports.syncthing}"; } ];
      };
    };
  };
  environment.global-persistence.directories = [ config.services.syncthing.configDir ];
  services.restic.backups.borgbase.paths = [
    config.services.syncthing.configDir
  ];
}
