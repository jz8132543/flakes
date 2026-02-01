{
  pkgs,
  ...
}:
{
  services.mysql = {
    enable = true;
    package = pkgs.mariadb;
    settings.mysqld = {
      bind-address = "0.0.0.0";
      skip-networking = false;
    };
  };

  # Separate setup service to avoid blocking mysql.service startup
  systemd.services.mysql-setup = {
    description = "Create IYUU database and user";
    after = [ "mysql.service" ];
    requires = [ "mysql.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
      ExecStart = pkgs.writeShellScript "mysql-setup" ''
        # Wait for socket to be ready
        while [ ! -S /run/mysqld/mysqld.sock ]; do sleep 1; done

        # Create database and user via CLI as requested
        ${pkgs.mariadb}/bin/mariadb -u root -e "CREATE DATABASE IF NOT EXISTS iyuu;"
        ${pkgs.mariadb}/bin/mariadb -u root -e "GRANT ALL PRIVILEGES ON iyuu.* TO 'iyuu'@'%' IDENTIFIED BY ${"''"};"
        ${pkgs.mariadb}/bin/mariadb -u root -e "FLUSH PRIVILEGES;"
      '';
    };
  };

  # Internal hostname alias
  networking.hosts."127.0.0.1" = [ "mysql.mag" ];
}
