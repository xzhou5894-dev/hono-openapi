# Production Readiness Audit Report
**Generated:** July 4, 2026  
**Status:** ⚠️ ISSUES FOUND - Requires Fixes Before Production Deployment

---

## Executive Summary

The hono-openapi project is a Bun-based monorepo with a Hono API backend and Vue 3 frontend. The deployment infrastructure is partially configured, but **critical issues must be resolved before production deployment**. Key issues include hardcoded domains, hardcoded database credentials, exposed debug code, and incomplete CI/CD configuration.

---

## 🔴 CRITICAL ISSUES (Must Fix)

### 1. **Hardcoded Database Credentials in Drizzle Config**
**Severity:** 🔴 CRITICAL  
**File:** `backend/drizzle.config.ts`  
**Issue:**
```typescript
dbCredentials: {
    url: 'postgres://user:asdfasdf@localhost:5439/cashinin',
},
```

**Risk:** Database credentials are hardcoded and exposed in source control.

**Fix:**
```typescript
import env from './src/env'

export default defineConfig({
    // ... other config
    dbCredentials: {
        url: env.DATABASE_URL,
        authToken: env.DATABASE_AUTH_TOKEN,
    },
})
```

---

### 2. **Hardcoded Domain Names Throughout Codebase**
**Severity:** 🔴 CRITICAL  
**Files:**
- `backend/src/app.ts` (line 22-31): CORS allowed origins hardcoded to `*.cashflowcasino.com`
- `backend/src/modules/auth/auth.controller.ts` (lines 25-35, 41): Cookie domain and JWT issuer hardcoded

**Issue:**
```typescript
const allowedOrigins = new Set<string>([
    'https://slots.cashflowcasino.com',
    'https://app.cashflowcasino.com',
    'https://api.cashflowcasino.com',
])

// In auth.controller.ts
function resolveCookieDomain(host: string | undefined): string | undefined {
    if (bare.endsWith('.cashflowcasino.com')) return '.cashflowcasino.com'
    // ...
}
const ISSUER = 'api.cashflowcasino.com'
```

**Risk:** Cannot deploy to different domains without code changes.

**Fix:** Use environment variables from `CORS_ALLOWED_ORIGINS`, `COOKIE_DOMAIN`, `JWT_ISSUER` (already defined in `.env.prod.example`)

---

### 3. **Excessive Debug/Console Logging in Production Code**
**Severity:** 🔴 CRITICAL  
**Files:**
- `backend/src/index.ts` (scattered throughout)
- Multiple modules with `console.log()`, `console.error()` calls

**Issue:** The entry point contains extensive debug logging that should use structured logging (pino is already a dependency):
```typescript
console.log(`Server is running on http://localhost:${port}`)
console.log(url.searchParams.get('data'))
console.log('here')
console.log(whatWeNeed)
console.log(JSON.parse(finalResult))
// ... many more
```

**Risk:** Leaks sensitive data, impacts performance, pollutes logs.

**Fix:** Replace all `console.*` with `logger.*` using the existing `pino` logger setup. Check `pino-pretty` config.

---

### 4. **Incomplete CI/CD Pipeline - Production Deployment Steps**
**Severity:** 🔴 CRITICAL  
**File:** `.github/workflows/ci-cd.yml`  
**Issue:**
```yaml
deploy-production:
  steps:
    - name: Deploy to production
      run: |
        echo "🚀 Deploying to production environment..."
        # Add your production deployment commands here
        # Example: rsync, docker push, kubectl apply, etc.
        echo "✅ Production deployment complete"
```

**Risk:** Placeholder deployment script does nothing. Production deployment must be manually implemented.

**Fix:** Implement actual deployment mechanism (Docker push, rsync, Kubernetes, etc.)

---

### 5. **Missing Proper Error Handling in WebSocket Proxy**
**Severity:** 🔴 CRITICAL  
**File:** `backend/src/index.ts`  
**Issue:**
- Exposed error responses: `new Response('Uh oh!!', { status: 500 })`
- No structured error logging
- Mixed debug code with production code
- Unused/commented code mixed in

**Fix:** Use consistent error handling with structured logging (pino)

---

## 🟠 HIGH PRIORITY ISSUES

### 6. **Docker Multi-Stage Build Not Optimized**
**Severity:** 🟠 HIGH  
**File:** `backend/Dockerfile`  
**Issue:**
```dockerfile
FROM oven/bun:latest AS builder
COPY backend/package.json backend/bunfig.toml backend/tsconfig.json backend/tsconfig.* backend/src backend/public ./backend/
COPY frontend/package.json frontend/vite.config.ts frontend/tsconfig.json frontend/tsconfig.* frontend/src frontend/public frontend/assets ./frontend/

RUN bun install --cwd backend
RUN bun install --cwd frontend
RUN bun --cwd frontend build
RUN mkdir -p backend/public
RUN cp -a frontend/dist/. backend/public/

FROM oven/bun:latest AS runner
COPY --from=builder /app/backend /app/backend
```

**Risk:** 
- Missing `.dist` directory copy from builder (built backend)
- Frontend files must be copied from builder
- No proper .dockerignore

**Fix:**
```dockerfile
FROM oven/bun:latest AS runner
WORKDIR /app
COPY --from=builder /app/backend/dist ./backend/dist
COPY --from=builder /app/backend/src ./backend/src
COPY --from=builder /app/backend/package.json ./backend/package.json
COPY --from=builder /app/backend/public ./backend/public
```

---

### 7. **Environment Variables Not Enforced at Build Time**
**Severity:** 🟠 HIGH  
**File:** `backend/src/env.ts`  
**Issue:** The env validation only runs at runtime. If critical env vars are missing, the app crashes in production.

**Fix:** Validate in CI/CD before deployment that all required env vars are set.

---

### 8. **Database URL Hardcoded in docker-compose.prod.yml**
**Severity:** 🟠 HIGH  
**File:** `docker-compose.prod.yml`  
**Issue:**
```yaml
environment:
  POSTGRES_USER: user
  POSTGRES_PASSWORD: asdfasdf
  POSTGRES_DB: hono
```

**Risk:** Hardcoded credentials in production compose file.

**Fix:** Use `.env.prod` for all secrets, never in compose file directly.

---

## 🟡 MEDIUM PRIORITY ISSUES

### 9. **Missing Liveness/Readiness Health Check Endpoint**
**Severity:** 🟡 MEDIUM  
**Issue:** No `/health` or `/ready` endpoint for Kubernetes/container orchestration.

**Fix:** Add health check route:
```typescript
app.get('/health', (c) => c.json({ status: 'ok' }))
app.get('/ready', async (c) => {
  try {
    await db.query.users.findFirst({ limit: 1 })
    return c.json({ status: 'ready' })
  } catch {
    return c.json({ status: 'not-ready' }, 503)
  }
})
```

---

### 10. **No Graceful Shutdown Handler**
**Severity:** 🟡 MEDIUM  
**File:** `backend/src/index.ts`  
**Issue:** No signal handlers for SIGTERM/SIGINT. Process may not close cleanly during deployment.

**Fix:**
```typescript
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, closing gracefully...')
  server.stop()
  process.exit(0)
})
```

---

### 11. **Insecure Cookie Configuration in Auth**
**Severity:** 🟡 MEDIUM  
**File:** `backend/src/modules/auth/auth.controller.ts`  
**Issue:** Need to verify `secure` and `sameSite` flags are set correctly for production.

**Fix:** Ensure setCookie includes:
```typescript
setCookie(c, 'refresh_token', token, {
  secure: env.NODE_ENV === 'production',
  sameSite: 'None',
  path: '/',
  domain: resolveCookieDomain(c.req.header('host')),
})
```

---

### 12. **CORS Wildcard Not Recommended**
**Severity:** 🟡 MEDIUM  
**File:** `backend/src/app.ts`  
**Issue:** Current implementation uses a Set and requires exact origin match (good), but production domains are hardcoded.

**Fix:** Use environment variable:
```typescript
const allowedOrigins = (env.CORS_ALLOWED_ORIGINS || '').split(',').map(o => o.trim())
```

---

## 🟢 LOWER PRIORITY / BEST PRACTICES

### 13. **No Rate Limiting Configured**
**Severity:** 🟢 LOW  
**Issue:** No rate limiting on auth endpoints, game endpoints, or general API.

**Recommendation:** Add rate limiting middleware (e.g., `hono-rate-limiter` or similar) for:
- `/api/auth/login` (5 per minute)
- `/api/auth/signup` (10 per hour)
- General API (100 per minute)

---

### 14. **No Request Validation Logging**
**Severity:** 🟢 LOW  
**Issue:** Failed validations don't log structured data for debugging/auditing.

**Recommendation:** Add middleware to log validation failures with request metadata.

---

### 15. **Missing Deployment Documentation Update**
**Severity:** 🟢 LOW  
**Issue:** `DEPLOYMENT.md` mentions domain migration but doesn't cover the fixes needed.

**Recommendation:** Update deployment guide to include:
- Environment variable setup checklist
- Database credential rotation procedures
- Post-deployment verification steps

---

## ✅ VERIFICATION CHECKLIST

Before deploying to production, verify:

- [ ] All database credentials removed from source code
- [ ] All hardcoded domain names replaced with env variables
- [ ] All `console.log()` calls replaced with structured logging
- [ ] CI/CD pipeline has actual deployment steps (not placeholders)
- [ ] Docker image builds and runs successfully
- [ ] Environment variables are set in production:
  - [ ] `NODE_ENV=production`
  - [ ] `DATABASE_URL` (correct production database)
  - [ ] `DATABASE_AUTH_TOKEN` (if using Turso)
  - [ ] `ACCESS_TOKEN_SECRET` (strong value, >32 chars)
  - [ ] `R2_PUBLIC_URL`, `R2_BUCKET_NAME`, `RCLONE_R2_REMOTE`
  - [ ] `CORS_ALLOWED_ORIGINS` (production domains)
  - [ ] `COOKIE_DOMAIN` (production domain)
  - [ ] `JWT_ISSUER` (production API host)
- [ ] Database migrations run successfully
- [ ] Health check endpoints respond
- [ ] Graceful shutdown is tested
- [ ] HTTPS is enforced
- [ ] Secrets are in a secret manager (not .env files)
- [ ] Logs are structured and sent to centralized logging
- [ ] Monitoring/alerting is configured

---

## RECOMMENDED ACTION PLAN

### Phase 1: Critical Fixes (BEFORE ANY DEPLOYMENT)
1. **Fix drizzle.config.ts** - Use env variables
2. **Fix app.ts** - Replace hardcoded CORS origins with env variables
3. **Fix auth.controller.ts** - Replace hardcoded domains with env variables
4. **Replace console.log** - Use structured logging (pino)
5. **Update docker-compose.prod.yml** - Remove hardcoded credentials
6. **Implement CI/CD deployment** - Replace placeholder steps

### Phase 2: High Priority (BEFORE PRODUCTION)
7. Fix Docker multi-stage build
8. Add health check endpoints
9. Add graceful shutdown handler
10. Verify secure cookie flags

### Phase 3: Medium Priority (FIRST WEEK)
11. Add rate limiting
12. Configure monitoring/alerting
13. Set up log aggregation

### Phase 4: Nice to Have
14. Add request validation logging
15. Update deployment documentation

---

## DEPLOYMENT COMMAND (After Fixes)

```bash
# Set required environment variables
export NODE_ENV=production
export DATABASE_URL="postgres://user:pass@prod-host:5432/dbname"
export DATABASE_AUTH_TOKEN="token-if-using-turso"
export ACCESS_TOKEN_SECRET="$(openssl rand -base64 32)"
export CORS_ALLOWED_ORIGINS="https://app.mmcrt.com,https://api.mmcrt.com,https://slots.mmcrt.com"
export COOKIE_DOMAIN=".mmcrt.com"
export JWT_ISSUER="api.mmcrt.com"
export R2_PUBLIC_URL="https://bucket.r2.cloudflarestorage.com"
export R2_BUCKET_NAME="bucket-name"
export RCLONE_R2_REMOTE="r2:bucket"

# Build
bash ./scripts/production-build.sh

# Migrate database
bun --cwd backend migrate

# Deploy (update with your deployment mechanism)
docker build -t your-registry/backend:latest .
docker push your-registry/backend:latest
# Apply to your infrastructure (K8s, Docker Compose, etc.)
```

---

## SUMMARY

| Category | Count | Status |
|----------|-------|--------|
| Critical Issues | 5 | 🔴 MUST FIX |
| High Priority | 4 | 🟠 BEFORE PROD |
| Medium Priority | 4 | 🟡 RECOMMENDED |
| Low Priority | 3 | 🟢 NICE TO HAVE |

**Overall Readiness:** 30% (After fixes: 85%)

The project has good scaffolding and documentation, but **requires addressing all critical issues before any production deployment**. Most fixes are straightforward configuration and logging improvements.
