#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

if ! command -v bun >/dev/null 2>&1; then
  echo "❌ bun is not installed. Install Bun from https://bun.sh/."
  exit 1
fi

if [ "${DOMAIN_REPLACE:-false}" = "true" ] && ! command -v python >/dev/null 2>&1; then
  echo "❌ python is required for DOMAIN_REPLACE=true."
  exit 1
fi

if [ ! -f ".env.prod" ] && [ ! -f ".env" ]; then
  echo "❌ Missing .env.prod or .env file. Copy .env.prod.example to .env.prod and set values."
  exit 1
fi

if [ "${DOMAIN_REPLACE:-false}" = "true" ]; then
  echo "🔁 Running safe domain replacement: cashflowcasino.com -> mmcrt.com"
  python scripts/safe-domain-replace.py cashflowcasino.com mmcrt.com --backup
fi

echo "📦 Installing Bun dependencies..."
bun install

echo "🛠️ Building frontend..."
bun --cwd frontend build

echo "🧩 Copying frontend build into backend/public..."
rm -rf backend/public/*
mkdir -p backend/public
cp -a frontend/dist/. backend/public/

echo "✅ Typechecking backend..."
bun --cwd backend typecheck

echo "🚀 Building backend..."
bun --cwd backend build

if [ "${MIGRATE_DB:-false}" = "true" ]; then
  echo "📚 Running database migrations..."
  bun --cwd backend migrate
fi

STARTED=false
if [ "${START_SERVICE:-false}" = "true" ]; then
  echo "▶️ Starting backend service in production mode..."
  export NODE_ENV=production
  export BUN_ENV=production
  bun --cwd backend start &
  SERVICE_PID=$!
  STARTED=true
  echo "Started backend with PID ${SERVICE_PID}. Waiting for startup..."
  sleep 5
fi

if [ -n "${HEALTH_URL:-}" ]; then
  echo "🔎 Running health check against ${HEALTH_URL}"
  ./scripts/health-check.sh "${HEALTH_URL}"
else
  echo "ℹ️ No HEALTH_URL provided, skipping health check. Set HEALTH_URL to verify endpoint status."
fi

if [ "$STARTED" = true ]; then
  echo "✅ Deployment script completed. Backend is running with PID ${SERVICE_PID}."
else
  echo "✅ Build complete. No backend service was started."
fi
