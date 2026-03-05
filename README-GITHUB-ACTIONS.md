# GitHub Actions Setup Guide

Step-by-step guide to configure CI/CD for this project.

## Prerequisites

- GitHub repository
- For Rails ECR push: AWS account, ECR repository
- For Infrastructure apply: AWS credentials, Terraform state backend (S3 recommended)

## 1. Enable GitHub Actions

1. Push this project to a GitHub repository
2. Go to **Settings** → **Actions** → **General**
3. Under "Actions permissions", select **Allow all actions and reusable workflows**
4. Save

## 2. Add Secrets

**Option A – Script (requires [gh CLI](https://cli.github.com) and `gh auth login`):**

```bash
./scripts/setup-github-actions.sh --rails        # ECR push
./scripts/setup-github-actions.sh --infra-mysql # Terraform MySQL
./scripts/setup-github-actions.sh --infra-datadog # Terraform Datadog
./scripts/setup-github-actions.sh --all          # All (interactive)
```

With env vars: `AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=xxx ./scripts/setup-github-actions.sh --rails`

**Option B – Manual:** Go to **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

### Rails (ECR Push) – Optional

Add these to push the Docker image to ECR on push to `main`:

| Secret | How to get |
|--------|------------|
| `AWS_ACCOUNT_ID` | `aws sts get-caller-identity --query Account --output text` |
| `AWS_ACCESS_KEY_ID` | IAM user or role access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user or role secret key |
| `AWS_REGION` | e.g. `ap-northeast-2` |

Create the ECR repository first:
```bash
aws ecr create-repository --repository-name crm --region ap-northeast-2
```

### Infrastructure – MySQL Apply – Optional

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS credentials |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials |
| `AWS_REGION` | e.g. `ap-northeast-2` |
| `TF_VAR_SSH_PUBLIC_KEY` | Contents of `~/.ssh/id_rsa.pub` |
| `TF_VAR_MYSQL_ROOT_PASSWORD` | MySQL root password |
| `TF_VAR_MYSQL_REPLICATION_PASSWORD` | Replication user password |
| `TF_VAR_MYSQL_APP_PASSWORD` | App database user password |
| `TF_VAR_MYSQL_DATADOG_PASSWORD` | Datadog DBM user password (or leave empty) |
| `TF_VAR_AVAILABILITY_ZONES` | `["ap-northeast-2a","ap-northeast-2b"]` (adjust for your region) |

### Infrastructure – Datadog Apply – Optional

| Secret | Description |
|--------|-------------|
| `DD_API_KEY` | Datadog → Organization Settings → API Keys |
| `DD_APP_KEY` | Datadog → Organization Settings → Application Keys |
| `EKS_CLUSTER_NAME` | Your EKS cluster name |
| `MYSQL_MASTER_HOST` | MySQL master private IP (from Terraform output) |
| `MYSQL_DATADOG_PASSWORD` | Same as `TF_VAR_MYSQL_DATADOG_PASSWORD` |

**Note:** Apply jobs run **only** when the required secrets are set. Without them, validate/plan jobs still run on PRs.

## 3. Configure Terraform Remote Backend (Recommended)

For Infrastructure apply, Terraform state must persist. Add to `terraform/mysql/main.tf` and `terraform/datadog/main.tf`:

```hcl
backend "s3" {
  bucket         = "your-terraform-state-bucket"
  key            = "mysql/terraform.tfstate"   # or datadog/terraform.tfstate
  region         = "ap-northeast-2"
  encrypt        = true
  dynamodb_table = "terraform-locks"
}
```

Create the S3 bucket and DynamoDB table, then run `terraform init` locally once to migrate state.

## 4. Workflow Behavior

### Rails CI/CD (`.github/workflows/rails.yml`)

| Event | Jobs |
|-------|------|
| **Push / PR** to `main` (paths: `crm/**`) | lint-and-test |
| **Push** to `main` | build |
| **Push** to `main` + AWS secrets | push-ecr |

### Infrastructure CI/CD (`.github/workflows/infrastructure.yml`)

| Event | Jobs |
|-------|------|
| **Push / PR** (paths: `terraform/**`, `k8s/**`, etc.) | validate-mysql, validate-datadog |
| **Push** to `main` + MySQL secrets | apply-mysql |
| **Push** to `main` + Datadog secrets | apply-datadog |
| **Manual** (Actions → Run workflow) | All above |

## 5. Verify

1. Push a change to `crm/` or open a PR → Rails workflow should run
2. Push a change to `terraform/` or open a PR → Infrastructure workflow should run
3. Check **Actions** tab for run history and logs

## 6. Minimal Setup (CI Only)

To run only **validate/test** (no apply or push):

- No secrets required
- PRs and pushes trigger validate/plan and Rails tests
- Apply and push jobs are skipped when secrets are missing
