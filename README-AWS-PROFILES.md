# AWS Profiles Setup (Multiple Accounts)

Configure and use multiple AWS accounts on your laptop with named profiles.

## Quick Start

```bash
./scripts/setup-aws-profiles.sh
```

Interactive menu: list profiles, verify credentials, add profile, set for session.

---

## 1. Configure Profiles

### Option A: Access Keys (IAM User)

**Interactive setup:** `aws configure --profile <name>`

| Prompt | What to enter |
|--------|---------------|
| **AWS Access Key ID** | From IAM → Users → Your user → Security credentials → Create access key. Copy the Access Key ID (starts with `AKIA...`). |
| **AWS Secret Access Key** | Shown once when you create the access key. Copy immediately — AWS won't show it again. If lost, create a new access key. |
| **Default region name** | AWS region. Use `us-west-1` for this project, or `us-east-1`, `ap-northeast-2`, etc. |
| **Default output format** | `json` (for scripts), `table` (for terminals), or leave blank (defaults to json). |

**Get access keys:** IAM Console → Users → [your user] → Security credentials → Access keys → Create access key. Choose "Command Line Interface (CLI)" and copy both values.

**Manual edit** — or edit `~/.aws/credentials`:

```ini
[default]
aws_access_key_id = AKIAXXXXXXXXXXXXXXXX
aws_secret_access_key = xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

[work]
aws_access_key_id = AKIAYYYYYYYYYYYYYYYY
aws_secret_access_key = yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy

[personal]
aws_access_key_id = AKIAZZZZZZZZZZZZZZ
aws_secret_access_key = zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
```

### Option B: AWS SSO (IAM Identity Center)

```bash
aws configure sso
```

Follow prompts: SSO start URL, region, account, role, default region, profile name.

---

## 2. Set Default Region (Optional)

Edit `~/.aws/config`:

```ini
[default]
region = us-west-1

[profile work]
region = us-west-1

[profile personal]
region = us-east-1
```

Note: profile-specific entries use `[profile name]`, not `[name]`.

---

## 3. Verify

```bash
# Default profile
aws sts get-caller-identity

# Named profile
aws sts get-caller-identity --profile work

# Or use the helper script
./scripts/setup-aws-profiles.sh
```

---

## 4. Use a Profile with CRM Setup

```bash
export AWS_PROFILE=work
./scripts/setup-aws.sh
```

Or one-liner:

```bash
AWS_PROFILE=work ./scripts/setup-aws.sh
```

---

## 5. SSO Login (If Using SSO Profiles)

SSO sessions expire. Refresh before running setup:

```bash
aws sso login --profile work-sso
export AWS_PROFILE=work-sso
./scripts/setup-aws.sh
```

---

## Quick Reference

| Task | Command |
|------|---------|
| List profiles | `aws configure list-profiles` |
| Current identity | `aws sts get-caller-identity` |
| Use profile for CRM setup | `AWS_PROFILE=work ./scripts/setup-aws.sh` |
| Set profile for session | `export AWS_PROFILE=work` |
| SSO login (refresh) | `aws sso login --profile work-sso` |

---

## Security

- Do **not** commit `~/.aws/credentials` or `~/.aws/config` with secrets
- Store access keys in a password manager
- Prefer SSO/AssumeRole over long-lived access keys when possible
- Rotate keys periodically
