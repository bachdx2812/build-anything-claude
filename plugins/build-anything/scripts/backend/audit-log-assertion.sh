#!/usr/bin/env bash
# audit-log-assertion.sh — GATE-18e.
# For each mutation scenario:
#   - pre-count audit_log rows
#   - execute mutation
#   - post-count
#   - assert delta == expected mutation_count (typically 1 per mutation)

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
require_test_db "GATE-18e" "audit-log.json"
log_step audit-log "starting"

AUDIT_TABLE=$(cfg "backend.audit_table" "audit_log")
SCENARIOS_JSON=$(cfg "backend.audit.scenarios" "[]")

if [[ "$SCENARIOS_JSON" == "[]" || "$SCENARIOS_JSON" == "null" ]]; then
  log_step audit-log "no scenarios configured — N/A_PENDING_REVIEWER (F6 fix)"
  emit_na_pending "GATE-18e" "audit-log.json" "no audit scenarios configured; reviewer must verify atom has no auditable mutations OR add them"
  exit 0
fi

BASE=$(cfg "backend.api_base_url" "http://localhost:3000")
FAIL=0
RESULTS="[]"

while IFS= read -r SC; do
  NAME=$(echo "$SC" | jq -r '.name')
  METHOD=$(echo "$SC" | jq -r '.method // "POST"')
  PATH_T=$(echo "$SC" | jq -r '.path')
  BODY=$(echo "$SC" | jq -r '.body // "{}"')
  EXPECTED_DELTA=$(echo "$SC" | jq -r '.expected_audit_delta // 1')
  ACTOR_FILTER=$(echo "$SC" | jq -r '.actor_filter // empty')
  JWT=$(fixture_jwt "$(echo "$SC" | jq -r '.jwt_fixture // "tenant_a"')")

  # build the count query — optionally filtered to the actor doing the mutation
  COUNT_QUERY="SELECT count(*) FROM $AUDIT_TABLE"
  [[ -n "$ACTOR_FILTER" ]] && COUNT_QUERY="$COUNT_QUERY WHERE $ACTOR_FILTER"

  PRE=$(db_query "$COUNT_QUERY" | head -1 | tr -d ' ')
  log_step audit-log "$NAME pre=$PRE"

  CODE=$(curl -sS -o /tmp/.ba-audit-resp.json -w "%{http_code}" \
    -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
    -X "$METHOD" -d "$BODY" "$BASE$PATH_T")

  POST=$(db_query "$COUNT_QUERY" | head -1 | tr -d ' ')
  ACTUAL_DELTA=$((POST - PRE))

  # capture latest audit row content for evidence
  LATEST_AUDIT=$(db_query "SELECT row_to_json(t) FROM (SELECT * FROM $AUDIT_TABLE ORDER BY at_timestamp DESC LIMIT 1) t" 2>/dev/null | head -1 || echo "{}")

  PASSED=true; REASON=""
  if [[ "$ACTUAL_DELTA" -ne "$EXPECTED_DELTA" ]]; then
    PASSED=false
    REASON="delta=$ACTUAL_DELTA want=$EXPECTED_DELTA (http=$CODE)"
  fi

  # Successful mutation (2xx) with delta 0 is the canonical sneaky failure
  if [[ "$CODE" -lt 300 && "$ACTUAL_DELTA" -eq 0 && "$EXPECTED_DELTA" -gt 0 ]]; then
    PASSED=false
    REASON="silent: 2xx response without audit row — exactly what GATE-18e catches"
  fi

  [[ "$PASSED" != "true" ]] && FAIL=$((FAIL+1))

  RESULTS=$(jq -c \
    --arg n "$NAME" --arg c "$CODE" \
    --argjson pre "$PRE" --argjson post "$POST" \
    --argjson actual "$ACTUAL_DELTA" --argjson expected "$EXPECTED_DELTA" \
    --argjson pass "$PASSED" --arg r "$REASON" \
    '. + [{name:$n,http_code:$c,pre:$pre,post:$post,actual_delta:$actual,expected_delta:$expected,passed:$pass,reason:$r}]' \
    <<< "$RESULTS")
done < <( jq -c '.[]' <<< "$SCENARIOS_JSON" )

PASSED=$([ "$FAIL" -eq 0 ] && echo true || echo false)
emit_evidence "GATE-18e" "$PASSED" "audit-log.json" \
  "{\"audit_table\":\"$AUDIT_TABLE\",\"scenarios_run\":$(jq 'length' <<< "$RESULTS"),\"failed\":$FAIL,\"results\":$RESULTS}"

if [[ "$PASSED" == "true" ]]; then log_step audit-log "PASS"; exit 0
else log_step audit-log "FAIL $FAIL scenario(s) — audit log inconsistent with mutations"; exit 1
fi
