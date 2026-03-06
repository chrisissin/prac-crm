#!/usr/bin/env bash
# Teardown CRM on AWS - delete EKS, then MySQL (VPC, EC2, etc.)
# Run from project root: ./scripts/teardown-aws.sh
#
# Optional: AWS_PROFILE, AWS_REGION (default us-west-1)
# Use the region where resources were created. If migrating regions, set AWS_REGION to the OLD region for teardown.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AWS_REGION="${AWS_REGION:-us-west-1}"

echo "==> CRM AWS Teardown (region: $AWS_REGION)"
echo ""

# 1. Delete K8s resources (Load Balancer, etc.) so Terraform can delete subnets
echo "==> [1/6] Deleting Kubernetes resources..."
if kubectl get namespace crm &>/dev/null 2>&1; then
  kubectl delete namespace crm --timeout=120s || true
  echo "    Deleted crm namespace"
else
  echo "    crm namespace not found or cluster unreachable (skip)"
fi

# 2. EKS first (depends on VPC subnets)
echo ""
echo "==> [2/6] Terraform destroy: EKS..."
cd "$PROJECT_ROOT/terraform/eks"
if terraform state list &>/dev/null 2>&1; then
  terraform destroy -auto-approve -var="aws_region=$AWS_REGION" || true
  echo "    EKS destroyed"
else
  echo "    EKS Terraform state empty"
  # EKS cluster may still exist; delete by name if found
  EKS_CLUSTER=$(aws eks list-clusters --region "$AWS_REGION" --query "clusters[?contains(@,'crm-prod-eks')]" --output text 2>/dev/null | head -1)
  if [[ -n "$EKS_CLUSTER" ]]; then
    echo "    Deleting orphaned EKS cluster: $EKS_CLUSTER..."
    aws eks delete-cluster --region "$AWS_REGION" --name "$EKS_CLUSTER" 2>/dev/null || true
    echo "    Waiting for EKS cluster deletion (up to 15 min)..."
    aws eks wait cluster-deleted --region "$AWS_REGION" --name "$EKS_CLUSTER" 2>/dev/null || sleep 300
  fi
fi

# 3. Pre-cleanup: remove resources that block subnet/VPC deletion (instances, NAT, EIPs, LBs)
echo ""
echo "==> [3/6] Pre-cleanup (instances, NAT, EIPs, LBs)..."
cd "$PROJECT_ROOT/terraform/mysql"
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || true)
[[ -z "$VPC_ID" || "$VPC_ID" == "None" ]] && VPC_ID=$(aws ec2 describe-vpcs --region "$AWS_REGION" --filters "Name=tag:Name,Values=crm-prod-vpc" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)
[[ "$VPC_ID" == "None" ]] && VPC_ID=""
if [[ -n "$VPC_ID" ]]; then
  # Terminate all EC2 instances in VPC (subnets cannot be deleted with instances)
  for iid in $(aws ec2 describe-instances --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running,pending,stopping" \
    --query 'Reservations[*].Instances[*].InstanceId' --output text 2>/dev/null || true); do
    [[ -n "${iid:-}" && "${iid:-}" != "None" ]] || continue
    echo "    Terminating instance $iid..."
    aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids "$iid" 2>/dev/null || true
  done
  # Delete Classic ELBs (K8s LoadBalancer creates these)
  for lb in $(aws elb describe-load-balancers --region "$AWS_REGION" --query \
    "LoadBalancerDescriptions[?VPCId=='$VPC_ID'].LoadBalancerName" --output text 2>/dev/null || true); do
    [[ -n "${lb:-}" && "${lb:-}" != "None" ]] || continue
    echo "    Deleting Classic LB $lb..."
    aws elb delete-load-balancer --region "$AWS_REGION" --load-balancer-name "$lb" 2>/dev/null || true
  done
  # Delete ALB/NLB
  for lb in $(aws elbv2 describe-load-balancers --region "$AWS_REGION" --query \
    "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output text 2>/dev/null || true); do
    [[ -n "${lb:-}" && "${lb:-}" != "None" ]] || continue
    echo "    Deleting LB $lb..."
    aws elbv2 delete-load-balancer --region "$AWS_REGION" --load-balancer-arn "$lb" 2>/dev/null || true
  done
  # Capture EIP allocation IDs from NAT gateways before deleting
  NAT_EIPS=$(aws ec2 describe-nat-gateways --region "$AWS_REGION" \
    --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending" \
    --query 'NatGateways[*].NatGatewayAddresses[0].AllocationId' --output text 2>/dev/null || true)
  # Delete NAT gateways (they hold EIPs and block IGW detach)
  for nat in $(aws ec2 describe-nat-gateways --region "$AWS_REGION" \
    --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending" \
    --query 'NatGateways[*].NatGatewayId' --output text 2>/dev/null || true); do
    [[ -n "${nat:-}" && "${nat:-}" != "None" ]] || continue
    echo "    Deleting NAT gateway $nat..."
    aws ec2 delete-nat-gateway --region "$AWS_REGION" --nat-gateway-id "$nat"
  done
  # Wait for instances and NAT (instances must terminate before subnets can be deleted)
  echo "    Waiting 180s for instances and NAT gateways to delete..."
  sleep 180
  # Disassociate EIPs in our VPC (IGW cannot detach until no "mapped public addresses")
  OUR_INSTANCES=$(aws ec2 describe-instances --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" --query 'Reservations[*].Instances[*].InstanceId' --output text 2>/dev/null | tr '\t' ' ')
  OUR_ENIS=$(aws ec2 describe-network-interfaces --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text 2>/dev/null | tr '\t' ' ')
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    assoc_id=$(echo "$line" | cut -f1)
    iid=$(echo "$line" | cut -f2)
    eni=$(echo "$line" | cut -f3)
    in_our_vpc=false
    if [[ -n "$iid" ]] && echo " $OUR_INSTANCES " | grep -qF " $iid "; then
      in_our_vpc=true
    elif [[ -n "$eni" ]] && echo " $OUR_ENIS " | grep -qF " $eni "; then
      in_our_vpc=true
    fi
    if [[ "$in_our_vpc" == "true" ]]; then
      echo "    Disassociating EIP $assoc_id..."
      aws ec2 disassociate-address --region "$AWS_REGION" --association-id "$assoc_id" 2>/dev/null || true
    fi
  done < <(aws ec2 describe-addresses --region "$AWS_REGION" --query \
    "Addresses[?AssociationId!=null].[AssociationId,InstanceId,NetworkInterfaceId]" --output text 2>/dev/null)
  sleep 10
  # Release NAT EIPs and any other unassociated EIPs
  for alloc in $NAT_EIPS; do
    [[ -n "$alloc" && "$alloc" != "None" ]] || continue
    aws ec2 release-address --region "$AWS_REGION" --allocation-id "$alloc" 2>/dev/null || true
  done
  for alloc in $(aws ec2 describe-addresses --region "$AWS_REGION" \
    --filters "Name=domain,Values=vpc" --query "Addresses[?AssociationId==null].AllocationId" --output text 2>/dev/null); do
    [[ -n "$alloc" ]] || continue
    aws ec2 release-address --region "$AWS_REGION" --allocation-id "$alloc" 2>/dev/null || true
  done
  echo "    Pre-cleanup done"
else
  echo "    No VPC in state (skip pre-cleanup)"
fi

# 4. MySQL (VPC, EC2, subnets, etc.)
echo ""
echo "==> [4/6] Terraform destroy: MySQL..."
cd "$PROJECT_ROOT/terraform/mysql"
if terraform state list &>/dev/null 2>&1; then
  terraform destroy -auto-approve -var="aws_region=$AWS_REGION" || true
  echo "    MySQL infra destroyed"
else
  echo "    MySQL state empty (skip)"
fi

echo ""
echo "==> [5/6] Cleanup..."
# Remove ECR repo (optional - comment out if you want to keep the image)
aws ecr delete-repository --repository-name crm --region "$AWS_REGION" --force 2>/dev/null || true

echo ""
echo "==> Teardown complete."
