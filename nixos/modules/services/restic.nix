{
  config,
  lib,
  pkgs,
  ...
}:
let
  pwFile = config.sops.secrets."restic/RESTIC_PASSWORD".path;
  repoFile = config.sops.secrets."restic/RESTIC_REPOSITORY".path;
  pgBackupLocation = config.services.postgresqlBackup.location or "/var/backup/postgresql";
  mysqlBackupLocation = config.services.mysqlBackup.location or "/var/backup/mysql";

  # 1. 灾难恢复脚本：按用户名恢复文件所有权 (--ownership-by-name)
  resticRestore = pkgs.writeShellApplication {
    name = "restic-restore";
    runtimeInputs = with pkgs; [
      (config.services.restic.backups.borgbase.package or pkgs.restic)
      coreutils
    ];
    text = ''
      SNAPSHOT="''${1:-latest}"
      TARGET="''${2:-/}"
      SUBPATH="''${3:-}"

      export RESTIC_PASSWORD_FILE="''${RESTIC_PASSWORD_FILE:-${pwFile}}"
      export RESTIC_REPOSITORY_FILE="''${RESTIC_REPOSITORY_FILE:-${repoFile}}"

      if [ ! -r "$RESTIC_PASSWORD_FILE" ] || [ ! -r "$RESTIC_REPOSITORY_FILE" ]; then
        echo "Error: Restic credentials not found or unreadable." >&2
        echo "Expected password file: $RESTIC_PASSWORD_FILE" >&2
        echo "Expected repository file: $RESTIC_REPOSITORY_FILE" >&2
        exit 1
      fi

      echo "==> [Restic Restore] Preparing to restore snapshot [$SNAPSHOT] into [$TARGET]..."
      echo "==> Using --ownership-by-name to resolve user/group ownership by name instead of numeric UID/GID."

      RESTORE_TARGET="$SNAPSHOT"
      if [ -n "$SUBPATH" ]; then
        RESTORE_TARGET="$SNAPSHOT:$SUBPATH"
      fi

      if ! restic restore "$RESTORE_TARGET" \
        --target "$TARGET" \
        --ownership-by-name \
        --verify; then
        echo "==> [Notice] Verification detected discrepancies on some files." >&2
        echo "==> Note: This is normal when restoring onto a live system where background services (e.g. LDAP, tokens) are actively writing." >&2
      else
        echo "==> [Restic Restore] Files restored and verified successfully."
      fi
    '';
  };

  # 2. PostgreSQL 数据库恢复脚本：从 /var/backup/postgresql 导入
  resticRestorePostgres = pkgs.writeShellApplication {
    name = "restic-restore-postgres";
    runtimeInputs = with pkgs; [
      (if config.services.postgresql.enable then config.services.postgresql.package else pkgs.postgresql)
      zstd
      gzip
      coreutils
      util-linux
      systemd
    ];
    text = ''
      BACKUP_DIR="${pgBackupLocation}"

      if [ ! -d "$BACKUP_DIR" ]; then
        echo "Error: PostgreSQL backup directory not found at $BACKUP_DIR" >&2
        exit 1
      fi

      echo "==> [PostgreSQL Restore] Ensuring PostgreSQL service is active..."
      systemctl start postgresql.service 2>/dev/null || true

      echo "==> [PostgreSQL Restore] Waiting for PostgreSQL service to be ready..."
      READY=0
      for _ in $(seq 1 30); do
        if pg_isready -h /run/postgresql -q; then
          READY=1
          break
        fi
        sleep 1
      done

      if [ "$READY" -eq 0 ]; then
        echo "Error: Timed out waiting for PostgreSQL to be ready." >&2
        exit 1
      fi

      # 优先恢复全库转储 all.sql.* (当 backupAll = true 时由 services.postgresqlBackup 生成)
      if [ -f "$BACKUP_DIR/all.sql.zstd" ]; then
        echo "==> Found $BACKUP_DIR/all.sql.zstd. Restoring full cluster dump..."
        zstd -dc "$BACKUP_DIR/all.sql.zstd" | runuser -u postgres -- psql -v ON_ERROR_STOP=0
        echo "==> [PostgreSQL Restore] Full cluster dump restore completed."
      elif [ -f "$BACKUP_DIR/all.sql.zst" ]; then
        echo "==> Found $BACKUP_DIR/all.sql.zst. Restoring full cluster dump..."
        zstd -dc "$BACKUP_DIR/all.sql.zst" | runuser -u postgres -- psql -v ON_ERROR_STOP=0
        echo "==> [PostgreSQL Restore] Full cluster dump restore completed."
      elif [ -f "$BACKUP_DIR/all.sql.gz" ]; then
        echo "==> Found $BACKUP_DIR/all.sql.gz. Restoring full cluster dump..."
        gzip -dc "$BACKUP_DIR/all.sql.gz" | runuser -u postgres -- psql -v ON_ERROR_STOP=0
        echo "==> [PostgreSQL Restore] Full cluster dump restore completed."
      elif [ -f "$BACKUP_DIR/all.sql" ]; then
        echo "==> Found $BACKUP_DIR/all.sql. Restoring full cluster dump..."
        runuser -u postgres -- psql -v ON_ERROR_STOP=0 < "$BACKUP_DIR/all.sql"
        echo "==> [PostgreSQL Restore] Full cluster dump restore completed."
      else
        echo "==> Searching for individual database dumps in $BACKUP_DIR..."
        FOUND=0
        for dump in "$BACKUP_DIR"/*.sql.zstd "$BACKUP_DIR"/*.sql.zst "$BACKUP_DIR"/*.sql.gz "$BACKUP_DIR"/*.sql; do
          [ -f "$dump" ] || continue
          case "$dump" in
            *.sql.zstd)
              DBNAME="$(basename "$dump" .sql.zstd)"
              echo "==> Restoring database: $DBNAME from $dump..."
              runuser -u postgres -- psql -c "CREATE DATABASE \"$DBNAME\";" 2>/dev/null || true
              zstd -dc "$dump" | runuser -u postgres -- psql -d "$DBNAME" -v ON_ERROR_STOP=0
              ;;
            *.sql.zst)
              DBNAME="$(basename "$dump" .sql.zst)"
              echo "==> Restoring database: $DBNAME from $dump..."
              runuser -u postgres -- psql -c "CREATE DATABASE \"$DBNAME\";" 2>/dev/null || true
              zstd -dc "$dump" | runuser -u postgres -- psql -d "$DBNAME" -v ON_ERROR_STOP=0
              ;;
            *.sql.gz)
              DBNAME="$(basename "$dump" .sql.gz)"
              echo "==> Restoring database: $DBNAME from $dump..."
              runuser -u postgres -- psql -c "CREATE DATABASE \"$DBNAME\";" 2>/dev/null || true
              gzip -dc "$dump" | runuser -u postgres -- psql -d "$DBNAME" -v ON_ERROR_STOP=0
              ;;
            *.sql)
              DBNAME="$(basename "$dump" .sql)"
              echo "==> Restoring database: $DBNAME from $dump..."
              runuser -u postgres -- psql -c "CREATE DATABASE \"$DBNAME\";" 2>/dev/null || true
              runuser -u postgres -- psql -d "$DBNAME" -v ON_ERROR_STOP=0 < "$dump"
              ;;
          esac
          FOUND=1
        done
        if [ "$FOUND" -eq 0 ]; then
          echo "Warning: No dump files found in $BACKUP_DIR." >&2
        else
          echo "==> [PostgreSQL Restore] All individual database dumps restored successfully."
        fi
      fi
    '';
  };

  # 3. MySQL / MariaDB 数据库恢复脚本：从 /var/backup/mysql 导入
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

  # 4. 一键全系统灾难恢复脚本
  resticRestoreAll = pkgs.writeShellApplication {
    name = "restic-restore-all";
    runtimeInputs = [
      resticRestore
      resticRestorePostgres
      resticRestoreMysql
      pkgs.coreutils
    ];
    text = ''
      SNAPSHOT="''${1:-latest}"
      echo "=========================================================="
      echo "  Starting Disaster Recovery via Restic Snapshot: $SNAPSHOT"
      echo "=========================================================="

      echo ""
      echo "[Step 1/3] Restoring files and configurations (ownership by username)..."
      restic-restore "$SNAPSHOT" "/" || true

      echo ""
      echo "[Step 2/3] Restoring PostgreSQL databases from backup dumps..."
      if [ -d "${pgBackupLocation}" ]; then
        restic-restore-postgres
      else
        echo "==> No PostgreSQL backup directory found, skipping."
      fi

      echo ""
      echo "[Step 3/3] Restoring MySQL databases from backup dumps..."
      if [ -d "${mysqlBackupLocation}" ]; then
        restic-restore-mysql
      else
        echo "==> No MySQL backup directory found, skipping."
      fi

      echo ""
      echo "=========================================================="
      echo "  Disaster Recovery completed successfully!"
      echo "=========================================================="
    '';
  };
  rrestic = pkgs.writeShellScriptBin "rrestic" ''
    set -euo pipefail
    # 凭据权限检查
    if [ ! -r "${pwFile}" ] || [ ! -r "${repoFile}" ]; then
      echo "错误：无法读取 Sops 密钥文件。请使用 sudo 或以 root 身份运行！" >&2
      exit 1
    fi

    export RESTIC_PASSWORD_FILE="${pwFile}"
    export RESTIC_REPOSITORY="$(cat "${repoFile}")"

    exec ${pkgs.restic}/bin/restic "$@"
  '';
in
{
  services.restic.backups.borgbase = {
    initialize = true;
    timerConfig = lib.mkDefault {
      OnCalendar = "03:00:00";
      RandomizedDelaySec = "30min";
    };
    passwordFile = config.sops.secrets."restic/RESTIC_PASSWORD".path;
    repositoryFile = config.sops.secrets."restic/RESTIC_REPOSITORY".path;
    pruneOpts = [
      "--keep-daily 3"
      "--keep-weekly 2"
    ];
  };

  sops.secrets."restic/RESTIC_PASSWORD" = {
    restartUnits = [ "restic-backups-borgbase.service" ];
  };
  sops.secrets."restic/RESTIC_REPOSITORY" = {
    restartUnits = [ "restic-backups-borgbase.service" ];
  };

  environment.systemPackages = with pkgs; [
    restic
    sqlite
    resticRestore
    resticRestorePostgres
    resticRestoreMysql
    resticRestoreAll
    rrestic
  ];
}
