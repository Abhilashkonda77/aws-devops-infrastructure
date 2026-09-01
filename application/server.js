'use strict';

/**
 * Minimal production-style HTTP service.
 *
 * Endpoints:
 *   GET /health   -> liveness/readiness probe used by ALB target group
 *   GET /         -> simple application endpoint
 *
 * Configuration is read entirely from environment variables (12-factor style).
 * Database connectivity is optional: if DB_HOST is not set, the app still
 * starts and serves traffic, but /health reports db status as "skipped".
 */

const express = require('express');
const { Pool } = require('pg');

const PORT = parseInt(process.env.PORT || '3000', 10);
const APP_ENV = process.env.APP_ENV || 'development';
const APP_VERSION = process.env.APP_VERSION || 'local';

const DB_HOST = process.env.DB_HOST;
const DB_PORT = parseInt(process.env.DB_PORT || '5432', 10);
const DB_NAME = process.env.DB_NAME || 'appdb';
const DB_USER = process.env.DB_USER || 'appuser';
const DB_PASSWORD = process.env.DB_PASSWORD || '';
const DB_SSL = (process.env.DB_SSL || 'true').toLowerCase() === 'true';

function log(level, message, extra = {}) {
  // Structured JSON logs -> straightforward to query in CloudWatch Logs Insights.
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    message,
    app_env: APP_ENV,
    app_version: APP_VERSION,
    ...extra,
  };
  console.log(JSON.stringify(entry));
}

let pool = null;
if (DB_HOST) {
  pool = new Pool({
    host: DB_HOST,
    port: DB_PORT,
    database: DB_NAME,
    user: DB_USER,
    password: DB_PASSWORD,
    ssl: DB_SSL ? { rejectUnauthorized: false } : false,
    max: 5,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
  });

  pool.on('error', (err) => {
    log('error', 'Unexpected error on idle PostgreSQL client', { error: err.message });
  });
}

const app = express();
app.disable('x-powered-by');

app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    log('info', 'request_completed', {
      method: req.method,
      path: req.path,
      status_code: res.statusCode,
      duration_ms: Date.now() - start,
    });
  });
  next();
});

app.get('/health', async (req, res) => {
  const health = {
    status: 'ok',
    app_version: APP_VERSION,
    app_env: APP_ENV,
    uptime_seconds: Math.round(process.uptime()),
    database: 'skipped',
  };

  if (pool) {
    try {
      await pool.query('SELECT 1');
      health.database = 'ok';
    } catch (err) {
      health.database = 'error';
      health.status = 'degraded';
      log('warn', 'health_check_db_failed', { error: err.message });
      return res.status(503).json(health);
    }
  }

  res.status(200).json(health);
});

app.get('/', (req, res) => {
  res.status(200).json({
    message: 'Hello from the DevOps reference application',
    app_env: APP_ENV,
    app_version: APP_VERSION,
    hostname: process.env.HOSTNAME || 'unknown',
  });
});

app.use((req, res) => {
  res.status(404).json({ error: 'not_found', path: req.path });
});

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  log('error', 'unhandled_error', { error: err.message, stack: err.stack });
  res.status(500).json({ error: 'internal_server_error' });
});

const server = app.listen(PORT, () => {
  log('info', 'server_started', { port: PORT });
});

// Graceful shutdown: stop accepting new connections, finish in-flight
// requests, close the DB pool, then exit. ECS sends SIGTERM on task stop.
async function shutdown(signal) {
  log('info', 'shutdown_initiated', { signal });

  const forceExitTimer = setTimeout(() => {
    log('error', 'shutdown_forced_timeout');
    process.exit(1);
  }, 10000);

  server.close(async (err) => {
    if (err) {
      log('error', 'server_close_error', { error: err.message });
    }
    if (pool) {
      try {
        await pool.end();
        log('info', 'db_pool_closed');
      } catch (e) {
        log('error', 'db_pool_close_error', { error: e.message });
      }
    }
    clearTimeout(forceExitTimer);
    log('info', 'shutdown_complete');
    process.exit(err ? 1 : 0);
  });
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

module.exports = app;
