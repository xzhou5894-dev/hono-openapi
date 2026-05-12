#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

export NODE_ENV=production
export BUN_ENV=production

echo "Starting backend in production mode on port ${PORT:-9999}..."
bun --cwd backend start
