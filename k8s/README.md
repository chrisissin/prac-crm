# CRM on AWS EKS

Kubernetes manifests for deploying the Rails CRM to Amazon EKS.

## Prerequisites

- EKS cluster (same VPC as MySQL Terraform for DB connectivity)
- `kubectl` configured
- AWS Load Balancer Controller installed (for Ingress)
- ECR repository for CRM image

## Setup

### 1. Build and Push Image

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=us-west-1
ECR_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/crm

aws ecr create-repository --repository-name crm --region $AWS_REGION 2>/dev/null || true
docker build -t $ECR_URI:latest ./crm
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI
docker push $ECR_URI:latest
```

### 2. Update Secrets

Edit `secret.yaml` or create manually:

```bash
kubectl create secret generic crm-secrets -n crm \
  --from-literal=DATABASE_USERNAME=crm_app \
  --from-literal=DATABASE_PASSWORD=<from-terraform> \
  --from-literal=DATABASE_HOST=<mysql_master_private_ip-from-terraform> \
  --from-literal=DATABASE_NAME=crm_production \
  --from-literal=SECRET_KEY_BASE=$(rails secret)
```

### 3. Update Deployment Image

Replace `123456789012` in `deployment.yaml` and `job-db-migrate.yaml` with your AWS account ID.

### 4. Apply Manifests

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/hpa.yaml
```

### 5. Run Migrations

```bash
kubectl apply -f k8s/job-db-migrate.yaml
kubectl wait --for=condition=complete job/crm-db-migrate -n crm
```

### 6. Create Admin User (optional)

```bash
kubectl exec -it deployment/crm -n crm -- bundle exec rails runner "
  User.find_or_create_by!(email: 'admin@crm.local') { |u| u.password = 'changeme'; u.name = 'Admin' }
"
```

## Files

| File | Purpose |
|------|---------|
| namespace.yaml | crm namespace |
| configmap.yaml | Non-sensitive env |
| secret.yaml | DB credentials, SECRET_KEY_BASE |
| deployment.yaml | Rails app pods |
| service.yaml | ClusterIP service |
| ingress.yaml | ALB Ingress |
| hpa.yaml | Horizontal Pod Autoscaler |
| job-db-migrate.yaml | One-time DB migration job |
