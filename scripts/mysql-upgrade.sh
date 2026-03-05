#!/usr/bin/env bash
# MySQL Upgrade Script
# Performs in-place upgrade with backup and rollback capability
# Usage: ./mysql-upgrade.sh [check|backup|upgrade|rollback]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/mysql-ops.conf"
BACKUP_DIR="${BACKUP_DIR:-/backup/mysql}"
ROLLBACK_FILE="${BACKUP_DIR}/.rollback_info"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
  log "ERROR: $*" >&2
  exit 1
}

[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

ACTION="${1:-check}"
CURRENT_VERSION="$(mysql -V 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)"

case "$ACTION" in
  check)
    log "Current MySQL version: $CURRENT_VERSION"
    log "Checking compatibility..."
    mysql -e "SELECT @@version;" 2>/dev/null || error "Cannot connect to MySQL"
    mysql -e "SHOW VARIABLES LIKE 'innodb_file_format';" 2>/dev/null
    log "Run: ./mysql-upgrade.sh backup  # before upgrading"
    ;;

  backup)
    log "Creating pre-upgrade backup..."
    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="${BACKUP_DIR}/pre-upgrade-$(date +%Y%m%d_%H%M%S).sql.gz"
    mysqldump -u root -p --all-databases --routines --triggers --events \
      | gzip > "$BACKUP_FILE"
    echo "BACKUP_FILE=$BACKUP_FILE" > "$ROLLBACK_FILE"
    echo "CURRENT_VERSION=$CURRENT_VERSION" >> "$ROLLBACK_FILE"
    log "Backup saved to $BACKUP_FILE"
    log "Rollback info in $ROLLBACK_FILE"
    ;;

  upgrade)
    log "Upgrading MySQL..."
    # Stop MySQL
    systemctl stop mysql || service mysql stop

    # Backup my.cnf
    cp /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf.bak.$(date +%Y%m%d)

    # Upgrade packages (Ubuntu/Debian)
    if command -v apt-get &>/dev/null; then
      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y mysql-server mysql-client || true
    # Amazon Linux / RHEL
    elif command -v yum &>/dev/null; then
      yum update -y mysql* mariadb* || true
    fi

    # Run mysql_upgrade
    mysql_upgrade -u root -p 2>/dev/null || mysql_upgrade

    # Start MySQL
    systemctl start mysql || service mysql start

    NEW_VERSION="$(mysql -V 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)"
    log "Upgrade complete. New version: $NEW_VERSION"
    ;;

  rollback)
    [[ -f "$ROLLBACK_FILE" ]] || error "No rollback info found. Run backup first."
    source "$ROLLBACK_FILE"
    log "Rolling back using $BACKUP_FILE"
    systemctl stop mysql || service mysql stop
    # Restore involves: remove new data dir, restore from backup
    log "Manual steps required:"
    log "1. mv /var/lib/mysql /var/lib/mysql.new"
    log "2. mysql_install_db"
    log "3. zcat $BACKUP_FILE | mysql -u root -p"
    log "4. systemctl start mysql"
    ;;

  *)
    error "Unknown action: $ACTION (use check|backup|upgrade|rollback)"
    ;;
esac
