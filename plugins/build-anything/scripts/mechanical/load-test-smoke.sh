#!/usr/bin/env bash
# load-test-smoke.sh — GATE-14 (BE) p95 latency smoke. k6-based.
# Single-number contract: p95 ms.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step load "starting"

THRESH_MS=$(threshold "gates.performance.p95_max_ms" 200)
OUT="$ATOM_DIR/gate-mechanical/load.json"

# read endpoints from .build-anything.json#load_smoke.endpoints
# endpoints may be strings ("/api/orders") OR objects { method, path, body, headers }
ENDPOINTS_JSON=$( jq -c '.load_smoke.endpoints // []' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo "[]" )
TARGET=$(jq -r '.load_smoke.target_url // empty' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo "")
EP_COUNT=$(jq 'length' <<< "$ENDPOINTS_JSON")

if [[ "$EP_COUNT" -eq 0 || -z "$TARGET" ]]; then
  log_step load "no load_smoke config — N/A_PENDING_REVIEWER (F6: no vacuous PASS)"
  emit_na_pending "GATE-14-load" "$OUT" "no load_smoke.endpoints/target_url configured; reviewer must add OR confirm atom has no HTTP perf budget"
  exit 0
fi

require_cmd k6 "install: brew install k6"

# generate k6 script inline; supports GET strings + object form { method, path, body, headers }
K6_SCRIPT="$(mktemp /tmp/k6-XXXXXX.js)"
trap 'rm -f "$K6_SCRIPT"' EXIT
VUS=$(jq -r '.load_smoke.vus // 10' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo 10)
DURATION=$(jq -r '.load_smoke.duration // "15s"' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo "15s")
cat > "$K6_SCRIPT" <<JS
import http from 'k6/http';
import { check } from 'k6';
export const options = { vus: ${VUS}, duration: '${DURATION}', thresholds: { http_req_duration: ['p(95)<${THRESH_MS}'] } };
const TARGET = '${TARGET}';
const ENDPOINTS = ${ENDPOINTS_JSON};
export default function () {
  ENDPOINTS.forEach((raw) => {
    const ep = (typeof raw === 'string') ? { method: 'GET', path: raw } : raw;
    const url = \`\${TARGET}\${ep.path}\`;
    const method = (ep.method || 'GET').toUpperCase();
    const headers = ep.headers || {};
    const body = ep.body ? (typeof ep.body === 'string' ? ep.body : JSON.stringify(ep.body)) : null;
    if (body && !headers['Content-Type']) headers['Content-Type'] = 'application/json';
    const params = { headers, tags: { name: ep.path } };
    const r = (method === 'GET' || method === 'HEAD')
      ? http.request(method, url, null, params)
      : http.request(method, url, body, params);
    check(r, { 'status<500': (res) => res.status < 500 });
  });
}
JS

# run, capture summary JSON
SUMMARY="$(mktemp /tmp/k6-summary-XXXXXX.json)"
trap 'rm -f "$SUMMARY"' EXIT
k6 run --quiet --summary-export="$SUMMARY" "$K6_SCRIPT" || true

P95=$(jq -r '.metrics.http_req_duration["p(95)"] // 0' "$SUMMARY")
P50=$(jq -r '.metrics.http_req_duration["p(50)"] // 0' "$SUMMARY")
ERR_RATE=$(jq -r '.metrics.http_req_failed.rate // 0' "$SUMMARY")

P95_INT=$(printf "%.0f" "$P95")
PASSED=$(awk -v s="$P95_INT" -v t="$THRESH_MS" 'BEGIN{print (s<=t)?"true":"false"}')

# v8.3 — endpoints_tested is the load equivalent of scope_files: prevents
# "p95=180ms" headline from masking that only 1 of 8 declared endpoints was hit.
emit_json "GATE-14-load" "$P95_INT" "$THRESH_MS" "$PASSED" "$OUT" \
  "{\"p50_ms\":$(printf '%.0f' "$P50"),\"err_rate\":$ERR_RATE,\"endpoints_tested\":$EP_COUNT}"

if [[ "$PASSED" == "true" ]]; then
  log_step load "PASS p95=${P95_INT}ms (≤${THRESH_MS}ms)"
  exit 0
else
  log_step load "FAIL p95=${P95_INT}ms exceeds ${THRESH_MS}ms"
  exit 1
fi
