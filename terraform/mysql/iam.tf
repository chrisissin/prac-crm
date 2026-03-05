# IAM for MySQL instances (SSM Session Manager, S3 backup access)

resource "aws_iam_role" "mysql" {
  name = "${local.name_prefix}-mysql-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "mysql_ssm" {
  role       = aws_iam_role.mysql.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Optional: S3 access for backup scripts
resource "aws_iam_role_policy" "mysql_s3_backup" {
  name = "${local.name_prefix}-mysql-s3-backup"
  role = aws_iam_role.mysql.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.mysql_backup.arn,
          "${aws_s3_bucket.mysql_backup.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "mysql_ssm" {
  name = "${local.name_prefix}-mysql-profile"
  role = aws_iam_role.mysql.name
}
