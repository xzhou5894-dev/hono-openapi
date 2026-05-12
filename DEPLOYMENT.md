# Production Deployment Guide

This repository is a Bun monorepo with a `backend` Hono API and a `frontend` Vite app. The backend serves built frontend assets from `backend/public`.

## Architecture

- `backend/`: Bun-based Hono API, WebSocket proxy, Postgres database access via Drizzle.
- `frontend/`: Vue 3 + Vite frontend app.
- `docker-compose.yml`: local Postgres service.
- `backend/public/`: backend static asset root. Built frontend files must be copied here for production.

## Production Prerequisites

1. Install Bun on the production machine.
   - https://bun.sh/
2. Install PostgreSQL in production or use a managed Postgres service.
3. Create a production `.env` file with the required environment variables.
4. Ensure the production host allows port `9999` (or your configured `PORT`).

## Required Environment Variables

The backend will fail fast if any required variable is missing.

- `NODE_ENV=production`
- `PORT=9999`
- `LOG_LEVEL=info`
- `DATABASE_URL=postgres://user:password@host:5432/database`
- `DATABASE_AUTH_TOKEN=production-auth-token`
- `ACCESS_TOKEN_SECRET=strong-secret-value`
- `R2_PUBLIC_URL=https://...`
- `R2_BUCKET_NAME=...`
- `RCLONE_R2_REMOTE=...`

> Note: `R2_PUBLIC_URL`, `R2_BUCKET_NAME`, and `RCLONE_R2_REMOTE` are validated by `backend/src/env.ts`. If your deployment does not use R2, provide safe placeholder values or update the env schema accordingly.

## Build and Deployment Scripts

### 1. Build the production app

From the repo root:

```sh
bash ./scripts/production-build.sh
```

This script will:

- install Bun dependencies
- build the frontend
- copy built assets into `backend/public`
- typecheck the backend
- build the backend

### 2. Start the backend

```sh
bash ./scripts/production-start.sh
```

This script runs the backend in production mode using Bun.

### 3. Run migrations

```sh
bun --cwd backend migrate
```

If you want to seed or reset the database in production, use the existing backend scripts with care:

```sh
bun --cwd backend seed
bun --cwd backend db:reset
```

## Local Production with Docker Compose

Use `docker-compose.yml` for Postgres and the backend service.

### Recommended `docker-compose.prod.yml`

The repository includes a production compose file that builds the backend image and starts Postgres.

```sh
cp .env.prod.example .env.prod
# Edit .env.prod with real secrets
docker compose -f docker-compose.prod.yml up --build -d
```

### Notes

- The backend container is built from `backend/Dockerfile`.
- The production compose file references `.env.prod` for secrets.

## Deployment Checklist

1. Verify `.env` or `.env.prod` contains all required values.
2. Run `bash ./scripts/production-build.sh` locally or in CI.
3. Run `bun --cwd backend migrate` after the database is available.
4. Start the backend with `bash ./scripts/production-start.sh` or `docker compose -f docker-compose.prod.yml up --build -d`.
5. Confirm the app and static assets are reachable at `http://<host>:9999`.
6. Check logs for startup errors related to environment variables or database connectivity.

## CI/CD / Release Pipeline

A minimal production pipeline should include:

1. `bun install`
2. `bash ./scripts/production-build.sh`
3. `bun --cwd backend typecheck`
4. `bun --cwd frontend build`
5. `bun --cwd backend migrate` against the target database
6. Deploy the backend runtime and restart the service.

## Production Hardening Tips

- Pin Postgres image versions instead of using `postgres:latest`.
- Run the backend behind a reverse proxy or load balancer.
- Use HTTPS and valid certificates.
- Keep `ACCESS_TOKEN_SECRET` and `DATABASE_AUTH_TOKEN` in a secret manager.
- Monitor Bun process health and restart automatically with a process manager or container orchestrator.
