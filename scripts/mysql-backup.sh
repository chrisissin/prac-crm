#!/usr/bin/env bash
# MySQL Backup Script
# Supports master and replica; uploads to S3
# Usage: ./mysql-backup.sh [full|incremental] [master|replica]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/mysql-ops.conf"
BACKUP_TYPE="${1:-full}"
ROLE="${2:-master}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/mysql-backup-${TIMESTAMP}.log"

# Load config if exists
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

# Defaults
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
MYSQL_SOCKET="${MYSQL_SOCKET:-/var/run/mysqld/mysqld.sock}"
BACKUP_DIR="${BACKUP_DIR:-/backup/mysql}"
S3_BUCKET="${S3_BUCKET:-}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
HOSTNAME_SHORT="$(hostname -s)"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
  log "ERROR: $*" >&2
  exit 1
}

[[ -d "$BACKUP_DIR" ]] || mkdir -p "$BACKUP_DIR"
cd "$BACKUP_DIR"

case "$BACKUP_TYPE" in
  full)
    log "Starting FULL backup ($ROLE)"
    BACKUP_FILE="mysql-full-${HOSTNAME_SHORT}-${TIMESTAMP}.sql.gz"

    if [[ -n "$MYSQL_PASSWORD" ]]; then
      MYSQL_OPTS="-u$MYSQL_USER -p$MYSQL_PASSWORD"
    else
      MYSQL_OPTS="-u$MYSQL_USER -S $MYSQL_SOCKET"
    fi

    log "Dumping to $BACKUP_FILE"
    mysqldump $MYSQL_OPTS \
      --single-transaction \
      --routines \
      --triggers \
      --events \
      --master-data=2 \
      --all-databases \
      --set-gtid-purged=OFF \
      2>/dev/null | gzip > "$BACKUP_FILE" || \
    mysqldump $MYSQL_OPTS \
      --single-transaction \
      --routines \
      --triggers \
      --events \
      --all-databases \
      2>/dev/null | gzip > "$BACKUP_FILE"

    log "Backup completed: $(du -h "$BACKUP_FILE" | cut -f1)"

    if [[ -n "$S3_BUCKET" ]] && command -v aws &>/dev/null; then
      log "Uploading to s3://$S3_BUCKET/backups/"
      aws s3 cp "$BACKUP_FILE" "s3://$S3_BUCKET/backups/${BACKUP_FILE}" --storage-class STANDARD_IA
      log "S3 upload completed"
    fi

    log "Pruning local backups older than $RETENTION_DAYS days"
    find "$BACKUP_DIR" -name "mysql-full-*.sql.gz" -mtime +$RETENTION_DAYS -delete
    ;;

  incremental)
    log "Starting INCREMENTAL backup ($ROLE)"
    # Flush and get binlog position
    BINLOG_DIR="/var/log/mysql"
    mysql -u$MYSQL_USER ${MYSQL_PASSWORD:+-p$MYSQL_PASSWORD} -e "FLUSH BINARY LOGS;"
    tar -czf "mysql-binlog-${HOSTNAME_SHORT}-${TIMESTAMP}.tar.gz" -C "$BINLOG_DIR" mysql-bin.* 2>/dev/null || true
    if [[ -n "$S3_BUCKET" ]] && command -v aws &>/dev/null; then
      aws s3 cp "mysql-binlog-${HOSTNAME_SHORT}-${TIMESTAMP}.tar.gz" "s3://$S3_BUCKET/backups/incremental/"
    fi
    log "Incremental backup completed"
    ;;

  *)
    error "Unknown backup type: $BACKUP_TYPE (use full or incremental)"
    ;;
esac

log "Backup script finished successfully"
