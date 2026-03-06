# AWS Setup Guide

Deploy the CRM stack on AWS: MySQL 5.6 (master-replica) on EC2 and Rails app on EKS.

## Quick Start (One Script)

```bash
export TF_VAR_mysql_root_password="<secure>"
export TF_VAR_mysql_replication_password="<secure>"
export TF_VAR_mysql_app_password="<secure>"
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"

./scripts/setup-aws.sh
```

Ensure `terraform/mysql/terraform.tfvars` has `availability_zones` and `ssh_public_key`. The script will:

1. **MySQL** – VPC, subnets, MySQL master/replica EC2, bastion
2. **EKS** – Kubernetes cluster + node group in that VPC
3. **Deploy** – Build image, push to ECR, deploy CRM to EKS, run migrations

#### HTTP vs HTTPS (Load Balancer)

| Mode | When to use | Config |
|------|-------------|--------|
| **HTTP** (default) | No domain, dev/test, or quick setup | Nothing. CRM is reachable at `http://<elb-hostname>`. |
| **HTTPS** | You own a domain with a validated ACM certificate | `export ACM_CERT_ARN="arn:aws:acm:REGION:ACCOUNT:certificate/ID"` |
| **Force HTTP** | Override `ACM_CERT_ARN` if set (e.g. invalid cert) | `export HTTP_ONLY=1` |

```bash
# HTTP (default) – no domain needed
./scripts/setup-aws.sh

# HTTPS – requires ACM cert in same region as cluster
export ACM_CERT_ARN="arn:aws:acm:us-west-1:037302670564:certificate/xxx"
./scripts/setup-aws.sh

# Force HTTP even if ACM_CERT_ARN is in environment
export HTTP_ONLY=1
./scripts/setup-aws.sh
```

Optional: `SKIP_TERRAFORM=1` (and set `DATABASE_HOST`) to skip MySQL. `SKIP_EKS=1` (and set `EKS_CLUSTER_NAME`) to skip EKS creation.

### Teardown (delete everything)

```bash
./scripts/teardown-aws.sh
```

Then to redeploy from scratch: `./scripts/setup-aws.sh`

## Architecture

```
                    ┌─────────────────────────────────────────────────────┐
                    │                     AWS VPC                         │
  Internet          │  Public subnets         Private subnets             │
  ─────────► ┌──────┼──► Bastion (SSH + kubectl)                          │
  ELB/NLB    │      │  ┌─────────────┐    ┌──────────────┐                │
  ──────────►│      │  │ EKS (CRM)   │───►│ MySQL Master │                │
             │      │  │ Pods        │    │ EC2          │                │
             │      │  └─────────────┘    └──────┬───────┘                │
             │      │                            │                       │
             │      │                     ┌──────▼───────┐                │
             │      │                     │ MySQL Replica │                │
             │      │                     │ EC2          │                │
             │      │                     └──────────────┘                │
             └──────┴────────────────────────────────────────────────────┘
```

- **Public IP for testing**: `k8s/service-loadbalancer.yaml` creates a LoadBalancer service – CRM is reachable at the ELB hostname after setup.
- **Bastion**: An EC2 jump host in a public subnet. SSH in and run `kubectl` there when local kubectl times out (e.g. private EKS endpoint).

## Prerequisites

- AWS CLI configured
- Terraform >= 1.0

### Which AWS account / credentials?

The script uses your **default** AWS CLI credentials. To target a specific account:

| Method | Usage |
|--------|-------|
| **Named profile** | `export AWS_PROFILE=my-profile` before running |
| **Explicit creds** | `export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...` |
| **Region** | `export AWS_REGION=us-east-1` (default: `us-west-1`) |
| **HTTPS** | `export ACM_CERT_ARN="arn:aws:acm:region:account:certificate/id"` (cert must be in same region) |
| **HTTP only** | `export HTTP_ONLY=1` (force HTTP even if ACM_CERT_ARN is set) |

Example:
```bash
export AWS_PROFILE=production
export AWS_REGION=us-west-1
./scripts/setup-aws.sh
```

**kubectl** uses your kubeconfig (`~/.kube/config`). Ensure the correct context for your EKS cluster:
```bash
kubectl config get-contexts    # list contexts
kubectl config use-context <cluster-context>
```
- kubectl
- Docker
- EKS cluster (or create via Terraform)

---

## Phase 1: MySQL on EC2

### 1.1 Deploy MySQL with Terraform

```bash
cd terraform/mysql
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
availability_zones = ["us-west-1a", "us-west-1c"]
# Get with: aws ec2 describe-availability-zones --query 'AvailabilityZones[*].ZoneName' --output text

ssh_public_key = "ssh-rsa AAAA... your@email.com"
```

Set secrets (do not commit):

```bash
export TF_VAR_mysql_root_password="<secure-password>"
export TF_VAR_mysql_replication_password="<secure-password>"
export TF_VAR_mysql_app_password="<secure-password-for-crm>"
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"
```

Apply:

```bash
terraform init
terraform plan
terraform apply
```

### 1.2 Save Outputs

```bash
terraform output mysql_master_private_ip   # Use for DATABASE_HOST
terraform output mysql_backup_bucket
terraform output vpc_id
terraform output private_subnet_ids
terraform output public_subnet_ids
terraform output bastion_public_ip
terraform output bastion_ssh_command
```

### 1.3 Bastion (Jump Host)

A bastion EC2 is created in a public subnet. Use it to SSH and run kubectl from inside the VPC:

```bash
# From terraform output
ssh ubuntu@$(cd terraform/mysql && terraform output -raw bastion_public_ip)

# On bastion: kubectl is pre-installed. Configure kubeconfig if not done at boot:
aws eks update-kubeconfig --region us-west-1 --name <your-eks-cluster>
kubectl get svc -n crm   # Get CRM LoadBalancer URL
```

Set `eks_cluster_name` in `terraform.tfvars` and re-apply to auto-configure kubectl on bastion boot.

### 1.4 Configure Operation Scripts

```bash
cp config/mysql-ops.conf.example config/mysql-ops.conf
```

Edit `mysql-ops.conf` with MySQL credentials and `S3_BUCKET` (from terraform output). Copy `scripts/` and `config/mysql-ops.conf` to the MySQL master via SSM:

```bash
aws ssm start-session --target <mysql-master-instance-id>
```

---

## Phase 2: EKS and CRM Deployment

### 2.1 EKS Cluster

Ensure your EKS cluster is in the **same VPC** as MySQL (or has network access to MySQL's private IP). If using the Terraform VPC, use those subnet IDs when creating the EKS cluster.

### 2.2 Build and Push Docker Image

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=us-west-1
ECR_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/crm

aws ecr create-repository --repository-name crm --region $AWS_REGION 2>/dev/null || true

docker build -t $ECR_URI:latest ./crm
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI
docker push $ECR_URI:latest
```

### 2.3 Update Kubernetes Manifests

Edit `k8s/deployment.yaml` and `k8s/job-db-migrate.yaml`: replace `123456789012` with your AWS account ID in the image URL.

Edit `k8s/secret.yaml` or create the secret manually:

```bash
kubectl create namespace crm

kubectl create secret generic crm-secrets -n crm \
  --from-literal=DATABASE_USERNAME=crm_app \
  --from-literal=DATABASE_PASSWORD=<mysql_app_password-from-terraform> \
  --from-literal=DATABASE_HOST=<mysql_master_private_ip-from-terraform> \
  --from-literal=DATABASE_NAME=crm_production \
  --from-literal=SECRET_KEY_BASE=$(cd crm && bundle exec rails secret)
```

### 2.4 Deploy to EKS

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/service-loadbalancer.yaml
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/hpa.yaml
```

### 2.5 Run Migrations

```bash
kubectl apply -f k8s/job-db-migrate.yaml
kubectl wait --for=condition=complete job/crm-db-migrate -n crm --timeout=120s
```

### 2.6 Create Admin User (Optional)

```bash
kubectl exec -it deployment/crm -n crm -- bundle exec rails runner "
  User.find_or_create_by!(email: 'admin@crm.local') { |u| u.password = 'changeme'; u.name = 'Admin' }
"
```

### 2.7 Access the App

**Public LoadBalancer (recommended for testing):**

```bash
kubectl get svc crm-public -n crm
```

The setup script outputs the CRM URL when it finishes. Use the `EXTERNAL-IP` or hostname (may take 1–2 min to provision).

**Alternatively**, if using ALB Ingress:

```bash
kubectl get ingress -n crm
```

Login: `admin@crm.local` / `changeme`

**If local kubectl times out**, SSH into the bastion and run the same commands there.

### 2.8 HTTPS / TLS Termination at Load Balancer

To serve HTTPS, you need an ACM certificate and a domain name. ACM cannot issue certs for the default ELB hostname (`*.elb.amazonaws.com`).

**1. Request an ACM certificate** (for your domain, e.g. `crm.example.com`):

```bash
aws acm request-certificate \
  --domain-name crm.example.com \
  --validation-method DNS \
  --region us-west-1
```

**2. Validate the certificate** – add the DNS CNAME record shown in ACM (Console → Certificate Manager) to your domain’s DNS.

**3. Point your domain to the Load Balancer** – after the ELB is created, add:

```
crm.example.com  CNAME  <elb-hostname-from-kubectl-get-svc>
```

**4. Apply the HTTPS service** with your certificate ARN:

```bash
ACM_CERT_ARN=$(aws acm list-certificates --region us-west-1 \
  --query 'CertificateSummaryList[?DomainName==`crm.example.com`].CertificateArn' --output text)

kubectl delete svc crm-public -n crm  # remove HTTP-only LB
sed "s|ACM_CERT_ARN_PLACEHOLDER|$ACM_CERT_ARN|g" k8s/service-loadbalancer-https.yaml | kubectl apply -f -
kubectl patch configmap crm-config -n crm --type merge -p '{"data":{"FORCE_SSL":"true"}}'
kubectl rollout restart deployment/crm -n crm
```

Or use the setup script with `ACM_CERT_ARN`:

```bash
export ACM_CERT_ARN="arn:aws:acm:us-west-1:ACCOUNT:certificate/ID"
./scripts/setup-aws.sh
```

Then access `https://crm.example.com`.

---

## Phase 3: Operations

### MySQL Backup (on master)

```bash
./scripts/mysql-backup.sh full master
```

### MySQL Monitor

```bash
MYSQL_HOST=<master-ip> MYSQL_PASSWORD=xxx ./scripts/mysql-monitor.sh full
```

### CRM Logs

```bash
kubectl logs -f deployment/crm -n crm
```

### Scale CRM

```bash
kubectl scale deployment crm -n crm --replicas=5
```

---

## Phase 4: Datadog Monitoring (Optional)

### 4.1 Deploy Datadog + MySQL DBM

```bash
cd terraform/datadog
cp terraform.tfvars.example terraform.tfvars
# Set: datadog_api_key, datadog_app_key, cluster_name, mysql_master_host, mysql_datadog_password
terraform init && terraform apply
```

Ensure `terraform/mysql` was applied with `mysql_datadog_password` so the `datadog@` user exists.

See `terraform/datadog/README.md` for details.

---

## Troubleshooting

| Issue | Check |
|-------|-------|
| CRM can't connect to MySQL | Security groups: EKS nodes must allow outbound to MySQL 3306; MySQL SG must allow inbound from EKS node SG |
| Pods pending | `kubectl describe pod -n crm` – check resources, image pull |
| 502 from ALB | Pods not ready; check `kubectl get pods -n crm` and logs |
| Migration job fails | Verify DATABASE_HOST, DATABASE_PASSWORD in secret |
| **500 after login** | `ConnectionNotEstablished` → MySQL unreachable. Verify: `terraform output mysql_master_private_ip` matches K8s secret. Update secret and restart: `kubectl create secret generic crm-secrets -n crm ... --dry-run=client -o yaml \| kubectl apply -f -` then `kubectl rollout restart deployment/crm -n crm` |
| **MySQL not running / Unit mysql.service could not be found** | Cloud-init apt failed (private subnet had no internet). See *MySQL cloud-init recovery* below. |
| **Terraform: timeout while waiting for plugin to start** | See below |
| **Terraform: UnauthorizedOperation / ec2:DescribeImages** | See IAM permissions below |
| **Terraform: collecting instance settings: couldn't find resource** | See below |

### Terraform Plugin Timeout (macOS / Apple Silicon)

If you see `Error: timeout while waiting for plugin to start` or `Failed to load plugin schemas`:

1. **Script now sets `TF_PLUGIN_TIMEOUT=300`** – re-run `./scripts/setup-aws.sh`.

2. **AWS provider pinned to 5.6.x** – newer versions can timeout on Apple Silicon. If it still fails:
   ```bash
   cd terraform/mysql
   rm -rf .terraform .terraform.lock.hcl
   terraform init
   cd ../..
   ./scripts/setup-aws.sh
   ```

3. **Use native arm64 Terraform** – if you have the x86 build (Rosetta), install the arm64 one:
   ```bash
   brew install terraform   # or download darwin_arm64 from terraform.io
   ```

4. **macOS IPv6** – If Terraform hangs on network calls, disabling IPv6 in System Settings can help (known Go/runtime issue).

### IAM Permissions (UnauthorizedOperation)

The Terraform setup requires broad permissions. Errors like `ec2:ImportKeyPair`, `iam:CreateRole`, `s3:CreateBucket`, `ec2:CreateVpc` mean your IAM user lacks the needed actions.

**Option 0 – Create user + permissions via script (run as admin):**

You need credentials with IAM admin rights (root account or an IAM user with AdministratorAccess). Configure a profile with those credentials, then:

```bash
# If using root: aws configure (creates default profile)
# Or create a named profile: aws configure --profile admin

AWS_PROFILE=<your-admin-profile> ./scripts/setup-aws-iam-user.sh chrisissin
```

Creates the user, attaches AdministratorAccess, and optionally creates access keys. Then run `./scripts/setup-aws.sh` with the target user's profile.

**Option 1 – Attach AdministratorAccess (simplest for dev/sandbox):**

1. IAM Console → Users → [your user] → **Add permissions**
2. Attach policy: **AdministratorAccess**
3. Re-run `./scripts/setup-aws.sh`

**Option 2 – Least-privilege (managed policies):**

Attach these managed policies to your IAM user:
- `AmazonEC2FullAccess`
- `AmazonVPCFullAccess`
- `AmazonS3FullAccess`
- `IAMFullAccess` (for creating roles/profiles for EC2)
- `AmazonSSMFullAccess` (for EC2 instance profile)
- `AmazonEKSClusterPolicy` (for K8s/EKS phase)

**Option 3 – Workaround for `ec2:DescribeImages` only:**  
If you only hit DescribeImages, use a fixed AMI: set `mysql_master_ami = "ami-XXX"` in `terraform.tfvars`. See fallback AMIs in `ec2-mysql.tf` for us-west-1.

### Terraform: "collecting instance settings: couldn't find resource"

This occurs when Terraform's state references an EC2 instance that no longer exists in AWS (failed launch, invalid AMI, or manual deletion). Fix by removing the resource from state and re-applying:

```bash
cd terraform/mysql
terraform state rm aws_instance.mysql_master
terraform state rm 'aws_instance.mysql_replica[0]'   # if replica exists
terraform apply -auto-approve
```

If the fallback AMI is invalid, set `mysql_master_ami` in `terraform.tfvars` to a current Ubuntu 20.04 AMI from [cloud-images.ubuntu.com/locator/ec2](https://cloud-images.ubuntu.com/locator/ec2).

### MySQL cloud-init recovery (apt failed, no internet)

If the MySQL master (or replicas) show `Unit mysql.service could not be found`, `apt` failed because the private subnet had no outbound internet when cloud-init ran (NAT not ready or route delayed).

**Fix: recreate the MySQL instance(s)** so cloud-init runs again with network available. Terraform now depends on NAT gateways before creating MySQL instances.

```bash
cd terraform/mysql
terraform taint aws_instance.mysql_master
terraform taint 'aws_instance.mysql_replica[0]'   # if replicas exist
terraform apply -auto-approve
```

Then run `./scripts/setup-aws.sh` (or only the deploy phase) to ensure migrations run. If `terraform taint` is unavailable in your Terraform version, use `terraform apply -replace=aws_instance.mysql_master -auto-approve`.

### Access denied for crm_app / 500 after login / Migration job fails

If migrations fail with `Access denied for user 'crm_app'@'...'` or login returns 500, cloud-init may not have created the `crm_app` user (timing or MySQL 8 auth plugin mismatch).

**Option 1 – Script (SSM):**
```bash
export TF_VAR_mysql_root_password="<your_root_pw>"
export TF_VAR_mysql_app_password="<your_app_pw>"
./scripts/fix-mysql-user.sh
```

**Option 2 – Manual via bastion:**
```bash
# SSH to MySQL master
ssh -A -J ubuntu@<bastion_ip> ubuntu@<mysql_master_ip>
# From terraform: bastion_ip=$(cd terraform/mysql && terraform output -raw bastion_public_ip)
#                mysql_master_ip=$(cd terraform/mysql && terraform output -raw mysql_master_private_ip)

# On the MySQL master:
sudo mysql -u root -p'<root_pw>' -e "
CREATE DATABASE IF NOT EXISTS crm_production CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
DROP USER IF EXISTS 'crm_app'@'%';
CREATE USER 'crm_app'@'%' IDENTIFIED WITH mysql_native_password BY '<app_pw>';
GRANT ALL PRIVILEGES ON crm_production.* TO 'crm_app'@'%';
FLUSH PRIVILEGES;
"
exit
```

Then re-run migrations:
```bash
kubectl delete job crm-db-migrate -n crm 2>/dev/null || true
# Use your ECR URI: sed 's|123456789012...|YOUR_ACCOUNT.dkr.ecr.REGION.amazonaws.com/crm|g' k8s/job-db-migrate.yaml | kubectl apply -f -
kubectl wait --for=condition=complete job/crm-db-migrate -n crm --timeout=180s
kubectl exec deployment/crm -n crm -- bundle exec rails runner 'User.find_or_create_by!(email: "admin@crm.local") { |u| u.password = "changeme"; u.name = "Admin" }.update!(password: "changeme", name: "Admin")'
```
