# Datadog Monitoring Terraform Variables

variable "datadog_api_key" {
  description = "Datadog API key"
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Datadog Application key (for Cluster Agent)"
  type        = string
  sensitive   = true
}

variable "datadog_site" {
  description = "Datadog intake site (datadoghq.com, datadoghq.eu, etc.)"
  type        = string
  default     = "datadoghq.com"
}

variable "environment" {
  description = "Environment name for tagging"
  type        = string
  default     = "prod"
}

variable "cluster_name" {
  description = "EKS cluster name (for Datadog agent)"
  type        = string
}

variable "mysql_master_host" {
  description = "MySQL master host (private IP) for DBM - from terraform/mysql output"
  type        = string
}

variable "mysql_replica_hosts" {
  description = "MySQL replica hosts for DBM"
  type        = list(string)
  default     = []
}

variable "mysql_datadog_password" {
  description = "Password for datadog@ MySQL user (for DBM)"
  type        = string
  sensitive   = true
}

variable "namespace" {
  description = "Kubernetes namespace for Datadog agent"
  type        = string
  default     = "datadog"
}
