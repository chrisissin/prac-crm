# Copy to terraform.tfvars and fill in values
# Do not commit terraform.tfvars with secrets!

aws_region   = "us-west-1"
environment  = "prod"
project_name = "crm"

# Get AZs: aws ec2 describe-availability-zones --query 'AvailabilityZones[*].ZoneName'
availability_zones = ["us-west-1a", "us-west-1c"]

# SSH public key - set via: export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"
# Or uncomment and paste your key (single line): ssh_public_key = "ssh-rsa AAAA... your@email.com"

# MySQL credentials - use TF_VAR or sensitive backend
# export TF_VAR_mysql_root_password="..."
# export TF_VAR_mysql_replication_password="..."
# export TF_VAR_mysql_app_password="..."
# export TF_VAR_mysql_datadog_password="..."   # For Datadog DBM (optional)
# export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"

mysql_replica_count = 1
