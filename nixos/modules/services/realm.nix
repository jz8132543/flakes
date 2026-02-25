{ pkgs, ... }:
{
  # Realm relay service
  # Configuration is read from /etc/realm/*.toml (or any config format realm supports)
  # Users should manually manage files in /etc/realm/
  # Example config: /etc/realm/config.toml

  systemd.services.realm = {
    description = "Realm relay service";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = "5s";
      # realm reads all *.toml files in a directory when given a directory path
      ExecStart = "${pkgs.realm}/bin/realm -c /etc/realm/config.toml";
      # Security hardening
      DynamicUser = false;
      User = "realm";
      Group = "realm";
      # Allow binding to privileged ports if needed
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
      CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      LogsDirectory = "realm";
      WorkingDirectory = "/var/log/realm";
      ReadOnlyPaths = [ "/etc/realm" ];
    };
  };

  users.users.realm = {
    isSystemUser = true;
    group = "realm";
    description = "Realm relay service user";
  };

  users.groups.realm = { };

  systemd.tmpfiles.rules = [
    "d /etc/realm 0755 root root -"
  ];

  # Persist the config directory across reboots (for impermanence setups)
  environment.global-persistence = {
    directories = [
      "/etc/realm"
    ];
  };
}
