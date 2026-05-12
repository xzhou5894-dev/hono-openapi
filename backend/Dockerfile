FROM oven/bun:latest AS builder
WORKDIR /app

# Copy backend and frontend manifests and source code
COPY backend/package.json backend/bunfig.toml backend/tsconfig.json backend/tsconfig.* backend/src backend/public ./backend/
COPY frontend/package.json frontend/vite.config.ts frontend/tsconfig.json frontend/tsconfig.* frontend/src frontend/public frontend/assets ./frontend/

# Install dependencies for both packages
RUN bun install --cwd backend
RUN bun install --cwd frontend

# Build frontend and inject output into backend static folder
RUN bun --cwd frontend build
RUN mkdir -p backend/public
RUN cp -a frontend/dist/. backend/public/

# Validate backend build
RUN bun --cwd backend typecheck
RUN bun --cwd backend build

FROM oven/bun:latest AS runner
WORKDIR /app
COPY --from=builder /app/backend /app/backend

ENV NODE_ENV=production
ENV BUN_ENV=production
EXPOSE 9999

CMD ["bun", "--cwd", "backend", "start"]
