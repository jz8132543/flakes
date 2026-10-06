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

  # 1. 灾难恢复脚本：按用户名恢复文件所有权 (--ownership-by-name)
  resticRestore = pkgs.writeShellApplication {
    name = "restic-restore";
    runtimeInputs = with pkgs; [
      config.services.restic.backups.borgbase.package
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

      restic restore "$RESTORE_TARGET" \
        --target "$TARGET" \
        --ownership-by-name \
        --verify

      echo "==> [Restic Restore] Files restored successfully."
    '';
  };

  # 2. PostgreSQL 数据库恢复脚本：从 /var/backup/postgresql 导入
  resticRestorePostgres = pkgs.writeShellApplication {
    name = "restic-restore-postgres";
    runtimeInputs = with pkgs; [
      (config.services.postgresql.package or postgresql)
      zstd
      coreutils
      util-linux
    ];
    text = ''
      BACKUP_DIR="${pgBackupLocation}"

      if [ ! -d "$BACKUP_DIR" ]; then
        echo "Error: PostgreSQL backup directory not found at $BACKUP_DIR" >&2
        exit 1
      fi

      echo "==> [PostgreSQL Restore] Waiting for PostgreSQL service to be ready..."
      until pg_isready -h /run/postgresql -q; do
        sleep 1
      done

      # 优先恢复全库转储 all.sql.zst (当 backupAll = true 时由 services.postgresqlBackup 生成)
      if [ -f "$BACKUP_DIR/all.sql.zst" ]; then
        echo "==> Found $BACKUP_DIR/all.sql.zst. Restoring full cluster dump..."
        zstd -dc "$BACKUP_DIR/all.sql.zst" | runuser -u postgres -- psql -v ON_ERROR_STOP=0
        echo "==> [PostgreSQL Restore] Full cluster dump restore completed."
      elif [ -f "$BACKUP_DIR/all.sql" ]; then
        echo "==> Found $BACKUP_DIR/all.sql. Restoring full cluster dump..."
        runuser -u postgres -- psql -v ON_ERROR_STOP=0 < "$BACKUP_DIR/all.sql"
        echo "==> [PostgreSQL Restore] Full cluster dump restore completed."
      else
        echo "==> Searching for individual database dumps in $BACKUP_DIR..."
        FOUND=0
        for dump in "$BACKUP_DIR"/*.sql.zst; do
          [ -f "$dump" ] || continue
          DBNAME="$(basename "$dump" .sql.zst)"
          echo "==> Restoring database: $DBNAME from $dump..."
          runuser -u postgres -- psql -c "CREATE DATABASE \"$DBNAME\";" 2>/dev/null || true
          zstd -dc "$dump" | runuser -u postgres -- psql -d "$DBNAME" -v ON_ERROR_STOP=0
          FOUND=1
        done
        if [ "$FOUND" -eq 0 ]; then
          echo "Warning: No .sql.zst dump files found in $BACKUP_DIR." >&2
        else
          echo "==> [PostgreSQL Restore] All individual database dumps restored successfully."
        fi
      fi
    '';
  };

  # 3. 一键全系统灾难恢复脚本
  resticRestoreAll = pkgs.writeShellApplication {
    name = "restic-restore-all";
    runtimeInputs = [
      resticRestore
      resticRestorePostgres
      pkgs.coreutils
    ];
    text = ''
      SNAPSHOT="''${1:-latest}"
      echo "=========================================================="
      echo "  Starting Disaster Recovery via Restic Snapshot: $SNAPSHOT"
      echo "=========================================================="

      echo ""
      echo "[Step 1/2] Restoring files and configurations (ownership by username)..."
      restic-restore "$SNAPSHOT" "/"

      echo ""
      echo "[Step 2/2] Restoring PostgreSQL databases from backup dumps..."
      restic-restore-postgres

      echo ""
      echo "=========================================================="
      echo "  Disaster Recovery completed successfully!"
      echo "=========================================================="
    '';
  };
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
    resticRestoreAll
  ];
}
