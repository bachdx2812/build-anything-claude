#!/usr/bin/env bash
# api-contract-test.sh — GATE-19.
# Drives Schemathesis against the project's OpenAPI spec and reports passing/failing endpoints.
# Falls back to Dredd if schemathesis not installed.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step api-contract "starting"

OPENAPI=$(cfg "backend.openapi_path" "openapi.yaml")
BASE=$(cfg "backend.api_base_url" "http://localhost:3000")
JWT_FIXTURE=$(cfg "backend.contract.jwt_fixture" "tenant_a")

SPEC_PATH="$PROJECT_ROOT/$OPENAPI"
if [[ ! -f "$SPEC_PATH" ]]; then
  log_step api-contract "no OpenAPI at $SPEC_PATH — N/A_PENDING_REVIEWER (F6 fix)"
  emit_na_pending "GATE-19" "api-contract.json" "no OpenAPI spec at $OPENAPI; reviewer must verify atom has no HTTP API surface OR add spec"
  exit 0
fi

JWT="${JWT_FIXTURE:+$(fixture_jwt "$JWT_FIXTURE")}"
REPORT_DIR="$EVIDENCE_DIR"
mkdir -p "$REPORT_DIR"

if command -v schemathesis >/dev/null 2>&1; then
  log_step api-contract "running schemathesis"
  AUTH_HDR=""
  [[ -n "$JWT" ]] && AUTH_HDR="-H Authorization:Bearer\ $JWT"
  set +e
  schemathesis run "$SPEC_PATH" \
    --base-url "$BASE" $AUTH_HDR \
    --hypothesis-max-examples 30 \
    --checks all \
    --junit-xml "$REPORT_DIR/schemathesis-junit.xml" \
    --report "$REPORT_DIR/schemathesis-report" >/dev/null
  RC=$?
  set -e

  FAILED=$(jq -r '.testsuite[].testcase | map(select(.failure)) | length' "$REPORT_DIR/schemathesis-junit.xml" 2>/dev/null || echo 0)
  TOTAL=$(jq -r '.testsuite[].testcase | length' "$REPORT_DIR/schemathesis-junit.xml" 2>/dev/null || echo 0)
  [[ -z "$FAILED" ]] && FAILED=$RC
elif command -v dredd >/dev/null 2>&1; then
  log_step api-contract "schemathesis not found, falling back to dredd"
  set +e
  dredd "$SPEC_PATH" "$BASE" \
    --reporter json --output "$REPORT_DIR/dredd.json" >/dev/null
  RC=$?
  set -e
  FAILED=$(jq -r '[.tests[] | select(.status=="fail")] | length' "$REPORT_DIR/dredd.json" 2>/dev/null || echo "$RC")
  TOTAL=$(jq -r '.tests | length' "$REPORT_DIR/dredd.json" 2>/dev/null || echo 0)
else
  log_step api-contract "neither schemathesis nor dredd installed — N/A_PENDING_REVIEWER (LAW-15 missing tool)"
  emit_na_pending "GATE-19" "api-contract.json" "no schemathesis/dredd installed; reviewer must install (pip install schemathesis) OR justify"
  exit 0
fi

PASSED=$([ "$FAILED" -eq 0 ] && echo true || echo false)
emit_evidence "GATE-19" "$PASSED" "api-contract.json" \
  "{\"tool\":\"schemathesis-or-dredd\",\"total\":$TOTAL,\"failed\":$FAILED,\"report\":\"$REPORT_DIR\",\"openapi\":\"$OPENAPI\"}"

if [[ "$PASSED" == "true" ]]; then log_step api-contract "PASS $TOTAL endpoints"; exit 0
else log_step api-contract "FAIL $FAILED/$TOTAL endpoints failed contract"; exit 1
fi
