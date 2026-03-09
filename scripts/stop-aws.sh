#!/usr/bin/env bash
# Stop CRM AWS resources to save costs (EC2 + scale EKS nodes to 0)
# Run from project root: ./scripts/stop-aws.sh
#
# Resume with: ./scripts/start-aws.sh
# Private IPs are preserved; services work after start.
#
# Optional: AWS_PROFILE, AWS_REGION (default us-west-1)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AWS_REGION="${AWS_REGION:-us-west-1}"

echo "==> Stopping CRM AWS resources (region: $AWS_REGION)"
echo ""

# 1. Collect EC2 instance IDs from Terraform
cd "$PROJECT_ROOT/terraform/mysql"
INSTANCES=()
MASTER=$(terraform output -raw mysql_master_instance_id 2>/dev/null || true)
[[ -n "$MASTER" && "$MASTER" != "None" ]] && INSTANCES+=("$MASTER")
for id in $(terraform output -json mysql_replica_instance_ids 2>/dev/null | jq -r '.[]? // empty' 2>/dev/null || true); do
  [[ -n "$id" && "$id" != "null" ]] && INSTANCES+=("$id")
done
BASTION=$(terraform output -raw bastion_instance_id 2>/dev/null || aws ec2 describe-instances --region "$AWS_REGION" --filters "Name=tag:Name,Values=crm-prod-bastion" "Name=instance-state-name,Values=running,pending,stopping" --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || true)
[[ -n "$BASTION" && "$BASTION" != "None" && "$BASTION" != "null" ]] && INSTANCES+=("$BASTION")

# 2. Stop EC2 instances
if [[ ${#INSTANCES[@]} -gt 0 ]]; then
  echo "==> [1/2] Stopping EC2 instances..."
  for id in "${INSTANCES[@]}"; do
    echo "    Stopping $id"
  done
  aws ec2 stop-instances --region "$AWS_REGION" --instance-ids "${INSTANCES[@]}"
  echo "    Waiting for instances to stop..."
  aws ec2 wait instance-stopped --region "$AWS_REGION" --instance-ids "${INSTANCES[@]}"
  echo "    Done"
else
  echo "==> [1/2] No EC2 instances found (run terraform apply in terraform/mysql first)"
fi

# 3. Scale EKS node group to 0
echo ""
echo "==> [2/2] Scaling EKS node group to 0..."
cd "$PROJECT_ROOT/terraform/eks"
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "crm-prod-eks")
NODEGROUP=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" --query 'nodegroups[0]' --output text 2>/dev/null || true)
if [[ -n "$NODEGROUP" && "$NODEGROUP" != "None" && "$NODEGROUP" != "null" ]]; then
  aws eks update-nodegroup-config --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP" \
    --scaling-config minSize=0,maxSize=3,desiredSize=0 --region "$AWS_REGION"
  echo "    Scaled $NODEGROUP to 0"
else
  echo "    EKS cluster or node group not found (skip)"
fi

echo ""
echo "==> Stopped. EBS storage and EKS control plane still incur cost."
echo "    Resume: ./scripts/start-aws.sh"
