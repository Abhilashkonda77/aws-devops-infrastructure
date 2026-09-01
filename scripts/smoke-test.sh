#!/usr/bin/env bash
#
# Smoke test: hits /health and / on a deployed environment and fails the
# build if either check does not pass. Used by CI after every deploy; can
# also be run manually.
#
# Usage:
#   ./scripts/smoke-test.sh http://<alb-dns-name>
#   ./scripts/smoke-test.sh http://<alb-dns-name> 10   # 10 retries instead of default

set -euo pipefail

BASE_URL="${1:-}"
MAX_RETRIES="${2:-15}"
SLEEP_SECONDS=10

if [ -z "$BASE_URL" ]; then
  echo "Usage: $0 <base-url> [max-retries]"
  exit 1
fi

echo "==> Smoke testing $BASE_URL"

check() {
  local path="$1"
  local expected_status="$2"
  local attempt=1

  while [ "$attempt" -le "$MAX_RETRIES" ]; do
    status=$(curl -s -o /tmp/smoke_body.txt -w '%{http_code}' "$BASE_URL$path" || echo "000")

    if [ "$status" == "$expected_status" ]; then
      echo "PASS: GET $path -> $status"
      return 0
    fi

    echo "  attempt $attempt/$MAX_RETRIES: GET $path -> $status (want $expected_status), retrying in ${SLEEP_SECONDS}s..."
    attempt=$((attempt + 1))
    sleep "$SLEEP_SECONDS"
  done

  echo "FAIL: GET $path did not return $expected_status after $MAX_RETRIES attempts"
  echo "Last response body:"
  cat /tmp/smoke_body.txt || true
  return 1
}

check "/health" "200"
check "/" "200"

echo "==> Smoke test passed."
