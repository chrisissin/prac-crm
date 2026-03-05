# CRM - Ruby on Rails

A CRM application with Accounts, Contacts, Leads, Deals, and Activities.

## Local Setup

```bash
bundle install
cp config/database.yml config/database.yml.local  # configure for local MySQL
rails db:create db:migrate db:seed
rails s
```

Default login (after seed): `admin@crm.local` / `changeme`

## Production (Docker + K8s)

See `../k8s/README.md` for EKS deployment.

## Environment Variables

| Variable | Description |
|----------|-------------|
| DATABASE_HOST | MySQL host (from Terraform output) |
| DATABASE_PORT | 3306 |
| DATABASE_NAME | crm_production |
| DATABASE_USERNAME | crm_app |
| DATABASE_PASSWORD | From Terraform |
| SECRET_KEY_BASE | `rails secret` |
| RAILS_ENV | production |
| RAILS_MAX_THREADS | 5 |
