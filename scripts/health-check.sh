#!/usr/bin/env bash
set -euo pipefail

# Health check script for the application
# Usage: ./scripts/health-check.sh [URL]

URL="${1:-http://localhost:9999}"
TIMEOUT="${TIMEOUT:-10}"

echo "🔎 Checking health at ${URL} (timeout: ${TIMEOUT}s)"

if ! curl --fail --silent --show-error --max-time "${TIMEOUT}" "${URL}"; then
  echo "❌ Health check failed for ${URL}" >&2
  exit 1
fi

echo "✅ Health check passed for ${URL}"
