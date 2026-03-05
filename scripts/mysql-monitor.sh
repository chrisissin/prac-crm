#!/usr/bin/env bash
# MySQL Health Monitor Script
# Checks replication status, connections, and basic metrics
# Usage: ./mysql-monitor.sh [local|replication|full]
# Can be run from bastion or via SSM; set MYSQL_HOST for remote checks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/mysql-ops.conf"
ALERT_EMAIL="${ALERT_EMAIL:-}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"

[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MODE="${1:-full}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

alert() {
  local msg="$1"
  log "ALERT: $msg"
  [[ -n "$ALERT_EMAIL" ]] && echo "$msg" | mail -s "MySQL Alert" "$ALERT_EMAIL" 2>/dev/null || true
  [[ -n "$SLACK_WEBHOOK" ]] && curl -s -X POST -H 'Content-type: application/json' \
    --data "{\"text\":\"MySQL Alert: $msg\"}" "$SLACK_WEBHOOK" 2>/dev/null || true
}

mysql_cmd() {
  if [[ -n "$MYSQL_PASSWORD" ]]; then
    mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -N -e "$1" 2>/dev/null
  else
    mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -S /var/run/mysqld/mysqld.sock -N -e "$1" 2>/dev/null
  fi
}

check_connection() {
  if mysql_cmd "SELECT 1" &>/dev/null; then
    log "OK: MySQL is reachable"
    return 0
  else
    alert "MySQL is not reachable at $MYSQL_HOST:$MYSQL_PORT"
    return 1
  fi
}

check_replication() {
  local role
  role=$(mysql_cmd "SELECT @@read_only" 2>/dev/null || echo "?")
  local slave_status
  slave_status=$(mysql_cmd "SHOW SLAVE STATUS\G" 2>/dev/null || true)

  if [[ -n "$slave_status" ]]; then
    # Replica
    local io_running
    local sql_running
    local lag
    io_running=$(echo "$slave_status" | grep "Slave_IO_Running:" | awk '{print $2}')
    sql_running=$(echo "$slave_status" | grep "Slave_SQL_Running:" | awk '{print $2}')
    lag=$(mysql_cmd "SHOW SLAVE STATUS\G" 2>/dev/null | grep "Seconds_Behind_Master:" | awk '{print $2}')

    if [[ "$io_running" == "Yes" ]] && [[ "$sql_running" == "Yes" ]]; then
      log "OK: Replication is running (lag: ${lag:-0}s)"
      if [[ -n "$lag" ]] && [[ "$lag" -gt 60 ]]; then
        alert "Replication lag is high: ${lag}s"
      fi
    else
      alert "Replication is broken - IO: $io_running SQL: $sql_running"
      return 1
    fi
  else
    log "OK: Master node (no slave status)"
  fi
  return 0
}

check_connections() {
  local max_conn
  local curr_conn
  max_conn=$(mysql_cmd "SELECT @@max_connections" 2>/dev/null || echo "0")
  curr_conn=$(mysql_cmd "SHOW STATUS LIKE 'Threads_connected'" 2>/dev/null | awk '{print $2}')
  local pct=0
  [[ "$max_conn" -gt 0 ]] && pct=$((curr_conn * 100 / max_conn))

  log "Connections: $curr_conn / $max_conn ($pct%)"
  if [[ "$pct" -gt 80 ]]; then
    alert "Connection usage high: $pct%"
  fi
}

check_slave_lag() {
  mysql_cmd "SHOW SLAVE STATUS\G" 2>/dev/null | grep -E "Seconds_Behind_Master|Slave_IO_Running|Slave_SQL_Running" || true
}

check_disk() {
  local data_dir
  data_dir=$(mysql_cmd "SELECT @@datadir" 2>/dev/null || echo "/var/lib/mysql")
  local usage
  usage=$(df -h "$data_dir" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
  log "Disk usage (data): ${usage}%"
  [[ "$usage" -gt 85 ]] && alert "Disk usage high: ${usage}%"
}

check_queries() {
  local long_running
  long_running=$(mysql_cmd "SELECT COUNT(*) FROM information_schema.processlist WHERE command != 'Sleep' AND time > 300" 2>/dev/null || echo "0")
  [[ "$long_running" -gt 0 ]] && alert "Long-running queries detected: $long_running"
}

# Main
case "$MODE" in
  local)
    check_connection
    check_connections
    check_disk
    ;;
  replication)
    check_connection
    check_replication
    check_slave_lag
    ;;
  full)
    check_connection || exit 1
    check_connections
    check_replication
    check_disk
    check_queries
    log "Monitor completed"
    ;;
  *)
    echo "Usage: $0 [local|replication|full]"
    exit 1
    ;;
esac
