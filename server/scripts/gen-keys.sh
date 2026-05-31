#!/usr/bin/env bash
# Generate RS256 key pair for development.
# SECRETS-01: Private key MUST NOT be committed.
# Run: bash scripts/gen-keys.sh
# Then copy the output into your .env file.

set -euo pipefail

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

openssl genrsa -out "$TMPDIR/private.pem" 2048
openssl rsa -in "$TMPDIR/private.pem" -pubout -out "$TMPDIR/public.pem"

echo "# Copy these into your .env (NEVER commit the private key)"
echo ""
echo "JWT_PRIVATE_KEY_PEM=$(awk 'NR>1{printf "%s\\n", prev} {prev=$0} END{printf "%s", prev}' "$TMPDIR/private.pem" | head -c 99999)"
echo ""
echo "JWT_PUBLIC_KEY_PEM=$(awk 'NR>1{printf "%s\\n", prev} {prev=$0} END{printf "%s", prev}' "$TMPDIR/public.pem" | head -c 99999)"
