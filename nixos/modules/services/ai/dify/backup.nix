# ─────────────────────────────────────────────────────────────────────────────
# services/ai/dify/backup.nix
#
# Dify 灾备配置（Restic 增量备份）
#
# 备份内容：
#   ✅ /var/lib/dify/storage    — 用户上传的文件/附件
#   ✅ /var/backup/postgresql   — PG 逻辑 dump（含 dify 库的聊天记录/工作流）
#   ✅ /var/lib/dify/qdrant     — Qdrant 向量索引持久化目录
#
# 明确排除（节省带宽，避免无意义的快照膨胀）：
#   ❌ Redis dump / AOF（已禁用，无需备份）
#   ❌ Celery 队列日志（瞬态，可重建）
#   ❌ /var/lib/containers      — 容器镜像图层（巨大，可随时 pull）
#   ❌ Next.js .next 缓存卷
#   ❌ 模型权重缓存（Hugging Face cache 等）
# ─────────────────────────────────────────────────────────────────────────────
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ai.dify;
  qdrantPort = config.ports.dify-qdrant;
  qdrantBackupDir = "/var/backup/qdrant";
in
{
  # ── 创建 Qdrant 备份目录 ───────────────────────────────────────────
  systemd.tmpfiles.rules = [
    "d ${qdrantBackupDir} 0750 root root - -"
  ];

  # ── Qdrant 全量零停机热快照服务 (调用 /snapshots API) ─────────────
  systemd.services.qdrant-backup = {
    description = "Qdrant Vector Database Automated Snapshot Backup";
    after = [ "qdrant.service" ];
    requires = [ "qdrant.service" ];
    path = with pkgs; [
      curl
      jq
      coreutils
      findutils
    ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };

    script = ''
      set -euo pipefail

      DATE=$(date +%Y%m%d_%H%M%S)
      echo "[qdrant-backup] Starting full snapshot at $DATE..."

      # 检查 Qdrant 服务是否正常
      if ! curl -sf "http://127.0.0.1:${toString qdrantPort}/healthz" >/dev/null; then
        echo "[qdrant-backup] Qdrant is not responding, skipping snapshot." >&2
        exit 1
      fi

      # 调用 Qdrant 全量存储快照 API
      SNAPSHOT_INFO=$(curl -sf -X POST "http://127.0.0.1:${toString qdrantPort}/snapshots")
      SNAPSHOT_NAME=$(echo "$SNAPSHOT_INFO" | jq -r '.result.name')

      if [ -n "$SNAPSHOT_NAME" ] && [ "$SNAPSHOT_NAME" != "null" ]; then
        echo "[qdrant-backup] Generated snapshot: $SNAPSHOT_NAME, downloading..."
        curl -sf "http://127.0.0.1:${toString qdrantPort}/snapshots/$SNAPSHOT_NAME" \
          -o "${qdrantBackupDir}/qdrant_all_$DATE.snapshot"

        # 删除 Qdrant 内部临时快照以释放 storage 内部冗余空间
        curl -sf -X DELETE "http://127.0.0.1:${toString qdrantPort}/snapshots/$SNAPSHOT_NAME" || true
        echo "[qdrant-backup] Successfully saved to ${qdrantBackupDir}/qdrant_all_$DATE.snapshot"
      else
        echo "[qdrant-backup] Snapshot API response did not contain a valid snapshot name: $SNAPSHOT_INFO" >&2
        exit 1
      fi

      # 轮转策略：自动删除 7 天前的历史快照
      find "${qdrantBackupDir}" -name "qdrant_all_*.snapshot" -type f -mtime +7 -delete
      echo "[qdrant-backup] Qdrant snapshot backup completed."
    '';
  };

  # ── Qdrant 定时快照 Timer (与 postgresqlBackup 协同) ───────────────
  systemd.timers.qdrant-backup = {
    description = "Daily Qdrant backup timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "01:25:00";
      Persistent = true;
    };
  };

  # ── 将 Dify 私钥与 Qdrant 快照纳入全局 Restic borgbase 备份 ─────────
  services.restic.backups.borgbase = {
    paths = lib.mkAfter [
      # 仅备份租户私钥（用于解密大模型 API Key 凭据）
      "${cfg.dataDir}/storage/privkeys"
      # Qdrant 结构化快照存档目录
      qdrantBackupDir
    ];

    exclude = lib.mkAfter [
      # ── 容器运行时（禁止备份，几十GB，随时可 pull）──────────────
      "/var/lib/containers"
      "/run/containers"

      # ── Redis（无 AOF/RDB，无需备份）────────────────────────────
      "/var/lib/redis*"
      "/run/redis*"

      # ── Next.js 构建缓存 ─────────────────────────────────────────
      "${cfg.dataDir}/**/.next"
      "${cfg.dataDir}/**/node_modules"
      "${cfg.dataDir}/**/__pycache__"

      # ── Celery 任务队列日志（瞬态，无价值）──────────────────────
      "${cfg.dataDir}/**/celerybeat*"
      "${cfg.dataDir}/**/worker*.log"

      # ── Python/模型缓存 ──────────────────────────────────────────
      "/root/.cache/huggingface"
      "/root/.cache/torch"
      "${cfg.dataDir}/**/*.cache"

      # ── 排除 Qdrant 原生运行目录（已由 qdrant-backup 逻辑快照替代）──
      "/var/lib/private/qdrant"
      "/var/lib/qdrant"
    ];
  };

  # ── 确保备份在 PG 转储与 Qdrant 快照均完成后运行 ──────────────────
  systemd.services."restic-backups-borgbase" = {
    after = lib.mkAfter [
      "postgresqlBackup.service"
      "qdrant-backup.service"
    ];
  };
}
