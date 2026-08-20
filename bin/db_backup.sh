#!/usr/bin/env bash
# 生产数据库每日备份脚本
# cron: 0 4 * * * /var/www/holdle_stock_prod/current/bin/db_backup.sh >> /var/www/holdle_stock_prod/shared/backups/cron.log 2>&1

set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"          # current 目录
SHARED_DIR="$(dirname "$APP_DIR")/shared"            # 持久目录
BACKUP_DIR="$SHARED_DIR/backups"
DB_NAME="stock_website_production"
DB_USER="stock_website"
DB_HOST="localhost"
RETENTION_DAYS=14
LOG_FILE="$BACKUP_DIR/backup.log"

command -v pg_dump >/dev/null || { echo "错误: 未找到 pg_dump"; exit 1; }

# 从 linked 的 .env.production 读取数据库密码（仅取这一行，避免 source 整个文件）
if [ -f "$APP_DIR/.env.production" ]; then
  export PGPASSWORD="$(grep -E '^STOCK_WEBSITE_DATABASE_PASSWORD=' "$APP_DIR/.env.production" | head -1 | cut -d= -f2-)"
fi
[ -n "${PGPASSWORD:-}" ] || { echo "错误: 未找到 STOCK_WEBSITE_DATABASE_PASSWORD"; exit 1; }

mkdir -p "$BACKUP_DIR"
STAMP="$(date +%Y%m%d_%H%M)"
FILE="$BACKUP_DIR/${DB_NAME}_${STAMP}.dump"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始备份 $DB_NAME → $FILE" | tee -a "$LOG_FILE"
if pg_dump -Fc -h "$DB_HOST" -U "$DB_USER" -f "$FILE" "$DB_NAME" 2>>"$LOG_FILE"; then
  SIZE="$(du -h "$FILE" | cut -f1)"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 备份成功 $FILE ($SIZE)" | tee -a "$LOG_FILE"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 备份失败: $FILE" | tee -a "$LOG_FILE"
  exit 1
fi

# 清理 N 天前的旧备份
find "$BACKUP_DIR" -name "${DB_NAME}_*.dump" -mtime +"$RETENTION_DAYS" -delete
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 清理完成（保留 ${RETENTION_DAYS} 天）" >> "$LOG_FILE"

# ── 异地备份钩子（本期不做，后续启用）──────────────
# 例：scp "$FILE" user@backup-host:/backups/ 或 上传 OSS/COS
