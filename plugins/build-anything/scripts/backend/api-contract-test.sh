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
JWT_FIXTURE=$(cfg "backend.contract.jwt_fixture" "")

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
  # Detect schemathesis major version (3.x uses --base-url + --hypothesis-max-examples + --junit-xml;
  # 4.x renamed to --url + --max-examples + --report junit --report-junit-path).
  SCHEMA_VER=$(schemathesis --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
  SCHEMA_MAJOR="${SCHEMA_VER%%.*}"
  JUNIT_PATH="$REPORT_DIR/schemathesis-junit.xml"
  set +e
  if [[ "$SCHEMA_MAJOR" -ge 4 ]]; then
    schemathesis run "$SPEC_PATH" \
      --url "$BASE" $AUTH_HDR \
      --max-examples 30 \
      --report junit \
      --report-dir "$REPORT_DIR/schemathesis-report" \
      --report-junit-path "$JUNIT_PATH" >/tmp/.ba-schemathesis.log 2>&1
  else
    schemathesis run "$SPEC_PATH" \
      --base-url "$BASE" $AUTH_HDR \
      --hypothesis-max-examples 30 \
      --checks all \
      --junit-xml "$JUNIT_PATH" \
      --report "$REPORT_DIR/schemathesis-report" >/tmp/.ba-schemathesis.log 2>&1
  fi
  RC=$?
  set -e

  if [[ ! -f "$JUNIT_PATH" ]]; then
    log_step api-contract "schemathesis produced no JUnit report (exit=$RC) — N/A_PENDING_REVIEWER (F6: no vacuous PASS)"
    emit_na_pending "GATE-19" "api-contract.json" "schemathesis ran but produced no junit XML at $JUNIT_PATH (exit=$RC); reviewer must inspect /tmp/.ba-schemathesis.log — likely server not reachable at $BASE or flag mismatch"
    exit 0
  fi
  # JUnit XML — count <testcase> and <failure>. Use xmllint if available, else grep.
  if command -v xmllint >/dev/null 2>&1; then
    TOTAL=$(xmllint --xpath 'count(//testcase)' "$JUNIT_PATH" 2>/dev/null || echo 0)
    FAILED=$(xmllint --xpath 'count(//testcase[failure or error])' "$JUNIT_PATH" 2>/dev/null || echo 0)
  else
    TOTAL=$(grep -cE '<testcase' "$JUNIT_PATH" 2>/dev/null || echo 0)
    FAILED=$(grep -cE '<(failure|error)' "$JUNIT_PATH" 2>/dev/null || echo 0)
  fi
  # Vacuous PASS guard — 0 tests run means no contract evidence.
  if [[ "$TOTAL" -eq 0 ]]; then
    log_step api-contract "schemathesis discovered 0 testcases — N/A_PENDING_REVIEWER (F6: no vacuous PASS)"
    emit_na_pending "GATE-19" "api-contract.json" "schemathesis ran but 0 testcases were generated; reviewer must verify OpenAPI has operations OR server is reachable at $BASE"
    exit 0
  fi
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
