#!/usr/bin/env bash
# AWS profile setup helper - list, verify, add profiles for multi-account use
# Usage: ./scripts/setup-aws-profiles.sh [list|verify|add|use]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_CREDENTIALS="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
AWS_CONFIG="${AWS_CONFIG_FILE:-$HOME/.aws/config}"

cmd_list() {
  echo "==> AWS Profiles"
  echo ""
  if ! command -v aws &>/dev/null; then
    echo "  AWS CLI not installed. Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
  fi
  if ! aws configure list-profiles 2>/dev/null | grep -q .; then
    echo "  No profiles found."
    echo "  Create ~/.aws/credentials with [profile-name] sections, or run: aws configure"
    exit 1
  fi
  for p in $(aws configure list-profiles); do
    echo "  - $p"
  done
}

cmd_verify() {
  local profile="${1:-}"
  echo "==> Verifying AWS credentials"
  echo ""
  if [[ -n "$profile" ]]; then
    echo "  Profile: $profile"
    if aws sts get-caller-identity --profile "$profile" 2>/dev/null; then
      echo ""
      echo "  OK"
    else
      echo "  FAILED"
      exit 1
    fi
  else
    echo "  Using default credentials (or AWS_PROFILE=${AWS_PROFILE:-<not set>})"
    if aws sts get-caller-identity 2>/dev/null; then
      echo ""
      echo "  OK"
    else
      echo "  FAILED"
      echo "  Run 'aws configure' to set up credentials, or 'aws sso login' if using SSO."
      echo "  To test a specific profile: $0 verify default"
      exit 1
    fi
  fi
}

cmd_add() {
  echo "==> Add AWS profile"
  echo ""
  echo "  Option 1: Interactive (access keys)"
  echo "    aws configure --profile <name>"
  echo ""
  echo "  Option 2: Interactive (SSO)"
  echo "    aws configure sso"
  echo ""
  echo "  Option 3: Edit files manually"
  echo "    Credentials: $AWS_CREDENTIALS"
  echo "    Config:      $AWS_CONFIG"
  echo ""
  echo "  Add a section like:"
  echo "    [my-profile]"
  echo "    aws_access_key_id = ..."
  echo "    aws_secret_access_key = ..."
  echo ""
  read -p "  Press Enter to continue..."
}

cmd_use() {
  local profile="${1:-}"
  if [[ -z "$profile" ]]; then
    echo "==> Set AWS profile for current session"
    echo ""
    echo "  Usage: $0 use <profile-name>"
    echo ""
    echo "  Then run:"
    echo "    export AWS_PROFILE=$profile"
    echo "    ./scripts/setup-aws.sh"
    exit 1
  fi
  echo "==> Using profile: $profile"
  echo ""
  if aws sts get-caller-identity --profile "$profile" &>/dev/null; then
    echo "  export AWS_PROFILE=$profile"
    echo ""
    echo "  Copy and run the line above, or:"
    echo "    eval \$(./scripts/setup-aws-profiles.sh use $profile | grep export)"
  else
    echo "  Profile '$profile' failed verification."
    exit 1
  fi
}

cmd_interactive() {
  while true; do
    echo ""
    echo "==> AWS Profile Setup"
    echo ""
    echo "  1) List profiles"
    echo "  2) Verify current/default credentials"
    echo "  3) Verify a specific profile"
    echo "  4) Add new profile (instructions)"
    echo "  5) Set profile for CRM setup"
    echo "  q) Quit"
    echo ""
    read -p "  Choice: " choice
    choice="${choice// /}"  # trim spaces
    case "$choice" in
      1)
        cmd_list
        ;;
      2)
        cmd_verify
        ;;
      3)
        read -p "  Profile name: " p
        cmd_verify "$p"
        ;;
      4)
        cmd_add
        ;;
      5)
        cmd_list
        echo ""
        read -p "  Profile to use: " p
        if [[ -n "$p" ]]; then
          cmd_use "$p"
        fi
        ;;
      q|Q)
        echo "  Bye."
        exit 0
        ;;
      *)
        echo "  Invalid choice"
        ;;
    esac
  done
}

# Main
case "${1:-}" in
  list)
    cmd_list
    ;;
  verify)
    cmd_verify "${2:-}"
    ;;
  add)
    cmd_add
    ;;
  use)
    cmd_use "${2:-}"
    ;;
  "")
    cmd_interactive
    ;;
  *)
    echo "Usage: $0 [list|verify|add|use [profile]]"
    echo ""
    echo "  list    - List all configured profiles"
    echo "  verify  - Verify credentials (optional: profile name)"
    echo "  add     - Show instructions to add a profile"
    echo "  use     - Show export command for a profile"
    echo "  (none)  - Interactive menu"
    exit 1
    ;;
esac
