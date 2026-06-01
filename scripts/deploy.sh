#!/bin/bash
# RiMi production deploy script
# Usage: ./scripts/deploy.sh
# Prerequisites:
#   1. fly auth login  (one-time)
#   2. Set NEON_MIGRATOR_URL and NEON_APP_URL env vars (from Neon console)
#   3. JWT keys at /tmp/rimi_prod.pem and /tmp/rimi_prod_pub.pem
#      Generate: openssl genrsa -out /tmp/rimi_prod.pem 4096
#                openssl rsa -in /tmp/rimi_prod.pem -pubout -out /tmp/rimi_prod_pub.pem

set -e
cd "$(dirname "$0")/.."

echo "=== RiMi Deploy ==="

# Check prerequisites
if ! flyctl status --app rimi-api &>/dev/null; then
  echo "Creating Fly.io app..."
  flyctl apps create rimi-api --org personal 2>/dev/null || true
fi

# Require Neon URLs
if [ -z "$NEON_MIGRATOR_URL" ] || [ -z "$NEON_APP_URL" ]; then
  echo ""
  echo "ERROR: Set Neon connection strings first:"
  echo "  export NEON_MIGRATOR_URL='postgresql://rimi_migrator:...@ep-xxx.ap-southeast-1.aws.neon.tech/rimi?sslmode=require'"
  echo "  export NEON_APP_URL='postgresql://rimi_app:...@ep-xxx.ap-southeast-1.aws.neon.tech/rimi?sslmode=require'"
  echo ""
  echo "Get these from: https://console.neon.tech → your project → Connection Details"
  exit 1
fi

# Require JWT keys
if [ ! -f /tmp/rimi_prod.pem ] || [ ! -f /tmp/rimi_prod_pub.pem ]; then
  echo "Generating production RSA keys..."
  openssl genrsa -out /tmp/rimi_prod.pem 4096 2>/dev/null
  openssl rsa -in /tmp/rimi_prod.pem -pubout -out /tmp/rimi_prod_pub.pem 2>/dev/null
fi

echo "Setting Fly.io secrets..."
flyctl secrets set \
  DB_MIGRATOR_URL="$NEON_MIGRATOR_URL" \
  DB_APP_URL="$NEON_APP_URL" \
  JWT_PRIVATE_KEY_PEM="$(cat /tmp/rimi_prod.pem)" \
  JWT_PUBLIC_KEY_PEM="$(cat /tmp/rimi_prod_pub.pem)" \
  --app rimi-api

echo "Deploying..."
flyctl deploy --app rimi-api

echo ""
HOSTNAME=$(flyctl status --app rimi-api --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Hostname','rimi-api.fly.dev'))" 2>/dev/null || echo "rimi-api.fly.dev")
echo "=== Deploy complete ==="
echo "API URL: https://$HOSTNAME"
echo ""
echo "Health check:"
curl -s "https://$HOSTNAME/v1/health" | python3 -m json.tool 2>/dev/null || echo "(may take 30s to wake up)"
