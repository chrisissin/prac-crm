# EKS Cluster for CRM

Creates an EKS cluster in the VPC and subnets from `terraform/mysql`.

**Run MySQL Terraform first** – this module reads `../mysql/terraform.tfstate` for `vpc_id` and `private_subnet_ids`.

## Quick Start

```bash
cd terraform/eks
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

Or use `./scripts/setup-aws.sh` which runs MySQL → EKS → deploy in one go.

## Outputs

- `cluster_name` – use with `aws eks update-kubeconfig --name <cluster_name>`
- `cluster_endpoint` – EKS API endpoint

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| aws_region | us-west-1 | Region (must match MySQL terraform) |
| project_name | crm | Must match terraform/mysql |
| environment | prod | Must match terraform/mysql |
| node_instance_type | t3.micro | EC2 type for nodes |
