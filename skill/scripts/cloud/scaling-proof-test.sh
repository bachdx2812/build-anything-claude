#!/usr/bin/env bash
# scaling-proof-test.sh — GATE-28 (v8.1).
# k6 ramp 1x → Nx, asserts p95 stays under budget. Without this, "scales horizontally" is opinion.
# Contract: 0 = p95 ≤ budget at peak; 1 = budget breach; N/A if no scaling config or no k6.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step scaling "starting"

SC_JSON=$(cfg "cloud.scaling" "{}")
if [[ "$SC_JSON" == "{}" || "$SC_JSON" == "null" ]]; then
  log_step scaling "no scaling configured — N/A_PENDING_REVIEWER"
  emit_na_pending "GATE-28" "scaling-proof.json" "no cloud.scaling configured; reviewer must set target_url / ramp / p95_budget_ms OR mark atom as single-instance"
  exit 0
fi

require_tool_or_na "k6" "GATE-28" "scaling-proof.json"

URL=$(echo "$SC_JSON" | jq -r '.target_url // empty')
START_VU=$(echo "$SC_JSON" | jq -r '.start_vu // 1')
PEAK_VU=$(echo "$SC_JSON" | jq -r '.peak_vu // 10')
RAMP_S=$(echo "$SC_JSON" | jq -r '.ramp_seconds // 30')
HOLD_S=$(echo "$SC_JSON" | jq -r '.hold_seconds // 30')
P95_BUDGET_MS=$(echo "$SC_JSON" | jq -r '.p95_budget_ms // 500')
[[ -z "$URL" ]] && { emit_na_pending "GATE-28" "scaling-proof.json" "scaling.target_url missing"; exit 0; }

SCRIPT_K6=$(mktemp -t k6-XXXXXX.js)
cat > "$SCRIPT_K6" <<EOF
import http from 'k6/http';
import { check } from 'k6';
export const options = {
  stages: [
    { duration: '${RAMP_S}s', target: ${PEAK_VU} },
    { duration: '${HOLD_S}s', target: ${PEAK_VU} },
  ],
  startVUs: ${START_VU},
  thresholds: {
    'http_req_duration{expected_response:true}': ['p(95)<${P95_BUDGET_MS}'],
    'http_req_failed': ['rate<0.01'],
  },
};
export default function () {
  const r = http.get('${URL}');
  check(r, { 'status 2xx': (res) => res.status >= 200 && res.status < 300 });
}
EOF

RESULTS_JSON=$(mktemp -t k6-out-XXXXXX.json)
log_step scaling "k6 ramp ${START_VU}→${PEAK_VU} VU, p95 budget ${P95_BUDGET_MS}ms"
set +e
k6 run --summary-export "$RESULTS_JSON" --quiet "$SCRIPT_K6" >/dev/null 2>&1
K6_EXIT=$?
set -e

if [[ ! -s "$RESULTS_JSON" ]]; then
  emit_evidence "GATE-28" false "scaling-proof.json" "{\"error\":\"k6 produced no summary\",\"k6_exit\":$K6_EXIT}"
  rm -f "$SCRIPT_K6" "$RESULTS_JSON"
  log_step scaling "FAIL k6 ran but no summary"; exit 1
fi

P95=$(jq -r '.metrics.http_req_duration["p(95)"] // .metrics.http_req_duration.values["p(95)"] // 0' "$RESULTS_JSON")
FAIL_RATE=$(jq -r '.metrics.http_req_failed.rate // .metrics.http_req_failed.values.rate // 0' "$RESULTS_JSON")
RPS=$(jq -r '.metrics.http_reqs.rate // .metrics.http_reqs.values.rate // 0' "$RESULTS_JSON")
REQS=$(jq -r '.metrics.http_reqs.count // .metrics.http_reqs.values.count // 0' "$RESULTS_JSON")
rm -f "$SCRIPT_K6" "$RESULTS_JSON"

P95_OK=$(awk -v p="$P95" -v b="$P95_BUDGET_MS" 'BEGIN{exit !(p<=b)}' && echo true || echo false)
ERR_OK=$(awk -v r="$FAIL_RATE" 'BEGIN{exit !(r<0.01)}' && echo true || echo false)
PASSED=true
[[ "$P95_OK" != "true" || "$ERR_OK" != "true" || "$K6_EXIT" -ne 0 ]] && PASSED=false

emit_evidence "GATE-28" "$PASSED" "scaling-proof.json" \
  "{\"target_url\":\"$URL\",\"start_vu\":$START_VU,\"peak_vu\":$PEAK_VU,\"p95_ms\":$P95,\"p95_budget_ms\":$P95_BUDGET_MS,\"fail_rate\":$FAIL_RATE,\"rps\":$RPS,\"total_reqs\":$REQS,\"k6_exit\":$K6_EXIT}"

if [[ "$PASSED" == "true" ]]; then log_step scaling "PASS p95=${P95}ms / ${P95_BUDGET_MS}ms err=${FAIL_RATE}"; exit 0
else log_step scaling "FAIL p95=${P95}ms / budget ${P95_BUDGET_MS}ms err=${FAIL_RATE} (k6_exit=$K6_EXIT)"; exit 1
fi
