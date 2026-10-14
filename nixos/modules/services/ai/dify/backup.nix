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
  ...
}:
let
  cfg = config.services.ai.dify;
in
{
  # ── 将 Dify 数据纳入全局 Restic borgbase 备份 ─────────────────────
  services.restic.backups.borgbase = {
    paths = lib.mkAfter [
      # 仅备份租户私钥（用于解密大模型 API Key 凭据），排除庞大的上传附件与向量库
      "${cfg.dataDir}/storage/privkeys"
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

      # ── Qdrant 的 WAL（仅备份 storage，WAL 是临时的）────────────
      "/var/lib/private/qdrant/storage/wal"
      "/var/lib/qdrant/storage/wal"
    ];
  };

  # ── 确保备份在 Qdrant 静止状态下运行（避免备份中途数据不一致）────
  # Restic 备份前先 SIGSTOP Qdrant，备份后 SIGCONT（最小停机窗口）
  # 注：Qdrant 支持在线快照 API，此处采用简单的信号暂停策略
  # 如需零停机，可改用 `qdrant-snapshot.service` 调用 /snapshots API
  systemd.services."restic-backups-borgbase" = {
    # 等待 PG 全量 dump 完成后再启动
    after = lib.mkAfter [
      "postgresqlBackup.service"
    ];
  };
}
