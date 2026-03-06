#!/usr/bin/env bash
# Fix CRM K8s secret when MySQL connection fails (500 after login)
# Run from project root. Requires: kubectl, terraform, TF_VAR_mysql_app_password set.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AWS_REGION="${AWS_REGION:-us-west-1}"

cd "$PROJECT_ROOT/terraform/mysql"
MYSQL_HOST=$(terraform output -raw mysql_master_private_ip 2>/dev/null || true)
[[ -z "$MYSQL_HOST" ]] && { echo "Run from terraform/mysql with applied state, or set MYSQL_HOST"; exit 1; }

MYSQL_PASSWORD="${TF_VAR_mysql_app_password:-}"
[[ -z "$MYSQL_PASSWORD" ]] && { echo "Set TF_VAR_mysql_app_password"; exit 1; }

SECRET_KEY_BASE=$(cd "$PROJECT_ROOT/crm" && bundle exec rails secret 2>/dev/null || echo "replace-with-rails-secret")

echo "Updating crm-secrets with DATABASE_HOST=$MYSQL_HOST"
kubectl create secret generic crm-secrets -n crm \
  --from-literal=DATABASE_USERNAME=crm_app \
  --from-literal=DATABASE_PASSWORD="$MYSQL_PASSWORD" \
  --from-literal=DATABASE_HOST="$MYSQL_HOST" \
  --from-literal=DATABASE_NAME=crm_production \
  --from-literal=SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Restarting CRM deployment..."
kubectl rollout restart deployment/crm -n crm
kubectl rollout status deployment/crm -n crm --timeout=120s

echo "Done. Try logging in again."
