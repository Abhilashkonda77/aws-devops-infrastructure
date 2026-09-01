'use strict';

/**
 * Minimal dependency-free test runner.
 * Kept intentionally simple: application logic is not the focus of this
 * project, CI just needs a real, meaningful pass/fail signal.
 */

const http = require('http');
const app = require('./server');

let failures = 0;

function assert(condition, message) {
  if (!condition) {
    failures += 1;
    console.error(`FAIL: ${message}`);
  } else {
    console.log(`PASS: ${message}`);
  }
}

function get(path) {
  return new Promise((resolve, reject) => {
    const req = http.get(`http://127.0.0.1:${process.env.PORT || 3000}${path}`, (res) => {
      let body = '';
      res.on('data', (chunk) => (body += chunk));
      res.on('end', () => resolve({ statusCode: res.statusCode, body }));
    });
    req.on('error', reject);
  });
}

async function run() {
  // Give the server a tick to start listening.
  await new Promise((r) => setTimeout(r, 300));

  const health = await get('/health');
  assert(health.statusCode === 200, '/health returns 200');
  assert(JSON.parse(health.body).status === 'ok', '/health status is ok');

  const root = await get('/');
  assert(root.statusCode === 200, '/ returns 200');

  const notFound = await get('/does-not-exist');
  assert(notFound.statusCode === 404, 'unknown route returns 404');

  process.exit(failures > 0 ? 1 : 0);
}

run().catch((err) => {
  console.error('Test run crashed:', err);
  process.exit(1);
});
