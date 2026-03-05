# Datadog Monitoring Setup

Datadog Agent on EKS with MySQL Database Monitoring (DBM) for query metrics, samples, and explain plans.

## Prerequisites

- EKS cluster (same VPC as MySQL)
- MySQL deployed via `terraform/mysql` with `mysql_datadog_password` set
- [Datadog](https://www.datadoghq.com/) account
- `kubectl` configured for your EKS cluster

## Quick Start (One Script)

```bash
export DD_API_KEY="<your-datadog-api-key>"
export DD_APP_KEY="<your-datadog-app-key>"
export EKS_CLUSTER_NAME="my-eks-cluster"
export MYSQL_DATADOG_PASSWORD="<password-for-datadog-mysql-user>"
# Optional: export MYSQL_MASTER_HOST="10.0.1.50"  # auto-detected from terraform/mysql if applied
# Optional: export MYSQL_REPLICA_HOSTS="10.0.2.50 10.0.2.51"  # space-separated

./scripts/setup-datadog.sh
```

**Get your keys:** [Datadog → Organization Settings → API Keys](https://app.datadoghq.com/organization-settings/api-keys)

> The script creates `terraform/datadog/terraform.tfvars` with your keys. Do not commit it.

## What Gets Deployed

| Component | Description |
|-----------|-------------|
| Datadog Agent | DaemonSet on EKS (metrics, logs, APM, process) |
| Cluster Agent | Distributes MySQL DBM cluster check |
| MySQL DBM | Query metrics, samples, explain plans, replication lag |

## Manual Setup

### 1. Ensure MySQL has Datadog user

```bash
cd terraform/mysql
export TF_VAR_mysql_datadog_password="<secure>"
terraform apply
```

### 2. Run Datadog Terraform

```bash
cd terraform/datadog
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init && terraform apply
```

## Verify

- **Datadog UI** → [Databases](https://app.datadoghq.com/databases) → MySQL
- **Agent status:** `kubectl exec -it -n datadog daemonset/datadog-agent -- agent status`

## Requirements

The MySQL Terraform creates the `datadog@` user and required procedures when `mysql_datadog_password` is set. EKS nodes must have network access to MySQL on port 3306 (same VPC).
