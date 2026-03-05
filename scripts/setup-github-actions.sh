#!/usr/bin/env bash
# Setup GitHub Actions secrets via gh CLI
# Requires: gh (GitHub CLI) installed and authenticated
# Usage: ./setup-github-actions.sh [--rails|--infra-mysql|--infra-datadog|--all]
# Or set env vars and run (secrets read from env when set)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE="${1:-}"

usage() {
  echo "Usage: $0 [--rails|--infra-mysql|--infra-datadog|--all]"
  echo ""
  echo "  --rails        Add secrets for Rails ECR push"
  echo "  --infra-mysql  Add secrets for Terraform MySQL apply"
  echo "  --infra-datadog Add secrets for Terraform Datadog apply"
  echo "  --all          Add all secrets (interactive)"
  echo ""
  echo "Secrets are read from environment variables when set."
  echo "Otherwise you will be prompted (gh secret set will read from stdin)."
  exit 1
}

set_secret() {
  local name="$1"
  local desc="$2"
  local val="${!name:-}"
  if [[ -n "$val" ]]; then
    echo "$val" | gh secret set "$name" --body-file -
    echo "  Set $name"
  else
    echo "  Skipped $name ($desc)"
  fi
}

set_secret_default() {
  local name="$1"
  local default="$2"
  local val="${!name:-$default}"
  echo "$val" | gh secret set "$name" --body-file -
  echo "  Set $name"
}

set_secret_prompt() {
  local name="$1"
  local desc="$2"
  local val="${!name:-}"
  if [[ -n "$val" ]]; then
    echo "$val" | gh secret set "$name" --body-file -
    echo "  Set $name"
  else
    echo -n "  $name ($desc): "
    read -s val
    echo
    if [[ -n "$val" ]]; then
      echo "$val" | gh secret set "$name" --body-file -
      echo "  Set $name"
    fi
  fi
}

echo "==> GitHub Actions Setup"
echo "    Project: $PROJECT_ROOT"
echo ""

# Check gh
command -v gh &>/dev/null || { echo "Install gh: https://cli.github.com"; exit 1; }
gh auth status &>/dev/null || { echo "Run: gh auth login"; exit 1; }

cd "$PROJECT_ROOT"
[[ -d .git ]] || { echo "Not a git repo"; exit 1; }
gh repo view &>/dev/null || { echo "Remote must be a GitHub repo"; exit 1; }

case "$MODE" in
  --rails)
    echo "==> Setting Rails (ECR) secrets..."
    set_secret AWS_ACCOUNT_ID "AWS account ID"
    set_secret AWS_ACCESS_KEY_ID "AWS access key"
    set_secret AWS_SECRET_ACCESS_KEY "AWS secret key"
    set_secret_default AWS_REGION "ap-northeast-2"
    ;;
  --infra-mysql)
    echo "==> Setting Infrastructure MySQL secrets..."
    set_secret_prompt AWS_ACCESS_KEY_ID "AWS access key"
    set_secret_prompt AWS_SECRET_ACCESS_KEY "AWS secret key"
    set_secret_prompt TF_VAR_SSH_PUBLIC_KEY "SSH public key"
    set_secret_prompt TF_VAR_MYSQL_ROOT_PASSWORD "MySQL root password"
    set_secret_prompt TF_VAR_MYSQL_REPLICATION_PASSWORD "Replication password"
    set_secret_prompt TF_VAR_MYSQL_APP_PASSWORD "App DB password"
    set_secret_prompt TF_VAR_MYSQL_DATADOG_PASSWORD "Datadog DBM password (optional)"
    set_secret_default TF_VAR_AVAILABILITY_ZONES '["ap-northeast-2a","ap-northeast-2b"]'
    set_secret_default AWS_REGION "ap-northeast-2"
    ;;
  --infra-datadog)
    echo "==> Setting Infrastructure Datadog secrets..."
    set_secret_prompt DD_API_KEY "Datadog API key"
    set_secret_prompt DD_APP_KEY "Datadog app key"
    set_secret_prompt EKS_CLUSTER_NAME "EKS cluster name"
    set_secret_prompt MYSQL_MASTER_HOST "MySQL master IP"
    set_secret_prompt MYSQL_DATADOG_PASSWORD "Datadog MySQL user password"
    set_secret_prompt AWS_ACCESS_KEY_ID "AWS access key"
    set_secret_prompt AWS_SECRET_ACCESS_KEY "AWS secret key"
    set_secret_default AWS_REGION "ap-northeast-2"
    ;;
  --all)
    echo "==> Setting all secrets (interactive)..."
    $0 --rails
    echo ""
    $0 --infra-mysql
    echo ""
    $0 --infra-datadog
    ;;
  -h|--help|"")
    usage
    ;;
  *)
    echo "Unknown: $MODE"
    usage
    ;;
esac

echo ""
echo "==> Done. Verify: gh secret list"
echo "    Or push a change to trigger workflows."
echo ""
