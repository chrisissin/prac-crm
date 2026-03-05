#!/usr/bin/env bash
# Create IAM user with permissions for CRM AWS setup (Terraform + EKS)
# Must be run by root or a user with IAM admin (CreateUser, AttachUserPolicy)
#
# Usage:
#   ./scripts/setup-aws-iam-user.sh <username>
#   ./scripts/setup-aws-iam-user.sh chrisissin
#
# Use a profile with IAM admin rights (root or another admin user):
#   AWS_PROFILE=<admin-profile> ./scripts/setup-aws-iam-user.sh chrisissin
#
# If you only have root: run "aws configure" with root keys, then use default profile.

set -euo pipefail

USERNAME="${1:-}"
if [[ -z "$USERNAME" ]]; then
  echo "Usage: $0 <iam-username>"
  echo "  Example: $0 chrisissin"
  echo ""
  echo "Creates IAM user and attaches policies needed for:"
  echo "  - Terraform MySQL (EC2, VPC, S3, IAM, SSM)"
  echo "  - EKS/ECR (Docker push, kubectl)"
  exit 1
fi

# Policies required for full CRM AWS setup
# Use AdministratorAccess for simplicity, or uncomment LEAST_PRIVILEGE for granular
POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

# LEAST_PRIVILEGE="AmazonEC2FullAccess AmazonVPCFullAccess AmazonS3FullAccess IAMFullAccess AmazonSSMFullAccess AmazonEKSClusterPolicy AmazonEC2ContainerRegistryFullAccess"

echo "==> Creating IAM user: $USERNAME"
echo "  (Using: $(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo 'unknown identity'))"
echo ""

# Create user (ignore if exists)
aws iam create-user --user-name "$USERNAME" 2>/dev/null || echo "  User $USERNAME already exists"

# Attach AdministratorAccess
echo "  Attaching AdministratorAccess..."
ATTACH_ERR=$(aws iam attach-user-policy --user-name "$USERNAME" --policy-arn "$POLICY_ARN" 2>&1) && { echo "  OK"; true; } || {
  if aws iam list-attached-user-policies --user-name "$USERNAME" --query "AttachedPolicies[?PolicyArn=='$POLICY_ARN']" --output text 2>/dev/null | grep -q .; then
    echo "  OK (already attached)"
  else
    echo "  FAILED"
    echo "  $ATTACH_ERR"
    echo ""
    echo "  Use a profile with IAM admin rights (root or admin user):"
    echo "  AWS_PROFILE=<your-admin-profile> $0 $USERNAME"
    exit 1
  fi
}

# Create access key (max 2 per user; skip if --attach-only)
CREATE_KEY="y"
[[ "${2:-}" == "--attach-only" ]] && CREATE_KEY="n"

echo ""
if [[ "$CREATE_KEY" != "n" ]]; then
  read -p "  Create access key for $USERNAME? [y/N] " -n 1 do_key
  echo ""
  CREATE_KEY="$do_key"
fi

if [[ "$(echo "$CREATE_KEY" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
  if KEY_OUT=$(aws iam create-access-key --user-name "$USERNAME" 2>&1); then
    ACCESS_KEY=$(echo "$KEY_OUT" | grep -o '"AccessKeyId": "[^"]*"' | cut -d'"' -f4)
    SECRET_KEY=$(echo "$KEY_OUT" | grep -o '"SecretAccessKey": "[^"]*"' | cut -d'"' -f4)
    echo ""
    echo "==> Access keys created. Add to ~/.aws/credentials:"
    echo ""
    echo "[$USERNAME]"
    echo "aws_access_key_id = $ACCESS_KEY"
    echo "aws_secret_access_key = $SECRET_KEY"
    echo ""
    echo "Then: AWS_PROFILE=$USERNAME ./scripts/setup-aws.sh"
    echo ""
    echo "⚠️  Save the Secret Access Key now — it won't be shown again."
  else
    echo "  Skipped. User already has 2 keys (AWS limit). Use existing keys with AWS_PROFILE=$USERNAME"
  fi
fi

echo ""
echo "==> Done. Try: AWS_PROFILE=$USERNAME ./scripts/setup-aws.sh"
