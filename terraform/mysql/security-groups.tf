# Security Groups for MySQL Master and Replicas

# MySQL cluster internal traffic (master <-> replicas, app connections)
resource "aws_security_group" "mysql" {
  name        = "${local.name_prefix}-mysql-sg"
  description = "Security group for MySQL master and replicas"
  vpc_id      = aws_vpc.main.id

  # MySQL port from within VPC
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "MySQL from VPC"
  }

  # Replication traffic
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    self        = true
    description = "MySQL replication within cluster"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${local.name_prefix}-mysql-sg"
  }
}

# SSH access (optional - for ops/debugging)
resource "aws_security_group" "mysql_ssh" {
  name        = "${local.name_prefix}-mysql-ssh-sg"
  description = "SSH access for MySQL instances (attach to bastion or restricted)"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"] # Restrict to your VPN/corporate IP in production
    description = "SSH"
  }

  tags = {
    Name = "${local.name_prefix}-mysql-ssh-sg"
  }
}
