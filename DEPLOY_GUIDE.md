# Production Deployment & Domain Migration Guide

## Project Overview

This repository is a Bun monorepo with a split frontend/backend architecture.

- `backend/`: Bun + Hono API, Drizzle ORM, auth/session logic, OpenAPI support, static asset serving from `backend/public`.
- `frontend/`: Vue 3 + Vite application with generated SDK client code in `frontend/src/sdk`.
- `docker-compose.prod.yml`: production compose orchestration for backend and Postgres.
- `scripts/production-build.sh` / `scripts/production-start.sh`: build and start helpers.
- `scripts/safe-domain-replace.py`: safe text-based domain replacement utility.

## Pre-deployment Checklist

1. Verify production runtime environment
   - Bun installed on the target machine: `bun --version`
   - Node-compatible tooling available for codegen/migrations
   - TLS certificates provisioned for `*.mmcrt.com`

2. Confirm environment files
   - Copy `.env.prod.example` to `.env.prod`
   - Do not commit production secrets
   - Confirm these values are set:
     - `NODE_ENV=production`
     - `PORT=9999`
     - `LOG_LEVEL=info`
     - `DATABASE_URL`
     - `DATABASE_AUTH_TOKEN`
     - `ACCESS_TOKEN_SECRET`
     - `R2_PUBLIC_URL`
     - `R2_BUCKET_NAME`
     - `RCLONE_R2_REMOTE`
   - Optional staging/domain variables for future refactors:
     - `APP_HOST`
     - `API_HOST`
     - `SLOTS_HOST`
     - `VITE_API_BASE_URL`
     - `COOKIE_DOMAIN`
     - `CORS_ALLOWED_ORIGINS`
     - `JWT_ISSUER`

3. Confirm domain and SSL readiness
   - `app.mmcrt.com`, `api.mmcrt.com`, and `slots.mmcrt.com` must have valid HTTPS certificates
   - Old hostnames should remain reachable during migration with redirects to new hostnames
   - Ensure CORS is configured for the new domain set and browser traffic is secure

4. Confirm database access
   - Production Postgres connection works from the backend host
   - Credentials are secret-managed or stored in `.env.prod`
   - Migrations can be applied safely with `bun --cwd backend migrate`

## Domain Migration Steps

### Step 1: Scan for old domain references

The workspace currently contains old-domain references in critical layers:

- `backend/src/app.ts`
- `backend/src/modules/auth/auth.controller.ts`
- `frontend/openapi-ts.config.ts`
- `frontend/src/sdk/runtime.client.ts`
- `frontend/src/sdk/api.ts`
- generated OpenAPI files under `frontend/src/sdk/generated/`
- static/public game loader and proxy code under `backend/public/`
- `frontend/public/games/redtiger/*`

### Step 2: Replace domain values

Use the safe replacement utility for audit and migration:

```bash
python scripts/safe-domain-replace.py cashflowcasino.com mmcrt.com --dry-run
```

If the results are correct, run:

```bash
python scripts/safe-domain-replace.py cashflowcasino.com mmcrt.com --backup
```

### Step 3: Update runtime config

After replacing domain strings, ensure these runtime boundaries are explicit:

- `backend/src/app.ts`: update CORS allowed origins to the `*.mmcrt.com` hosts
- `backend/src/modules/auth/auth.controller.ts`: update cookie domain resolution, issuer, and set-cookie domain values
- `frontend/openapi-ts.config.ts`: update the codegen input URL
- `frontend/src/sdk/runtime.client.ts` and `frontend/src/sdk/api.ts`: update API base URL fallback
- regenerate the SDK client if API host input changes:
  ```bash
  bunx @hey-api/openapi-ts -f ./frontend/openapi-ts.config.ts
  ```

### Step 4: Validate static assets

Inspect game loader and proxy code in:

- `backend/public/injector.js`
- `backend/public/iframe-loader.html`
- `backend/public/nolimit/*`
- `frontend/public/games/redtiger/*`

These assets often contain hardcoded network endpoints and must point at the new production domains or use relative paths where possible.

## Slot Server Verification

1. Deploy a staging slot with `mmcrt.com`-derived hostnames.
2. Use environment variables rather than baked-in domains for API endpoint configuration.
3. Confirm CORS policy does not block the stage origin.
4. Confirm `refresh_token` cookies are set with `SameSite=None` and `Secure`.
5. Verify browser cross-site auth flows between `app.mmcrt.com` and `api.mmcrt.com`.
6. Test game loads and proxy behavior on the slot host.
7. Confirm old domain redirects still route to the new host while the slot is live.

## Recommended Deployment Flow

1. Build production artifacts with `bash ./deploy-prod.sh`
2. Deploy to a staging slot or blue/green host
3. Run health checks against the staging host
4. Swap traffic to the new domain after verification
5. Keep old-domain redirects in place until DNS caches expire

## Deployment Script

Use `deploy-prod.sh` to build, optionally replace domains, optionally migrate DB, and run a health check.

Example:

```bash
DOMAIN_REPLACE=true \
MIGRATE_DB=true \
HEALTH_URL=https://api.mmcrt.com/ \
bash ./deploy-prod.sh
```

### Script capabilities

- installs Bun dependencies
- builds the frontend and backend
- copies frontend assets into `backend/public`
- uses `scripts/safe-domain-replace.py` if requested
- verifies the app via `curl` if `HEALTH_URL` is provided
- optionally runs database migrations when `MIGRATE_DB=true`

## CI/CD Pipeline

A GitHub Actions workflow is included at `.github/workflows/ci-cd.yml` that:

- Runs on push to `main`/`master` and pull requests
- Installs Bun and dependencies
- Runs linting, typechecking, and builds
- Runs tests (if configured)
- Uploads build artifacts
- Deploys to staging on main branch pushes
- Deploys to production with manual approval

### Required GitHub Secrets

For the CI/CD pipeline to work with database migrations and deployments, set these secrets in your repository:

- `DATABASE_URL`: Production database connection string
- `DATABASE_AUTH_TOKEN`: Database authentication token
- `ACCESS_TOKEN_SECRET`: JWT signing secret
- `R2_PUBLIC_URL`: Cloudflare R2 public URL
- `R2_BUCKET_NAME`: Cloudflare R2 bucket name
- `RCLONE_R2_REMOTE`: Rclone remote configuration

### Health Check

Use the included health check script:

```bash
./scripts/health-check.sh https://api.mmcrt.com/
```

Or set the `TIMEOUT` environment variable for custom timeout:

```bash
TIMEOUT=30 ./scripts/health-check.sh https://api.mmcrt.com/
```

## Notes and Risks

- Production auth relies on secure cookies. HTTPS is mandatory.
- The current repo still contains hardcoded hostnames in generated SDK and static assets until a full replacement is completed.
- If you migrate domains, do not deploy in-place without a staging verification step.
- Use secrets managers for `ACCESS_TOKEN_SECRET` and `DATABASE_AUTH_TOKEN` rather than hardcoding them.
