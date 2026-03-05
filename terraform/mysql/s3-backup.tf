# S3 bucket for MySQL backups

resource "aws_s3_bucket" "mysql_backup" {
  bucket = "${var.project_name}-${var.environment}-mysql-backup-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${local.name_prefix}-mysql-backup"
  }
}

resource "aws_s3_bucket_versioning" "mysql_backup" {
  bucket = aws_s3_bucket.mysql_backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mysql_backup" {
  bucket = aws_s3_bucket.mysql_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "mysql_backup" {
  bucket = aws_s3_bucket.mysql_backup.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "mysql_backup" {
  bucket = aws_s3_bucket.mysql_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_caller_identity" "current" {}
