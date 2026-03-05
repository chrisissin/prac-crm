# MySQL 5.6 Master-Replica on AWS EC2
# Terraform >= 1.0

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.63.0"  # Pin to 5.63.x for Apple Silicon (5.64+ can timeout on plugin start)
    }
  }

  # Uncomment for remote state
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "mysql/terraform.tfstate"
  #   region         = "ap-northeast-2"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    })
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}
