#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Installing Bun dependencies..."
bun install

echo "Building frontend..."
bun --cwd frontend build

echo "Copying frontend build to backend/static public folder..."
mkdir -p backend/public
cp -a frontend/dist/. backend/public/

echo "Typechecking backend..."
bun --cwd backend typecheck

echo "Building backend..."
bun --cwd backend build

echo "Production build complete."
