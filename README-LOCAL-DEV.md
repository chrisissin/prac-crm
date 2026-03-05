# Local Development Guide

Run the CRM app **fully in Docker**: MySQL 5.6 + Rails, both as containers.

## Prerequisites

- Docker and Docker Compose (no Ruby on host needed)

## Quick Start (One Script)

```bash
./scripts/setup-local.sh
```

Open http://localhost:3000 — Login: `admin@crm.local` / `changeme`

If login fails, re-run seeds: `docker compose exec crm bundle exec rails db:seed` — or reset fully: `docker compose exec crm bundle exec rails db:drop db:create db:migrate db:seed`

## Manual Steps

### 1. Start all services

```bash
docker compose up -d
```

### 2. First-time setup

```bash
docker compose exec crm bundle install
docker compose exec crm bundle exec rails db:create db:migrate db:seed
```

### 3. View logs

```bash
docker compose logs -f crm
```

---

## Docker Details

| Service | Port | Notes |
|---------|------|-------|
| crm (Rails) | 3000 | Volume mount for live code reload |
| mysql | 3306 | Root: root, App: crm_app / crm_dev_password |

Connect to MySQL from host:

```bash
mysql -h 127.0.0.1 -P 3306 -u crm_app -pcrm_dev_password crm_development
```

Code changes in `crm/` are reflected on reload (no rebuild needed).

---

## Run Tests

```bash
docker compose exec crm bundle exec rails db:create db:migrate RAILS_ENV=test
docker compose exec crm bundle exec rails test
```

## Reset Database

```bash
docker compose exec crm bundle exec rails db:drop db:create db:migrate db:seed
```

## Stop

```bash
docker compose down
# With data: docker compose down -v
```
