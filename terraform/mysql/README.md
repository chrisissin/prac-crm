# MySQL 5.6 Terraform - Master/Replica on AWS EC2

Creates VPC, MySQL master and replica(s), S3 bucket for backups, and IAM for SSM + S3.

## Prerequisites

- Terraform >= 1.0
- AWS CLI configured
- SSH key pair

## Quick Start

1. Create `terraform.tfvars`:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Set variables (use env or tfvars):
   ```bash
   export TF_VAR_mysql_root_password="..."
   export TF_VAR_mysql_replication_password="..."
   export TF_VAR_mysql_app_password="..."
   export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"
   ```

3. Get availability zones:
   ```bash
   aws ec2 describe-availability-zones --query 'AvailabilityZones[*].ZoneName' --output text
   ```

4. Apply:
   ```bash
   cd terraform/mysql
   terraform init
   terraform plan
   terraform apply
   ```

## Outputs

- `mysql_master_private_ip` - Use this for Rails DATABASE_HOST
- `mysql_replica_private_ips` - Read replica endpoints
- `mysql_backup_bucket` - S3 bucket for backup scripts

## Architecture

- **Master**: 1 EC2 in private subnet, EBS for data
- **Replica(s)**: N EC2 across subnets
- **Replication**: GTID or file/position based
- **Backup**: S3 bucket with lifecycle policies

## Notes

- MySQL 5.6 is EOL; consider 5.7/8.0 for production
- Ubuntu 20.04 AMI used; MySQL 5.6 from Oracle APT repo
- Use SSM Session Manager for SSH (no bastion needed)
