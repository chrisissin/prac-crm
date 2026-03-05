# CRM

Ruby on Rails CRM with MySQL 5.6.

- **[README-LOCAL-DEV.md](README-LOCAL-DEV.md)** – Local development (MySQL 5.6 in Docker)
- **[README-AWS.md](README-AWS.md)** – AWS setup (Terraform MySQL + EKS deployment)
- **[README-AWS-PROFILES.md](README-AWS-PROFILES.md)** – AWS profiles (multi-account on laptop)
- **[README-DATADOG.md](README-DATADOG.md)** – Datadog monitoring + MySQL DBM

**One-command setup:**
- Local: `./scripts/setup-local.sh` (MySQL + Rails in Docker)
- AWS: Set `TF_VAR_*` env vars and run `./scripts/setup-aws.sh` (see `./scripts/setup-aws-profiles.sh` for multi-account)
- Datadog: Set `DD_API_KEY`, `DD_APP_KEY`, `EKS_CLUSTER_NAME`, `MYSQL_DATADOG_PASSWORD` and run `./scripts/setup-datadog.sh`

**CI/CD:** [README-GITHUB-ACTIONS.md](README-GITHUB-ACTIONS.md) – Setup guide | `./scripts/setup-github-actions.sh` – Configure secrets

## Structure

```
prac/
├── crm/                      # Rails CRM application
├── k8s/                      # Kubernetes manifests for EKS
├── terraform/
│   ├── mysql/                # Terraform for MySQL on EC2
│   └── datadog/              # Datadog Agent + MySQL DBM on EKS
│   ├── main.tf
│   ├── variables.tf
│   ├── vpc.tf
│   ├── ec2-mysql.tf
│   ├── security-groups.tf
│   ├── iam.tf
│   ├── s3-backup.tf
│   ├── outputs.tf
│   └── cloud-init/
│       ├── master.yml
│       └── replica.yml
├── scripts/                  # Operation scripts
│   ├── mysql-backup.sh
│   ├── mysql-upgrade.sh
│   ├── mysql-monitor.sh
│   └── README.md
├── config/
│   └── mysql-ops.conf.example
└── README.md
```

## Quick Start

### 1. Deploy MySQL with Terraform

```bash
cd terraform/mysql
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set:
# - availability_zones
# - ssh_public_key
# - mysql_root_password, mysql_replication_password, mysql_app_password (or TF_VAR_*)

terraform init && terraform apply
```

### 2. Configure Operation Scripts

```bash
cp config/mysql-ops.conf.example config/mysql-ops.conf
# Set MYSQL_PASSWORD, S3_BUCKET (from terraform output), etc.
```

### 3. Deploy Scripts to EC2

Copy `scripts/` and `config/mysql-ops.conf` to the master (and replicas). Use SSM Session Manager or SCP.

```bash
# From Terraform output
aws ssm start-session --target <mysql-master-instance-id>
```

## Operations

| Script | Purpose |
|--------|---------|
| `mysql-backup.sh` | Full/incremental backup to local + S3 |
| `mysql-upgrade.sh` | Check, backup, upgrade, rollback |
| `mysql-monitor.sh` | Connection, replication, disk, alerts |

See `scripts/README.md` for usage and cron examples.

### 4. Deploy Rails CRM to EKS

```bash
# Build & push image
cd crm && docker build -t <ecr-uri>/crm:latest . && docker push <ecr-uri>/crm:latest

# Deploy to K8s
kubectl apply -f k8s/
kubectl apply -f k8s/job-db-migrate.yaml  # Run migrations
```

See `crm/README.md` and `k8s/README.md` for details.
