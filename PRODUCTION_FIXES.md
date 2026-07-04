# Production Deployment Fixes - Implementation Guide

## Quick Start

All fixes are provided below. Follow in order: **Critical → High Priority → Medium Priority**

---

## PHASE 1: CRITICAL FIXES (MUST DO BEFORE DEPLOYMENT)

### Fix 1: Update drizzle.config.ts - Remove Hardcoded Credentials

**File:** `backend/drizzle.config.ts`

**Current:**
```typescript
import { defineConfig } from 'drizzle-kit'

export default defineConfig({
    schema: './src/db/schema/index.ts',
    out: './drizzle',
    dialect: 'postgresql',
    casing: 'camelCase',
    dbCredentials: {
        url: 'postgres://user:asdfasdf@localhost:5439/cashinin',
    },
})
```

**Replace with:**
```typescript
import { defineConfig } from 'drizzle-kit'
import env from './src/env'

export default defineConfig({
    schema: './src/db/schema/index.ts',
    out: './drizzle',
    dialect: 'postgresql',
    casing: 'camelCase',
    dbCredentials: {
        url: env.DATABASE_URL,
        authToken: env.DATABASE_AUTH_TOKEN,
    },
})
```

---

### Fix 2: Update backend/src/app.ts - Use Environment Variables for CORS

**File:** `backend/src/app.ts`

**Current (lines 19-37):**
```typescript
const allowedOrigins = new Set<string>([
    'http://localhost',
    'http://localhost:5173',
    'http://localhost:5174',
    'http://localhost:9999',
    'http://localhost:3001',
    'http://localhost:3000',
    'https://slots.cashflowcasino.com',
    'https://app.cashflowcasino.com',
    'https://api.cashflowcasino.com',
])
```

**Replace with:**
```typescript
// Parse CORS allowed origins from env, with sensible local defaults
function getAllowedOrigins(): Set<string> {
    const envOrigins = env.CORS_ALLOWED_ORIGINS
        ? env.CORS_ALLOWED_ORIGINS.split(',').map(o => o.trim())
        : []
    
    // Always allow localhost in dev/test
    const defaults = [
        'http://localhost',
        'http://localhost:5173',
        'http://localhost:5174',
        'http://localhost:9999',
        'http://localhost:3001',
        'http://localhost:3000',
    ]
    
    return new Set<string>([...defaults, ...envOrigins])
}

const allowedOrigins = getAllowedOrigins()
```

**Then add to env schema** (`backend/src/env.ts`):
```typescript
const EnvSchema = z.object({
    // ... existing fields ...
    CORS_ALLOWED_ORIGINS: z.string().optional(),
    COOKIE_DOMAIN: z.string().optional(),
    JWT_ISSUER: z.string().optional(),
})
```

---

### Fix 3: Update backend/src/modules/auth/auth.controller.ts - Remove Hardcoded Domains

**File:** `backend/src/modules/auth/auth.controller.ts`

**Current (lines 22-35):**
```typescript
function resolveCookieDomain(host: string | undefined): string | undefined {
    if (!host) return undefined
    const bare = host.split(':')[0].toLowerCase()
    if (bare.endsWith('.cashflowcasino.com')) return '.cashflowcasino.com'
    if (bare === 'cashflowcasino.com') return '.cashflowcasino.com'
    return undefined
}

const ISSUER = 'api.cashflowcasino.com'
```

**Replace with:**
```typescript
function resolveCookieDomain(host: string | undefined): string | undefined {
    // In production, use env COOKIE_DOMAIN; in dev, return undefined
    if (env.NODE_ENV === 'production' && env.COOKIE_DOMAIN) {
        return env.COOKIE_DOMAIN
    }
    if (!host) return undefined
    const bare = host.split(':')[0].toLowerCase()
    // Only set domain if host matches a known production pattern
    if (env.COOKIE_DOMAIN && bare.includes(env.COOKIE_DOMAIN.replace('.', ''))) {
        return env.COOKIE_DOMAIN
    }
    return undefined
}

const ISSUER = env.JWT_ISSUER || 'localhost'
```

---

### Fix 4: Replace All console.log with Structured Logging

**File:** `backend/src/index.ts`

**Step 1:** Add logger import at the top:
```typescript
import pino from 'pino'

const logger = pino(
    process.env.NODE_ENV === 'production'
        ? undefined
        : { transport: { target: 'pino-pretty' } }
)
```

**Step 2:** Replace all console statements:

| Old | New |
|-----|-----|
| `console.log(...)` | `logger.info({msg: ...})` |
| `console.error(...)` | `logger.error({msg: ...})` |
| `console.warn(...)` | `logger.warn({msg: ...})` |
| `console.log(\`Server is running on...\`)` | `logger.info({ port, msg: 'Server running' })` |

**Key replacements in index.ts:**
```typescript
// Line 18: Replace
console.log(`Server is running on http://localhost:${port}`)
// With:
logger.info({ port, msg: 'Server running' })

// Line 25: Replace
console.log(url.searchParams.get('data'))
// With:
logger.debug({ data: url.searchParams.get('data') })

// Line 28: Replace
console.log('here')
// Delete this line

// Line 66: Replace
console.error(chalk.red('[WS Auth] No token provided.'))
// With:
logger.error({ topic: 'ws-auth', error: 'No token provided' })

// Line 73: Replace
console.error(chalk.red('[WS Auth] Invalid token payload.'))
// With:
logger.error({ topic: 'ws-auth', error: 'Invalid token payload' })

// And so on for all other console calls...
```

**Also update error handler:**
```typescript
error(error: Error) {
    logger.error({ error: error.message, stack: error.stack })
    return new Response(
        JSON.stringify({ error: 'Internal Server Error' }),
        { status: 500, headers: { 'content-type': 'application/json' } }
    )
},
```

---

### Fix 5: Update docker-compose.prod.yml - Secure Credentials

**File:** `docker-compose.prod.yml`

**Current:**
```yaml
environment:
  POSTGRES_USER: user
  POSTGRES_PASSWORD: asdfasdf
  POSTGRES_DB: hono
```

**Replace with:**
```yaml
env_file:
  - .env.prod
# Remove all hardcoded credentials
```

**Ensure .env.prod contains:**
```bash
POSTGRES_USER=prod_user
POSTGRES_PASSWORD=<STRONG_RANDOM_PASSWORD>
POSTGRES_DB=production_db
DATABASE_URL=postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
```

---

### Fix 6: Implement CI/CD Deployment Steps

**File:** `.github/workflows/ci-cd.yml`

**For Docker Registry Deployment (DockerHub/ECR):**

```yaml
deploy-production:
  needs: deploy-staging
  runs-on: ubuntu-latest
  if: github.ref == 'refs/heads/master' && github.event_name == 'push'
  environment: production

  steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Setup Bun
      uses: oven-sh/setup-bun@v1
      with:
        bun-version: latest

    - name: Build Docker image
      run: |
        docker build -t ${{ secrets.DOCKER_REGISTRY }}/backend:latest .
        docker tag ${{ secrets.DOCKER_REGISTRY }}/backend:latest ${{ secrets.DOCKER_REGISTRY }}/backend:${{ github.sha }}

    - name: Login to Docker Registry
      run: |
        echo "${{ secrets.DOCKER_PASSWORD }}" | docker login -u "${{ secrets.DOCKER_USERNAME }}" --password-stdin

    - name: Push Docker image
      run: |
        docker push ${{ secrets.DOCKER_REGISTRY }}/backend:latest
        docker push ${{ secrets.DOCKER_REGISTRY }}/backend:${{ github.sha }}

    - name: Deploy to production
      run: |
        # Option 1: SSH + Docker Compose
        ssh -i ${{ secrets.PROD_DEPLOY_KEY }} ${{ secrets.PROD_DEPLOY_USER }}@${{ secrets.PROD_DEPLOY_HOST }} << 'EOF'
          cd /app
          docker pull ${{ secrets.DOCKER_REGISTRY }}/backend:latest
          docker-compose -f docker-compose.prod.yml up -d
          docker-compose -f docker-compose.prod.yml exec -T backend bun --cwd backend migrate
        EOF

    - name: Health check
      run: |
        TIMEOUT=30 ./scripts/health-check.sh https://api.mmcrt.com/
        ./scripts/health-check.sh https://api.mmcrt.com/health

    - name: Notify deployment
      if: success()
      run: |
        echo "✅ Production deployment successful"
        # Add Slack/email notification here
```

**Add these GitHub Secrets:**
- `DOCKER_USERNAME`: Docker Hub username
- `DOCKER_PASSWORD`: Docker Hub token
- `DOCKER_REGISTRY`: docker.io/yourcompany
- `PROD_DEPLOY_HOST`: Production server IP
- `PROD_DEPLOY_USER`: SSH user (ubuntu, ec2-user, etc.)
- `PROD_DEPLOY_KEY`: SSH private key for deployment

---

## PHASE 2: HIGH PRIORITY FIXES

### Fix 7: Correct Docker Multi-Stage Build

**File:** `backend/Dockerfile`

**Current:**
```dockerfile
FROM oven/bun:latest AS builder
WORKDIR /app

COPY backend/package.json backend/bunfig.toml backend/tsconfig.json backend/tsconfig.* backend/src backend/public ./backend/
COPY frontend/package.json frontend/vite.config.ts frontend/tsconfig.json frontend/tsconfig.* frontend/src frontend/public frontend/assets ./frontend/

RUN bun install --cwd backend
RUN bun install --cwd frontend

RUN bun --cwd frontend build
RUN mkdir -p backend/public
RUN cp -a frontend/dist/. backend/public/

RUN bun --cwd backend typecheck
RUN bun --cwd backend build

FROM oven/bun:latest AS runner
WORKDIR /app
COPY --from=builder /app/backend /app/backend

ENV NODE_ENV=production
ENV BUN_ENV=production
EXPOSE 9999

CMD ["bun", "--cwd", "backend", "start"]
```

**Replace with:**
```dockerfile
FROM oven/bun:latest AS builder
WORKDIR /app

# Copy all manifests and configs
COPY backend/package.json backend/bunfig.toml backend/tsconfig.json backend/tsconfig.* ./backend/
COPY frontend/package.json frontend/vite.config.ts frontend/tsconfig.json frontend/tsconfig.* ./frontend/

# Copy source code
COPY backend/src ./backend/src
COPY frontend/src ./frontend/src
COPY frontend/public ./frontend/public
COPY frontend/assets ./frontend/assets

# Install dependencies
RUN bun install --cwd backend
RUN bun install --cwd frontend

# Build frontend and copy to backend public
RUN bun --cwd frontend build
RUN mkdir -p backend/public
RUN cp -a frontend/dist/. backend/public/

# Validate and build backend
RUN bun --cwd backend typecheck
RUN bun --cwd backend build

FROM oven/bun:latest AS runner
WORKDIR /app

# Copy only necessary files from builder
COPY --from=builder /app/backend/dist ./backend/dist
COPY --from=builder /app/backend/src ./backend/src
COPY --from=builder /app/backend/package.json ./backend/package.json
COPY --from=builder /app/backend/bunfig.toml ./backend/bunfig.toml
COPY --from=builder /app/backend/public ./backend/public
COPY --from=builder /app/backend/drizzle ./backend/drizzle

# Install only production dependencies
RUN cd backend && bun install --production

ENV NODE_ENV=production
ENV BUN_ENV=production
EXPOSE 9999

CMD ["bun", "--cwd", "backend", "start"]
```

**Add .dockerignore:**
```
.git
.github
.env*
node_modules
*.log
.DS_Store
frontend/node_modules
backend/dist
backend/node_modules
```

---

### Fix 8: Add Health Check Endpoints

**File:** `backend/src/index.ts` or create `backend/src/modules/health/health.router.ts`

**Add at app initialization (in app.ts before other routes):**
```typescript
import { createRouter } from '#/lib/create-router'

const health = createRouter()
    .get('/health', (c) => {
        return c.json({ status: 'ok', timestamp: new Date().toISOString() })
    })
    .get('/ready', async (c) => {
        try {
            // Quick database check
            await db.query.users.findFirst({ limit: 1 })
            return c.json({ 
                status: 'ready',
                database: 'connected',
                timestamp: new Date().toISOString()
            })
        } catch (error) {
            return c.json(
                { 
                    status: 'not-ready',
                    error: 'Database connection failed',
                    timestamp: new Date().toISOString()
                },
                503
            )
        }
    })

app.route('/api/', health)
```

---

### Fix 9: Add Graceful Shutdown Handler

**File:** `backend/src/index.ts`

**Add before the final exports:**
```typescript
// Graceful shutdown
process.on('SIGTERM', async () => {
    logger.info({ msg: 'SIGTERM received, shutting down gracefully...' })
    server.stop()
    // Give connections time to close
    await new Promise(resolve => setTimeout(resolve, 5000))
    process.exit(0)
})

process.on('SIGINT', async () => {
    logger.info({ msg: 'SIGINT received, shutting down gracefully...' })
    server.stop()
    await new Promise(resolve => setTimeout(resolve, 5000))
    process.exit(0)
})
```

---

### Fix 10: Verify Secure Cookie Flags

**File:** `backend/src/modules/auth/auth.controller.ts`

**Find all `setCookie` calls and ensure they look like:**
```typescript
setCookie(c, 'refresh_token', refreshToken, {
    httpOnly: true,
    secure: env.NODE_ENV === 'production',
    sameSite: 'None', // Required for cross-site requests
    maxAge: REFRESH_TOKEN_EXPIRES_IN_SECONDS,
    path: '/',
    domain: resolveCookieDomain(c.req.header('host')),
})
```

---

## PHASE 3: MEDIUM PRIORITY FIXES

### Fix 11: Add Rate Limiting

**Step 1:** Install package
```bash
bun add hono-rate-limiter
```

**Step 2:** Add to app.ts:
```typescript
import { rateLimiter } from 'hono-rate-limiter'

// Rate limiting
const limiter = rateLimiter({
    windowMs: 15 * 60 * 1000, // 15 minutes
    limit: 100, // Default 100 requests per window
})

// Apply to auth routes (stricter)
const authLimiter = rateLimiter({
    windowMs: 60 * 1000, // 1 minute
    limit: 5,
    keyGenerator: (c) => c.req.header('x-forwarded-for') || 'unknown',
})

app.use('/api/auth/*', authLimiter)
app.use('/api/*', limiter)
```

---

## ENVIRONMENT VARIABLES CHECKLIST

Create `.env.prod` with these values:

```bash
# Runtime
NODE_ENV=production
PORT=9999
LOG_LEVEL=info

# Database
DATABASE_URL=postgres://user:password@prod-host:5432/dbname
DATABASE_AUTH_TOKEN=<if-using-turso>

# Security
ACCESS_TOKEN_SECRET=<generate-with: openssl rand -base64 32>
COOKIE_DOMAIN=.mmcrt.com
JWT_ISSUER=api.mmcrt.com

# CORS
CORS_ALLOWED_ORIGINS=https://app.mmcrt.com,https://api.mmcrt.com,https://slots.mmcrt.com

# R2/CloudflareStorage
R2_PUBLIC_URL=https://bucket.r2.cloudflarestorage.com
R2_BUCKET_NAME=your-bucket
RCLONE_R2_REMOTE=r2:your-bucket

# Optional: Monitoring
SENTRY_DSN=<sentry-dsn-if-using>
```

---

## DEPLOYMENT CHECKLIST

Before deploying:

```bash
# 1. Update environment variables
cp .env.prod.example .env.prod
# Edit .env.prod with real values

# 2. Build locally to test
bash ./scripts/production-build.sh

# 3. Run type checks
bun run typecheck:all

# 4. Build Docker image
docker build -t backend:latest .

# 5. Test Docker image
docker run --env-file .env.prod -p 9999:9999 backend:latest

# 6. Verify health check responds
curl http://localhost:9999/api/health

# 7. Push to registry
docker tag backend:latest registry/backend:latest
docker push registry/backend:latest

# 8. Run migrations in production
# (after deployment starts the container)
bun --cwd backend migrate
```

---

## VALIDATION AFTER DEPLOYMENT

```bash
# 1. Health check
curl https://api.mmcrt.com/api/health

# 2. Readiness check
curl https://api.mmcrt.com/api/ready

# 3. CORS check
curl -H "Origin: https://app.mmcrt.com" https://api.mmcrt.com/api/health -v

# 4. Database connection
curl https://api.mmcrt.com/api/users (should work if authenticated)

# 5. Check logs
docker logs <container-id>  # or journalctl -u backend
```

---

## ESTIMATED TIME TO COMPLETE

- Phase 1 (Critical): **1-2 hours**
- Phase 2 (High): **1 hour**
- Phase 3 (Medium): **30 minutes**
- **Total: ~3 hours to full production readiness**
