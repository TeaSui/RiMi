#!/bin/bash
# Start RiMi backend locally for simulator/device development
# Usage: ./scripts/start-local.sh
# API will be available at http://<your-mac-ip>:8080

set -e
cd "$(dirname "$0")/.."

# ── 1. Ensure JWT keys exist ──────────────────────────────────────────
if [ ! -f /tmp/rimi_dev.pem ]; then
  echo "Generating dev JWT keys..."
  openssl genrsa -out /tmp/rimi_dev.pem 2048 2>/dev/null
  openssl rsa -in /tmp/rimi_dev.pem -pubout -out /tmp/rimi_dev_pub.pem 2>/dev/null
  echo "Keys created at /tmp/rimi_dev.pem"
fi

# ── 2. Ensure Postgres is running ─────────────────────────────────────
if ! docker inspect rimi-postgres &>/dev/null; then
  echo "Starting Postgres..."
  docker run -d --name rimi-postgres \
    -e POSTGRES_DB=rimi \
    -e POSTGRES_USER=postgres \
    -e POSTGRES_PASSWORD=postgres \
    -p 5432:5432 \
    postgres:16-alpine
  echo "Waiting for Postgres..."
  sleep 4
elif [ "$(docker inspect rimi-postgres --format='{{.State.Status}}')" != "running" ]; then
  echo "Restarting Postgres..."
  docker start rimi-postgres
  sleep 3
fi

# ── 3. Get Mac local IP for simulator ─────────────────────────────────
MAC_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "localhost")
echo ""
echo "══════════════════════════════════════════"
echo "  RiMi Local Dev Server"
echo "══════════════════════════════════════════"
echo "  API:        http://$MAC_IP:8080"
echo "  Simulator:  http://$MAC_IP:8080"
echo "  DB:         localhost:5432/rimi"
echo "══════════════════════════════════════════"
echo ""
echo "Run Flutter with:"
echo "  flutter run -d <device-id> --dart-define=RIMI_API_BASE_URL=http://$MAC_IP:8080"
echo ""

# ── 4. Build and start the server ─────────────────────────────────────
cd server
go build -o /tmp/rimi-local ./cmd/api

JWT_PRIVATE_KEY_PEM="$(cat /tmp/rimi_dev.pem)" \
JWT_PUBLIC_KEY_PEM="$(cat /tmp/rimi_dev_pub.pem)" \
DB_MIGRATOR_URL="postgres://postgres:postgres@localhost:5432/rimi?sslmode=disable" \
DB_APP_URL="postgres://postgres:postgres@localhost:5432/rimi?sslmode=disable" \
JWT_ISSUER=rimi-auth \
JWT_AUDIENCE=rimi-api \
JWT_KEY_ID=k1 \
PORT=8080 \
MIGRATIONS_PATH="file://migrations" \
SMTP_HOST=localhost \
SMTP_PORT=1025 \
SMTP_FROM=noreply@rimi.app \
/tmp/rimi-local
