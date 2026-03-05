#!/bin/sh
set -e
cd /app

bundle install

# Wait for MySQL to be reachable
echo "Waiting for MySQL..."
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if ruby -e "require 'socket'; TCPSocket.new('mysql', 3306).close" 2>/dev/null; then
    echo "MySQL reachable."
    bundle exec rails db:create 2>/dev/null || true
    bundle exec rails db:migrate 2>/dev/null || true
    break
  fi
  if [ "$i" = "15" ]; then
    echo "Warning: MySQL not reachable after 30s, continuing..."
  fi
  sleep 2
done

exec "$@"
