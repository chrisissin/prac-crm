# MySQL 5.6 on AWS EC2 - Terraform Variables
# Supports master-replica replication

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "crm"
}

# VPC
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (bastion, NAT)"
  type        = list(string)
  default     = ["10.0.100.0/24", "10.0.101.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "Availability zones for subnets"
  type        = list(string)
}

# EC2 - MySQL Master
variable "mysql_master_instance_type" {
  description = "EC2 instance type for MySQL master (t3.micro for Free Tier)"
  type        = string
  default     = "t3.micro"
}

variable "mysql_master_volume_size" {
  description = "EBS volume size (GB) for MySQL master data"
  type        = number
  default     = 100
}

variable "mysql_master_ami" {
  description = "AMI for MySQL master (Ubuntu 20.04). Empty = use region default or lookup (requires ec2:DescribeImages)"
  type        = string
  default     = "" # Set to specific AMI if IAM lacks ec2:DescribeImages
}

# EC2 - MySQL Replica
variable "mysql_replica_instance_type" {
  description = "EC2 instance type for MySQL replica (t3.micro for Free Tier)"
  type        = string
  default     = "t3.micro"
}

variable "mysql_replica_volume_size" {
  description = "EBS volume size (GB) for MySQL replica data"
  type        = number
  default     = 100
}

variable "mysql_replica_count" {
  description = "Number of MySQL replica instances"
  type        = number
  default     = 1
}

# MySQL Configuration
variable "mysql_version" {
  description = "MySQL version"
  type        = string
  default     = "5.6"
}

variable "mysql_root_password" {
  description = "MySQL root password (use TF_VAR or secrets)"
  type        = string
  sensitive   = true
}

variable "mysql_replication_user" {
  description = "MySQL replication username"
  type        = string
  default     = "repl_user"
}

variable "mysql_replication_password" {
  description = "MySQL replication password"
  type        = string
  sensitive   = true
}

variable "mysql_database_name" {
  description = "Application database name"
  type        = string
  default     = "crm_production"
}

variable "mysql_app_username" {
  description = "Application database username"
  type        = string
  default     = "crm_app"
}

variable "mysql_app_password" {
  description = "Application database password"
  type        = string
  sensitive   = true
}

# Datadog DBM (Database Monitoring)
variable "mysql_datadog_password" {
  description = "Password for datadog@ MySQL user (Datadog DBM)"
  type        = string
  sensitive   = true
  default     = ""
}

# Bastion
variable "bastion_instance_type" {
  description = "EC2 instance type for bastion (t3.micro for Free Tier)"
  type        = string
  default     = "t3.micro"
}

variable "bastion_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH into bastion"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "eks_cluster_name" {
  description = "EKS cluster name (for bastion kubeconfig). When set, bastion configures kubectl on boot."
  type        = string
  default     = ""
}

# Tags
variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
