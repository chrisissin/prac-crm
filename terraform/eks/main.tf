# EKS cluster for CRM - uses VPC and subnets from terraform/mysql

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.63.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

data "terraform_remote_state" "mysql" {
  backend = "local"

  config = {
    path = "${path.module}/../mysql/terraform.tfstate"
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "${local.name_prefix}-eks"
  cluster_version = var.cluster_version

  vpc_id     = data.terraform_remote_state.mysql.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.mysql.outputs.private_subnet_ids

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      min_size       = 1
      max_size       = 3
      desired_size   = 2
    }
  }
}
