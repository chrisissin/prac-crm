# Terraform Outputs

output "mysql_master_private_ip" {
  description = "Private IP of MySQL master"
  value       = aws_instance.mysql_master.private_ip
}

output "mysql_master_instance_id" {
  description = "EC2 instance ID of MySQL master"
  value       = aws_instance.mysql_master.id
}

output "mysql_replica_private_ips" {
  description = "Private IPs of MySQL replicas"
  value       = aws_instance.mysql_replica[*].private_ip
}

output "mysql_replica_instance_ids" {
  description = "EC2 instance IDs of MySQL replicas"
  value       = aws_instance.mysql_replica[*].id
}

output "mysql_backup_bucket" {
  description = "S3 bucket name for MySQL backups"
  value       = aws_s3_bucket.mysql_backup.id
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (for EKS or other resources)"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (bastion, NAT)"
  value       = aws_subnet.public[*].id
}

output "bastion_public_ip" {
  description = "Public IP of bastion host for SSH"
  value       = aws_instance.bastion.public_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect to bastion (run kubectl from there)"
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.bastion.public_ip}"
}
