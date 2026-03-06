#!/usr/bin/env bash
# Create/fix crm_app user on MySQL master (when cloud-init didn't or Access denied)
# Run from project root. Requires: terraform, TF_VAR_mysql_root_password, TF_VAR_mysql_app_password

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AWS_REGION="${AWS_REGION:-us-west-1}"

cd "$PROJECT_ROOT/terraform/mysql"
INSTANCE_ID=$(terraform output -raw mysql_master_instance_id 2>/dev/null || true)
[[ -z "$INSTANCE_ID" ]] && { echo "Run from terraform/mysql with applied state"; exit 1; }

ROOT_PW="${TF_VAR_mysql_root_password:-}"
APP_PW="${TF_VAR_mysql_app_password:-}"
[[ -z "$ROOT_PW" ]] && { echo "Set TF_VAR_mysql_root_password"; exit 1; }
[[ -z "$APP_PW" ]] && { echo "Set TF_VAR_mysql_app_password"; exit 1; }

# Use mysql_native_password for better Rails/client compatibility (MySQL 8 default can cause Access denied)
SQL="CREATE DATABASE IF NOT EXISTS crm_production CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
DROP USER IF EXISTS 'crm_app'@'%';
CREATE USER 'crm_app'@'%' IDENTIFIED WITH mysql_native_password BY '${APP_PW}';
GRANT ALL PRIVILEGES ON crm_production.* TO 'crm_app'@'%';
FLUSH PRIVILEGES;"

# Base64 to avoid SSM JSON escaping; decode and run on instance
SQL_B64=$(echo "$SQL" | base64)
CMD="export MYSQL_PWD='${ROOT_PW}'; echo '${SQL_B64}' | base64 -d | sudo -E mysql -u root"

echo "Creating crm_app user on MySQL master ($INSTANCE_ID)..."
CMD_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["'"$CMD"'"]' \
  --region "$AWS_REGION" \
  --output text --query 'Command.CommandId')

echo "Waiting for command $CMD_ID..."
for _ in $(seq 1 12); do
  sleep 5
  STATUS=$(aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
    --region "$AWS_REGION" --query 'Status' --output text 2>/dev/null || echo "InProgress")
  case "$STATUS" in
    Success) echo "  Status: Success"; exit 0 ;;
    Failed)  echo "  Status: Failed"; exit 1 ;;
  esac
  echo "  Status: $STATUS (waiting...)"
done
echo "  Timed out. If migrations fail, run via bastion:"
echo "    ssh -A -J ubuntu@\$(cd $PROJECT_ROOT/terraform/mysql && terraform output -raw bastion_public_ip) ubuntu@\$(cd $PROJECT_ROOT/terraform/mysql && terraform output -raw mysql_master_private_ip)"
echo "    sudo mysql -u root -p'<root_pw>' -e \"CREATE DATABASE IF NOT EXISTS crm_production; DROP USER IF EXISTS 'crm_app'@'%'; CREATE USER 'crm_app'@'%' IDENTIFIED WITH mysql_native_password BY '<app_pw>'; GRANT ALL ON crm_production.* TO 'crm_app'@'%'; FLUSH PRIVILEGES;\""
exit 1
