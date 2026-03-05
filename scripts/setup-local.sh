#!/usr/bin/env bash
# Local development setup - MySQL + Rails, both in Docker
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> CRM Local Setup (Docker)"
echo "    Project root: $PROJECT_ROOT"
echo ""

# 1. Build and start services
echo "==> [1/4] Building and starting MySQL + Rails..."
cd "$PROJECT_ROOT"
docker compose build
docker compose up -d

echo "    Waiting for MySQL to be ready..."
for i in $(seq 1 60); do
  if docker compose exec -T mysql mysqladmin ping -h localhost -u root -proot --silent 2>/dev/null; then
    echo "    MySQL is ready."
    break
  fi
  if [[ $i -eq 60 ]]; then
    echo "    ERROR: MySQL did not become ready in time."
    exit 1
  fi
  sleep 2
done

# 2. Bundle install (runs via entrypoint on start; ensure deps are ready)
echo ""
echo "==> [2/4] Ensuring Ruby dependencies..."
docker compose exec crm bundle install

# 3. Database setup
echo ""
echo "==> [3/4] Setting up database..."
docker compose exec crm bundle exec rails db:create db:migrate db:seed

# 4. Done
echo ""
echo "==> [4/4] Done!"
echo ""
echo "  App running at http://localhost:3000"
echo "  Login: admin@crm.local / changeme"
echo ""
echo "  Logs:  docker compose logs -f crm"
echo "  Stop:  docker compose down"
echo ""
