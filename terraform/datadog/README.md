# Datadog Monitoring + MySQL DBM

Terraform for Datadog Agent on EKS and MySQL Database Monitoring (DBM).

## Prerequisites

- EKS cluster (same VPC as MySQL for connectivity)
- MySQL Terraform applied with `mysql_datadog_password` set
- Datadog API key and Application key

## Setup

### 1. MySQL with Datadog User

Deploy or update MySQL Terraform with the datadog password:

```bash
cd ../mysql
export TF_VAR_mysql_datadog_password="<secure-password>"
# ... other TF_VAR_* ...
terraform apply
```

### 2. Datadog Terraform

```bash
cd terraform/datadog
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
```

Required variables:
- `datadog_api_key` - From Datadog Org Settings → API Keys
- `datadog_app_key` - From Datadog Org Settings → Application Keys
- `cluster_name` - Your EKS cluster name
- `mysql_master_host` - From `terraform/mysql` output: `mysql_master_private_ip`
- `mysql_datadog_password` - Same as `mysql_datadog_password` in MySQL Terraform
- `mysql_replica_hosts` - (optional) From `terraform/mysql` output: `mysql_replica_private_ips`

```bash
terraform init
terraform plan
terraform apply
```

## What Gets Deployed

| Component | Description |
|-----------|-------------|
| Datadog Agent | DaemonSet on EKS nodes (metrics, logs, APM, process) |
| Cluster Agent | Dispatches cluster checks (MySQL DBM) |
| MySQL DBM | Cluster check connecting to MySQL master + replicas |

## MySQL DBM Requirements

The MySQL Terraform cloud-init creates:
- `datadog@'%'` user with REPLICATION CLIENT, PROCESS, SELECT on performance_schema
- `datadog` schema with `explain_statement` and `enable_events_statements_consumers` procedures
- `performance_schema` enabled with DBM-required settings

## Verify

1. **Datadog UI** → Databases → MySQL
2. **Agent status**: `kubectl exec -it -n datadog daemonset/datadog-agent -- agent status`
3. Check `mysql` under Cluster Checks section

## Security

- Store `datadog_api_key`, `datadog_app_key`, `mysql_datadog_password` in a secret manager
- Use remote Terraform state with encryption
- Restrict EKS node security group to allow outbound to Datadog intake only if needed
