#!/usr/bin/env bash
# AWS setup - Terraform MySQL + EKS + CRM deployment
# Requires: AWS CLI, Terraform, kubectl, Docker
#
# Set before running:
#   export TF_VAR_mysql_root_password="<secure>"
#   export TF_VAR_mysql_replication_password="<secure>"
#   export TF_VAR_mysql_app_password="<secure>"
#   export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"
#
# Optional: AWS_PROFILE, AWS_REGION (default us-west-1), SKIP_TERRAFORM, SKIP_EKS, SKIP_K8S
# Optional: Load Balancer HTTP vs HTTPS
#   HTTP (default): No cert needed. Use when you have no domain or for dev/test.
#   HTTPS: Set ACM_CERT_ARN to a validated ACM certificate ARN in the same region.
#     export ACM_CERT_ARN="arn:aws:acm:us-west-1:ACCOUNT:certificate/ID"
#   Force HTTP: Set HTTP_ONLY=1 to use HTTP even if ACM_CERT_ARN is set.
#     export HTTP_ONLY=1
#
# Use a specific AWS profile:
#   export AWS_PROFILE=my-profile
#   ./scripts/setup-aws.sh
#
# Or explicit creds:
#   export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=us-east-1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AWS_REGION="${AWS_REGION:-us-west-1}"
# Give plugins more time to start (helps on Apple Silicon / Rosetta)
export TF_PLUGIN_TIMEOUT="${TF_PLUGIN_TIMEOUT:-300}"

echo "==> CRM AWS Setup"
echo "    Project root: $PROJECT_ROOT"
echo "    Region: $AWS_REGION"
if [[ "${HTTP_ONLY:-}" == "1" || -z "${ACM_CERT_ARN:-}" ]]; then
  echo "    Load Balancer: HTTP (no TLS)"
else
  echo "    Load Balancer: HTTPS (ACM certificate)"
fi
echo ""

# Check required tools
for cmd in aws terraform kubectl docker; do
  command -v $cmd &>/dev/null || { echo "Missing: $cmd"; exit 1; }
done

# Check Terraform secrets
if [[ "${SKIP_TERRAFORM:-}" != "1" ]]; then
  for var in TF_VAR_mysql_root_password TF_VAR_mysql_replication_password TF_VAR_mysql_app_password; do
    [[ -n "${!var:-}" ]] || { echo "Set $var"; exit 1; }
  done
  # SSH key: use TF_VAR or auto-load from ~/.ssh/id_rsa.pub (trim newlines)
  if [[ -z "${TF_VAR_ssh_public_key:-}" ]]; then
    if [[ -f "$HOME/.ssh/id_rsa.pub" ]]; then
      export TF_VAR_ssh_public_key="$(tr -d '\n' < "$HOME/.ssh/id_rsa.pub")"
      echo "    Using SSH key from ~/.ssh/id_rsa.pub"
    else
      echo "Set TF_VAR_ssh_public_key or create ~/.ssh/id_rsa.pub"
      exit 1
    fi
  else
    export TF_VAR_ssh_public_key="$(echo "$TF_VAR_ssh_public_key" | tr -d '\n')"
  fi
  if [[ ! "$TF_VAR_ssh_public_key" =~ ^ssh-(rsa|ed25519)\ [A-Za-z0-9+/=]+ ]]; then
    echo "Invalid SSH public key. Use: export TF_VAR_ssh_public_key=\"\$(cat ~/.ssh/id_rsa.pub)\""
    exit 1
  fi
fi

# Phase 1: Terraform (MySQL)
if [[ "${SKIP_TERRAFORM:-}" != "1" ]]; then
  echo "==> [1/8] Terraform: MySQL on EC2..."
  cd "$PROJECT_ROOT/terraform/mysql"
  if [[ ! -f terraform.tfvars ]]; then
    cp terraform.tfvars.example terraform.tfvars
    echo "    Created terraform.tfvars - ensure availability_zones and ssh_public_key are set"
  fi
  # Clean provider cache to force 5.63.x (5.64+ times out on Apple Silicon)
  rm -rf .terraform .terraform.lock.hcl 2>/dev/null || true
  terraform init
  terraform apply -auto-approve
  MYSQL_HOST=$(terraform output -raw mysql_master_private_ip)
  echo "    MySQL master: $MYSQL_HOST"
else
  echo "==> [1/8] Skipping Terraform (SKIP_TERRAFORM=1)"
  MYSQL_HOST="${DATABASE_HOST:-}"
  if [[ -z "$MYSQL_HOST" ]]; then
    echo "    Set DATABASE_HOST when skipping Terraform"
    exit 1
  fi
fi

# Phase 2: Terraform (EKS)
if [[ "${SKIP_EKS:-}" != "1" ]]; then
  echo ""
  echo "==> [2/8] Terraform: EKS cluster..."
  cd "$PROJECT_ROOT/terraform/eks"
  if [[ ! -f terraform.tfvars ]]; then
    cp terraform.tfvars.example terraform.tfvars
    echo "    Created terraform.tfvars"
  fi
  # Ensure region matches
  if [[ -n "$AWS_REGION" ]] && ! grep -q "aws_region" terraform.tfvars 2>/dev/null; then
    echo "aws_region = \"$AWS_REGION\"" >> terraform.tfvars
  fi
  rm -rf .terraform .terraform.lock.hcl 2>/dev/null || true
  terraform init
  terraform apply -auto-approve -var="aws_region=$AWS_REGION"
  EKS_CLUSTER_NAME=$(terraform output -raw cluster_name)
  echo "    EKS cluster: $EKS_CLUSTER_NAME"
else
  echo "==> [2/8] Skipping EKS (SKIP_EKS=1)"
  EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-}"
  [[ -n "$EKS_CLUSTER_NAME" ]] || { echo "    Set EKS_CLUSTER_NAME when skipping EKS"; exit 1; }
fi

# Phase 3: Configure kubectl and wait for nodes
if [[ "${SKIP_EKS:-}" != "1" ]]; then
  echo ""
  echo "==> [3/8] Configuring kubectl..."
  aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME"
  echo "    Waiting for EKS nodes to be ready..."
  JSONPATH_READY='{.items[*].status.conditions[?(@.type=="Ready")].status}'
  for _ in $(seq 1 30); do
    READY=$(kubectl get nodes -o jsonpath="$JSONPATH_READY" 2>/dev/null | tr ' ' '\n' | grep -c True || true)
    [[ "${READY:-0}" -ge 1 ]] && break
    sleep 10
  done
  echo "    kubeconfig updated, nodes ready"
fi

# Phase 4: Build and push image
echo ""
echo "==> [4/8] Building and pushing Docker image..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/crm"

aws ecr create-repository --repository-name crm --region "$AWS_REGION" 2>/dev/null || true
docker build --platform linux/amd64 -t "$ECR_URI:latest" "$PROJECT_ROOT/crm"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_URI"
docker push "$ECR_URI:latest"

# Get MySQL host for K8s secret
if [[ "${SKIP_TERRAFORM:-}" != "1" ]]; then
  cd "$PROJECT_ROOT/terraform/mysql"
  MYSQL_HOST=$(terraform output -raw mysql_master_private_ip)
fi
MYSQL_PASSWORD="${TF_VAR_mysql_app_password:-$MYSQL_APP_PASSWORD}"
[[ -n "$MYSQL_PASSWORD" ]] || { echo "Set TF_VAR_mysql_app_password or MYSQL_APP_PASSWORD"; exit 1; }

# Phase 5: K8s secret
echo ""
echo "==> [5/8] Creating Kubernetes secret..."
SECRET_KEY_BASE=$(cd "$PROJECT_ROOT/crm" && bundle exec rails secret 2>/dev/null || echo "replace-with-rails-secret")

kubectl create namespace crm 2>/dev/null || true
kubectl create secret generic crm-secrets -n crm \
  --from-literal=DATABASE_USERNAME=crm_app \
  --from-literal=DATABASE_PASSWORD="$MYSQL_PASSWORD" \
  --from-literal=DATABASE_HOST="$MYSQL_HOST" \
  --from-literal=DATABASE_NAME=crm_production \
  --from-literal=SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  --dry-run=client -o yaml | kubectl apply -f -

# Phase 6: Deploy K8s manifests (substitute image URL)
echo ""
echo "==> [6/8] Deploying to EKS..."
cd "$PROJECT_ROOT"
IMAGE_PLACEHOLDER="123456789012.dkr.ecr.us-west-1.amazonaws.com/crm"

# HTTP vs HTTPS: use HTTPS only when ACM_CERT_ARN is set and HTTP_ONLY is not set
USE_HTTPS=false
if [[ -n "${ACM_CERT_ARN:-}" && "${HTTP_ONLY:-}" != "1" ]]; then
  if [[ ! "$ACM_CERT_ARN" =~ ^arn:aws:acm: ]]; then
    echo "Error: ACM_CERT_ARN should be an ACM certificate ARN (e.g. arn:aws:acm:region:account:certificate/id)"
    exit 1
  fi
  if [[ "$ACM_CERT_ARN" == *"xxxxxxxx"* ]]; then
    echo "Error: ACM_CERT_ARN is still the placeholder. Get a real ARN:"
    echo "  aws acm list-certificates --region $AWS_REGION --query 'CertificateSummaryList[*].[DomainName,CertificateArn]' --output table"
    exit 1
  fi
  USE_HTTPS=true
  echo "    Using HTTPS (ACM certificate)"
else
  echo "    Using HTTP (set ACM_CERT_ARN for HTTPS, or HTTP_ONLY=1 to force HTTP)"
fi

kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
sed "s|$IMAGE_PLACEHOLDER|$ECR_URI|g" k8s/deployment.yaml | kubectl apply -f -
kubectl apply -f k8s/service.yaml
if [[ "$USE_HTTPS" == "true" ]]; then
  kubectl delete svc crm-public -n crm 2>/dev/null || true
  sed "s|ACM_CERT_ARN_PLACEHOLDER|$ACM_CERT_ARN|g" k8s/service-loadbalancer-https.yaml | kubectl apply -f -
  kubectl patch configmap crm-config -n crm --type merge -p '{"data":{"FORCE_SSL":"true"}}'
  kubectl rollout restart deployment/crm -n crm
else
  kubectl apply -f k8s/service-loadbalancer.yaml
  kubectl patch configmap crm-config -n crm --type merge -p '{"data":{"FORCE_SSL":"false"}}' 2>/dev/null || true
fi
kubectl apply -f k8s/ingress.yaml 2>/dev/null || true
kubectl apply -f k8s/hpa.yaml

# Phase 6b: Ensure MySQL crm_app user exists (cloud-init runs async; may not finish before we migrate)
if [[ "${SKIP_TERRAFORM:-}" != "1" ]]; then
  echo ""
  echo "==> [6b/8] Ensuring MySQL crm_app user exists..."
  if "$PROJECT_ROOT/scripts/fix-mysql-user.sh" 2>/dev/null; then
    echo "    MySQL crm_app user ready"
  else
    echo "    Note: If migrations fail with 'Access denied', run ./scripts/fix-mysql-user.sh"
    echo "    Or SSH to MySQL master (see README-AWS.md troubleshooting)"
  fi
fi

# Phase 7: Migrations
echo ""
echo "==> [7/8] Running database migrations..."
kubectl delete job crm-db-migrate -n crm 2>/dev/null || true
sed "s|$IMAGE_PLACEHOLDER|$ECR_URI|g" k8s/job-db-migrate.yaml | kubectl apply -f -
kubectl wait --for=condition=complete job/crm-db-migrate -n crm --timeout=180s || true

# Phase 8: Admin user
echo ""
echo "==> [8/8] Creating admin user..."
sleep 5
kubectl exec deployment/crm -n crm -- bundle exec rails runner 'user = User.find_or_create_by!(email: "admin@crm.local") { |u| u.password = "changeme"; u.name = "Admin" }; user.update!(password: "changeme", name: "Admin")' 2>/dev/null || echo "    Run manually: kubectl exec deployment/crm -n crm -- bundle exec rails db:seed"

echo ""
echo "==> AWS setup complete!"
echo ""

# Output CRM URL (LoadBalancer may take 1–2 min to get EXTERNAL-IP)
CRM_HOST=""
for _ in $(seq 1 30); do
  CRM_HOST=$(kubectl get svc crm-public -n crm -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [[ -n "$CRM_HOST" ]] && break
  sleep 5
done
if [[ -n "$CRM_HOST" ]]; then
  if [[ "$USE_HTTPS" == "true" ]]; then
    echo "  CRM URL (HTTPS): https://<your-domain>  (CNAME to $CRM_HOST)"
  else
    echo "  CRM URL (public): http://$CRM_HOST"
  fi
else
  echo "  CRM URL: run 'kubectl get svc crm-public -n crm' (EXTERNAL-IP may take 1–2 min)"
fi
echo "  Login: admin@crm.local / changeme"
echo ""

# Bastion output (from Terraform)
if [[ "${SKIP_TERRAFORM:-}" != "1" ]]; then
  cd "$PROJECT_ROOT/terraform/mysql"
  BASTION_IP=$(terraform output -raw bastion_public_ip 2>/dev/null || true)
  if [[ -n "$BASTION_IP" ]]; then
    echo "  Bastion (SSH + kubectl): ssh ubuntu@$BASTION_IP"
    if [[ -n "${EKS_CLUSTER_NAME:-}" ]]; then
      echo "    From bastion: aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER_NAME && kubectl get svc -n crm"
    else
      echo "    From bastion: kubectl get svc -n crm  # get CRM URL if local kubectl times out"
    fi
  fi
  cd "$PROJECT_ROOT"
fi
echo ""
echo "  Logs: kubectl logs -f deployment/crm -n crm"
echo ""
