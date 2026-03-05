variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project name (must match terraform/mysql)"
  type        = string
  default     = "crm"
}

variable "environment" {
  description = "Environment (must match terraform/mysql)"
  type        = string
  default     = "prod"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.29"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS nodes (t3.micro for Free Tier)"
  type        = string
  default     = "t3.micro"
}
