#!/usr/bin/env bash
# Start CRM AWS resources (EC2 + scale EKS nodes back up)
# Run from project root: ./scripts/start-aws.sh
#
# Use after: ./scripts/stop-aws.sh
#
# Optional: AWS_PROFILE, AWS_REGION (default us-west-1)
# Optional: EKS_DESIRED_SIZE (default 2) - number of EKS nodes to start
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AWS_REGION="${AWS_REGION:-us-west-1}"
EKS_DESIRED_SIZE="${EKS_DESIRED_SIZE:-2}"

echo "==> Starting CRM AWS resources (region: $AWS_REGION)"
echo ""

# 1. Collect EC2 instance IDs from Terraform
cd "$PROJECT_ROOT/terraform/mysql"
INSTANCES=()
MASTER=$(terraform output -raw mysql_master_instance_id 2>/dev/null || true)
[[ -n "$MASTER" && "$MASTER" != "None" ]] && INSTANCES+=("$MASTER")
for id in $(terraform output -json mysql_replica_instance_ids 2>/dev/null | jq -r '.[]? // empty' 2>/dev/null || true); do
  [[ -n "$id" && "$id" != "null" ]] && INSTANCES+=("$id")
done
BASTION=$(terraform output -raw bastion_instance_id 2>/dev/null || aws ec2 describe-instances --region "$AWS_REGION" --filters "Name=tag:Name,Values=crm-prod-bastion" "Name=instance-state-name,Values=stopped,running,pending" --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || true)
[[ -n "$BASTION" && "$BASTION" != "None" && "$BASTION" != "null" ]] && INSTANCES+=("$BASTION")

# 2. Start EC2 instances (MySQL first, then bastion)
if [[ ${#INSTANCES[@]} -gt 0 ]]; then
  echo "==> [1/2] Starting EC2 instances..."
  aws ec2 start-instances --region "$AWS_REGION" --instance-ids "${INSTANCES[@]}"
  echo "    Waiting for instances to run..."
  aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "${INSTANCES[@]}"
  echo "    Done"
  echo "    Waiting 30s for MySQL/bootstrap..."
  sleep 30
else
  echo "==> [1/2] No EC2 instances found"
fi

# 3. Scale EKS node group back up
echo ""
echo "==> [2/2] Scaling EKS node group to $EKS_DESIRED_SIZE..."
cd "$PROJECT_ROOT/terraform/eks"
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "crm-prod-eks")
NODEGROUP=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" --query 'nodegroups[0]' --output text 2>/dev/null || true)
if [[ -n "$NODEGROUP" && "$NODEGROUP" != "None" && "$NODEGROUP" != "null" ]]; then
  aws eks update-nodegroup-config --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP" \
    --scaling-config minSize=0,maxSize=3,desiredSize=$EKS_DESIRED_SIZE --region "$AWS_REGION"
  echo "    Scaled $NODEGROUP to $EKS_DESIRED_SIZE"
  echo "    Waiting for nodes (1-3 min)..."
  aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" 2>/dev/null || true
  for _ in $(seq 1 36); do
    READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c Ready || true)
    [[ "${READY:-0}" -ge "$EKS_DESIRED_SIZE" ]] && break
    sleep 5
  done
  kubectl get nodes 2>/dev/null || echo "    (Run: aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME)"
else
  echo "    EKS cluster or node group not found"
fi

# 4. Output CRM URL (LoadBalancer may take 1-2 min)
echo ""
echo "==> Started."
CRM_HOST=""
for _ in $(seq 1 24); do
  CRM_HOST=$(kubectl get svc crm-public -n crm -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [[ -n "$CRM_HOST" ]] && break
  sleep 5
done
if [[ -n "$CRM_HOST" ]]; then
  echo "    CRM URL: http://$CRM_HOST"
  echo "    Login: admin@crm.local / changeme"
else
  echo "    CRM URL: kubectl get svc crm-public -n crm (may take 1-2 min)"
fi
echo "    Bastion: cd terraform/mysql && terraform output bastion_ssh_command"
