# MySQL 5.6 Master and Replica EC2 Instances
# AMI: mysql_master_ami if set, else SSM Parameter Store (ssm:GetParameters; no ec2:DescribeImages needed)

locals {
  ami_from_config = var.mysql_master_ami != "" ? var.mysql_master_ami : null
}

data "aws_ssm_parameter" "ubuntu_ami" {
  count = local.ami_from_config == null ? 1 : 0
  name  = "/aws/service/canonical/ubuntu/server/20.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

locals {
  ami_id = local.ami_from_config != null ? local.ami_from_config : data.aws_ssm_parameter.ubuntu_ami[0].value
}

# --- MySQL Master ---

resource "aws_instance" "mysql_master" {
  ami                    = local.ami_id
  instance_type           = var.mysql_master_instance_type
  subnet_id               = aws_subnet.private[0].id
  vpc_security_group_ids  = [aws_security_group.mysql.id, aws_security_group.mysql_ssh.id]
  key_name                = aws_key_pair.mysql.key_name
  iam_instance_profile    = aws_iam_instance_profile.mysql_ssm.name
  disable_api_termination = var.environment == "prod"

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_size           = var.mysql_master_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = false
  }

  user_data = base64encode(templatefile("${path.module}/cloud-init/master.yml", {
    mysql_root_password       = var.mysql_root_password
    mysql_replication_user   = var.mysql_replication_user
    mysql_replication_password = var.mysql_replication_password
    mysql_database_name      = var.mysql_database_name
    mysql_app_username       = var.mysql_app_username
    mysql_app_password       = var.mysql_app_password
    mysql_datadog_password   = var.mysql_datadog_password
    environment              = var.environment
  }))

  user_data_replace_on_change = true

  # Wait for NAT so cloud-init can apt-get (private subnet needs NAT for internet)
  depends_on = [aws_nat_gateway.main]

  tags = {
    Name   = "${local.name_prefix}-mysql-master"
    Role   = "mysql-master"
  }
}

# --- MySQL Replicas ---

resource "aws_instance" "mysql_replica" {
  count                  = var.mysql_replica_count
  ami                    = local.ami_id
  instance_type           = var.mysql_replica_instance_type
  subnet_id               = aws_subnet.private[count.index % length(aws_subnet.private)].id
  vpc_security_group_ids  = [aws_security_group.mysql.id, aws_security_group.mysql_ssh.id]
  key_name                = aws_key_pair.mysql.key_name
  iam_instance_profile    = aws_iam_instance_profile.mysql_ssm.name

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_size           = var.mysql_replica_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = false
  }

  user_data = base64encode(templatefile("${path.module}/cloud-init/replica.yml", {
    mysql_master_host        = aws_instance.mysql_master.private_ip
    mysql_root_password      = var.mysql_root_password
    mysql_replication_user  = var.mysql_replication_user
    mysql_replication_password = var.mysql_replication_password
    mysql_datadog_password  = var.mysql_datadog_password
    replica_index           = count.index + 1
    environment             = var.environment
  }))

  user_data_replace_on_change = true

  depends_on = [aws_instance.mysql_master]

  tags = {
    Name   = "${local.name_prefix}-mysql-replica-${count.index + 1}"
    Role   = "mysql-replica"
  }
}

# --- Key pair (provide your public key via variable or file) ---

resource "aws_key_pair" "mysql" {
  key_name   = "${local.name_prefix}-mysql-key"
  public_key = var.ssh_public_key

  lifecycle {
    ignore_changes = [public_key]
  }
}

variable "ssh_public_key" {
  description = "SSH public key for EC2 access"
  type        = string
}
