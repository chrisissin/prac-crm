# Bastion / Jump host for SSH + kubectl access to EKS
# SSH into the bastion and run kubectl there (inside the VPC)

data "aws_ssm_parameter" "bastion_ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

resource "aws_security_group" "bastion" {
  name        = "${local.name_prefix}-bastion-sg"
  description = "SSH access for bastion host"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.bastion_allowed_cidrs
    description = "SSH"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${local.name_prefix}-bastion-sg"
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ssm_parameter.bastion_ami.value
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = aws_key_pair.mysql.key_name
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = base64encode(templatefile("${path.module}/cloud-init/bastion.yml", {
    aws_region      = var.aws_region
    eks_cluster_name = var.eks_cluster_name
  }))

  user_data_replace_on_change = true

  tags = {
    Name = "${local.name_prefix}-bastion"
    Role = "bastion"
  }
}
