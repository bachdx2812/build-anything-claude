#!/usr/bin/env bash
# transaction-atomicity-test.sh — GATE-18c.
# Inject failure mid-transaction (via app's chaos endpoint or DB kill query) and
# verify named invariants STILL HOLD after rollback. Requires app to expose a
# chaos middleware that aborts at a configurable injection point.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
require_test_db
log_step tx-atomicity "starting"

SCENARIOS_JSON=$(cfg "backend.tx_atomicity.scenarios" "[]")
if [[ "$SCENARIOS_JSON" == "[]" || "$SCENARIOS_JSON" == "null" ]]; then
  log_step tx-atomicity "no scenarios configured — vacuous PASS"
  emit_evidence "GATE-18c" true "transaction-atomicity.json" '{"scenarios_run":0}'
  exit 0
fi

BASE=$(cfg "backend.api_base_url" "http://localhost:3000")
FAIL=0
RESULTS="[]"

# Each scenario: { name, method, path, body, jwt_fixture, inject_point, invariant_query, invariant_expect_zero }
while IFS= read -r SC; do
  NAME=$(echo "$SC" | jq -r '.name')
  METHOD=$(echo "$SC" | jq -r '.method // "POST"')
  PATH_T=$(echo "$SC" | jq -r '.path')
  BODY=$(echo "$SC" | jq -r '.body // "{}"')
  INJECT=$(echo "$SC" | jq -r '.inject_point')
  INV_Q=$(echo "$SC" | jq -r '.invariant_query')
  INV_EXP_ZERO=$(echo "$SC" | jq -r '.invariant_expect_zero // true')
  JWT=$(fixture_jwt "$(echo "$SC" | jq -r '.jwt_fixture // "tenant_a"')")

  # pre-state
  PRE=$(db_query "$INV_Q" | wc -l | tr -d ' ')

  log_step tx-atomicity "$NAME inject=$INJECT"
  # call with chaos header — app reads X-Chaos-Inject and aborts at named point
  CODE=$(curl -sS -o /tmp/.ba-tx-resp.json -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $JWT" \
    -H "X-Chaos-Inject: $INJECT" \
    -X "$METHOD" -d "$BODY" \
    "$BASE$PATH_T")

  # 5xx is EXPECTED — we requested a failure
  # Now verify invariant
  POST=$(db_query "$INV_Q" | wc -l | tr -d ' ')

  INV_OK=true
  if [[ "$INV_EXP_ZERO" == "true" && "$POST" -ne 0 ]]; then INV_OK=false; fi
  if [[ "$INV_EXP_ZERO" == "false" && "$POST" -eq 0 ]]; then INV_OK=false; fi

  # Additional check: row count delta should be 0 (rollback worked)
  ROLLBACK_OK=true
  if [[ "$PRE" -ne "$POST" ]]; then ROLLBACK_OK=false; fi

  PASSED=true; REASON=""
  [[ "$INV_OK" != "true" ]] && { PASSED=false; REASON="${REASON}invariant violated post-chaos; "; }
  [[ "$ROLLBACK_OK" != "true" ]] && { PASSED=false; REASON="${REASON}state changed (pre=$PRE post=$POST); "; }

  [[ "$PASSED" != "true" ]] && FAIL=$((FAIL+1))

  RESULTS=$(jq -c \
    --arg n "$NAME" --arg inj "$INJECT" --arg c "$CODE" \
    --argjson pre "$PRE" --argjson post "$POST" \
    --argjson invok "$INV_OK" --argjson rbok "$ROLLBACK_OK" \
    --argjson pass "$PASSED" --arg r "$REASON" \
    '. + [{name:$n,inject_point:$inj,http_code:$c,pre_rows:$pre,post_rows:$post,invariant_ok:$invok,rollback_ok:$rbok,passed:$pass,reason:$r}]' \
    <<< "$RESULTS")
done < <( jq -c '.[]' <<< "$SCENARIOS_JSON" )

PASSED=$([ "$FAIL" -eq 0 ] && echo true || echo false)
emit_evidence "GATE-18c" "$PASSED" "transaction-atomicity.json" \
  "{\"scenarios_run\":$(jq 'length' <<< "$RESULTS"),\"failed\":$FAIL,\"results\":$RESULTS}"

if [[ "$PASSED" == "true" ]]; then log_step tx-atomicity "PASS"; exit 0
else log_step tx-atomicity "FAIL $FAIL scenario(s) — atomicity broken"; exit 1
fi
