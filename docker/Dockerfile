# syntax=docker/dockerfile:1

# ---- Build stage: install dependencies with dev deps excluded ----
FROM node:20-alpine AS deps
WORKDIR /app
COPY application/package.json application/package-lock.json* ./
RUN npm install --omit=dev --no-audit --no-fund

# ---- Runtime stage ----
FROM node:20-alpine AS runtime

# Small, well-maintained base image. Alpine keeps the final image small.
RUN apk add --no-cache curl

# Create a dedicated non-root user/group instead of running as root or
# relying on the default "node" user's UID matching host expectations.
RUN addgroup -S appgroup -g 1001 && adduser -S appuser -u 1001 -G appgroup

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY application/package.json ./package.json
COPY application/server.js ./server.js

ENV NODE_ENV=production \
    PORT=3000

EXPOSE 3000

# Container-level health check (in addition to the ALB target group health
# check) so `docker ps` / ECS container health also reflects app health.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://127.0.0.1:${PORT}/health || exit 1

USER appuser

# Use the "node" binary directly (not npm) as PID 1 so SIGTERM propagates
# correctly for graceful shutdown, instead of being swallowed by npm.
CMD ["node", "server.js"]
