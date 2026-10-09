{
  config,
  pkgs,
  nixosModules,
  ...
}:
let
  mysqlBackupLocation = config.services.mysqlBackup.location or "/var/backup/mysql";

  # MySQL / MariaDB 数据库恢复脚本：从 /var/backup/mysql 导入
  resticRestoreMysql = pkgs.writeShellApplication {
    name = "restic-restore-mysql";
    runtimeInputs = with pkgs; [
      (if config.services.mysql.enable then config.services.mysql.package else pkgs.mariadb)
      zstd
      gzip
      coreutils
      findutils
      util-linux
      systemd
    ];
    text = ''
      BACKUP_DIR="${mysqlBackupLocation}"

      if [ ! -d "$BACKUP_DIR" ]; then
        echo "Error: MySQL backup directory not found at $BACKUP_DIR" >&2
        exit 1
      fi

      echo "==> [MySQL Restore] Ensuring MySQL/MariaDB service is active..."
      systemctl start mysql.service 2>/dev/null || true

      echo "==> [MySQL Restore] Waiting for MySQL/MariaDB service to be ready..."
      READY=0
      for _ in $(seq 1 30); do
        if [ -S /run/mysqld/mysqld.sock ] && mariadb-admin --socket=/run/mysqld/mysqld.sock ping --silent 2>/dev/null; then
          READY=1
          break
        fi
        sleep 1
      done

      if [ "$READY" -eq 0 ]; then
        echo "Error: Timed out waiting for MySQL/MariaDB to be ready." >&2
        exit 1
      fi

      # 1. 优先恢复全库转储 all.sql.*
      if [ -f "$BACKUP_DIR/all.sql.zstd" ]; then
        echo "==> Found $BACKUP_DIR/all.sql.zstd. Restoring full MySQL dump..."
        zstd -dc "$BACKUP_DIR/all.sql.zstd" | mariadb -u root
        echo "==> [MySQL Restore] Full MySQL dump restore completed."
      elif [ -f "$BACKUP_DIR/all.sql.zst" ]; then
        echo "==> Found $BACKUP_DIR/all.sql.zst. Restoring full MySQL dump..."
        zstd -dc "$BACKUP_DIR/all.sql.zst" | mariadb -u root
        echo "==> [MySQL Restore] Full MySQL dump restore completed."
      elif [ -f "$BACKUP_DIR/all.sql.gz" ]; then
        echo "==> Found $BACKUP_DIR/all.sql.gz. Restoring full MySQL dump..."
        gzip -dc "$BACKUP_DIR/all.sql.gz" | mariadb -u root
        echo "==> [MySQL Restore] Full MySQL dump restore completed."
      elif [ -f "$BACKUP_DIR/all.sql" ]; then
        echo "==> Found $BACKUP_DIR/all.sql. Restoring full MySQL dump..."
        mariadb -u root < "$BACKUP_DIR/all.sql"
        echo "==> [MySQL Restore] Full MySQL dump restore completed."
      # 2. 检查 automysqlbackup 生成的目录结构 ($BACKUP_DIR/daily/<dbname>/*.sql.gz)
      elif [ -d "$BACKUP_DIR/daily" ]; then
        echo "==> Found AutoMySQLBackup directory structure in $BACKUP_DIR/daily..."
        FOUND=0
        for db_dir in "$BACKUP_DIR/daily"/*; do
          [ -d "$db_dir" ] || continue
          DBNAME="$(basename "$db_dir")"
          case "$DBNAME" in
            information_schema|performance_schema|sys)
              continue
              ;;
          esac
          # 获取该数据库目录下最新修改的 .sql.gz 文件
          LATEST_DUMP="$(find "$db_dir" -maxdepth 1 -name "*.sql.gz" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)"
          if [ -n "$LATEST_DUMP" ] && [ -f "$LATEST_DUMP" ]; then
            echo "==> Restoring MySQL database: $DBNAME from $LATEST_DUMP..."
            mariadb -u root -e "CREATE DATABASE IF NOT EXISTS \`$DBNAME\`;" 2>/dev/null || true
            gzip -dc "$LATEST_DUMP" | mariadb -u root "$DBNAME"
            FOUND=1
          fi
        done
        if [ "$FOUND" -eq 0 ]; then
          echo "Warning: No valid database dumps found in $BACKUP_DIR/daily." >&2
        else
          echo "==> [MySQL Restore] All databases restored successfully from AutoMySQLBackup."
        fi
      # 3. 检查单层目录下的各个 dump 文件
      else
        echo "==> Searching for individual database dumps in $BACKUP_DIR..."
        FOUND=0
        for dump in "$BACKUP_DIR"/*; do
          [ -f "$dump" ] || continue
          DBNAME=""
          DECOMPRESS=""
          case "$dump" in
            *.sql.zstd)
              DBNAME="$(basename "$dump" .sql.zstd)"
              DECOMPRESS="zstd -dc"
              ;;
            *.sql.zst)
              DBNAME="$(basename "$dump" .sql.zst)"
              DECOMPRESS="zstd -dc"
              ;;
            *.zst)
              DBNAME="$(basename "$dump" .zst)"
              DECOMPRESS="zstd -dc"
              ;;
            *.sql.gz)
              DBNAME="$(basename "$dump" .sql.gz)"
              DECOMPRESS="gzip -dc"
              ;;
            *.gz)
              DBNAME="$(basename "$dump" .gz)"
              DECOMPRESS="gzip -dc"
              ;;
            *.sql)
              DBNAME="$(basename "$dump" .sql)"
              DECOMPRESS="cat"
              ;;
            *)
              continue
              ;;
          esac

          [ "$DBNAME" = "all" ] && continue

          echo "==> Restoring MySQL database: $DBNAME from $dump..."
          mariadb -u root -e "CREATE DATABASE IF NOT EXISTS \`$DBNAME\`;" 2>/dev/null || true
          $DECOMPRESS "$dump" | mariadb -u root "$DBNAME"
          FOUND=1
        done
        if [ "$FOUND" -eq 0 ]; then
          echo "Warning: No MySQL dump files found in $BACKUP_DIR." >&2
        else
          echo "==> [MySQL Restore] All individual database dumps restored successfully."
        fi
      fi
    '';
  };
in
{
  imports = [ nixosModules.services.restic ];

  environment.systemPackages = [
    resticRestoreMysql
  ];

  services.mysql = {
    enable = true;
    package = pkgs.mariadb;
    settings.mysqld = {
      bind-address = "0.0.0.0";
      skip-networking = false;
    };
  };

  # backup mysql database via automysqlbackup (原生全库自动备份与轮转)
  services.automysqlbackup = {
    enable = true;
    calendar = "01:15:00"; # 备份时间调度（如 postgresqlBackup.startAt，支持 systemd OnCalendar 表达式）
  };

  services.restic.backups.borgbase.paths = [
    "/var/backup/mysql"
  ];
  systemd.services."restic-backups-borgbase" = {
    after = [ "automysqlbackup.service" ];
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
  networking.hosts."127.0.0.1" = [ "mysql.ts" ];
}
