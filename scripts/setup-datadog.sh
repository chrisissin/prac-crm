#!/usr/bin/env bash
# Datadog setup - Agent on EKS + MySQL DBM
# Requires: Terraform, kubectl, EKS cluster, MySQL deployed
#
# Set before running:
#   export DD_API_KEY="<datadog-api-key>"
#   export DD_APP_KEY="<datadog-app-key>"
#   export EKS_CLUSTER_NAME="<eks-cluster-name>"
#   export MYSQL_DATADOG_PASSWORD="<password-for-datadog-mysql-user>"
#
# Optional:
#   export MYSQL_MASTER_HOST="10.0.1.50"           # auto from terraform/mysql if not set
#   export MYSQL_REPLICA_HOSTS="10.0.2.50 10.0.2.51"  # space-separated
#   export DD_SITE="datadoghq.com"                 # or datadoghq.eu, us5.datadoghq.com
#   export AWS_REGION="us-west-1"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DD_SITE="${DD_SITE:-datadoghq.com}"
AWS_REGION="${AWS_REGION:-us-west-1}"

echo "==> Datadog Setup"
echo "    Project root: $PROJECT_ROOT"
echo ""

# Check required tools
for cmd in terraform kubectl; do
  command -v $cmd &>/dev/null || { echo "Missing: $cmd"; exit 1; }
done

# Required env vars
[[ -n "${DD_API_KEY:-}" ]]    || { echo "Set DD_API_KEY"; exit 1; }
[[ -n "${DD_APP_KEY:-}" ]]    || { echo "Set DD_APP_KEY"; exit 1; }
[[ -n "${EKS_CLUSTER_NAME:-}" ]] || { echo "Set EKS_CLUSTER_NAME"; exit 1; }
[[ -n "${MYSQL_DATADOG_PASSWORD:-}" ]] || { echo "Set MYSQL_DATADOG_PASSWORD"; exit 1; }

# Get MySQL hosts from terraform if not set
if [[ -z "${MYSQL_MASTER_HOST:-}" ]]; then
  echo "==> [1/4] Getting MySQL host from terraform/mysql..."
  cd "$PROJECT_ROOT/terraform/mysql"
  if terraform output -raw mysql_master_private_ip 2>/dev/null; then
    MYSQL_MASTER_HOST=$(terraform output -raw mysql_master_private_ip)
    echo "    MySQL master: $MYSQL_MASTER_HOST"
  else
    echo "    Run terraform apply in terraform/mysql first, or set MYSQL_MASTER_HOST"
    exit 1
  fi
else
  echo "==> [1/4] Using MYSQL_MASTER_HOST=$MYSQL_MASTER_HOST"
fi

# Replica hosts (optional)
if [[ -z "${MYSQL_REPLICA_HOSTS:-}" ]] && [[ -d "$PROJECT_ROOT/terraform/mysql" ]]; then
  REPLICAS=$(cd "$PROJECT_ROOT/terraform/mysql" && terraform output -json mysql_replica_private_ips 2>/dev/null | tr -d '[]",' | xargs)
  [[ -n "$REPLICAS" ]] && MYSQL_REPLICA_HOSTS="$REPLICAS"
fi

# Build tfvars
echo ""
echo "==> [2/4] Configuring Terraform..."
cd "$PROJECT_ROOT/terraform/datadog"

cat > terraform.tfvars << TFVARS
datadog_api_key        = "${DD_API_KEY}"
datadog_app_key        = "${DD_APP_KEY}"
datadog_site           = "${DD_SITE}"
cluster_name           = "${EKS_CLUSTER_NAME}"
mysql_master_host      = "${MYSQL_MASTER_HOST}"
mysql_datadog_password = "${MYSQL_DATADOG_PASSWORD}"
aws_region             = "${AWS_REGION}"
environment            = "prod"
TFVARS

if [[ -n "${MYSQL_REPLICA_HOSTS:-}" ]]; then
  # Convert space-separated to JSON array
  REPLICA_JSON="["
  for h in $MYSQL_REPLICA_HOSTS; do
    [[ "$REPLICA_JSON" != "[" ]] && REPLICA_JSON+=", "
    REPLICA_JSON+="\"$h\""
  done
  REPLICA_JSON+="]"
  echo "mysql_replica_hosts = $REPLICA_JSON" >> terraform.tfvars
fi

echo "    terraform.tfvars created"

# Terraform init
echo ""
echo "==> [3/4] Terraform init..."
terraform init

# Apply
echo ""
echo "==> [4/4] Terraform apply..."
terraform apply -auto-approve

echo ""
echo "==> Datadog setup complete!"
echo ""
echo "  Verify: Datadog UI → Databases → MySQL"
echo "  Agent:  kubectl exec -it -n datadog daemonset/datadog-agent -- agent status"
echo ""
