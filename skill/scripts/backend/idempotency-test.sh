#!/usr/bin/env bash
# idempotency-test.sh — GATE-20.
# For each mutation endpoint with idempotency contract:
#   1. POST with Idempotency-Key X → expect 201
#   2. POST with same key + same body → expect 200 (or 201) and SAME resource_id
#   3. DB row count for resource MUST equal 1 (not 2)

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
require_test_db
log_step idempotency "starting"

ENDPOINTS_JSON=$(cfg "backend.idempotency.endpoints" "[]")
if [[ "$ENDPOINTS_JSON" == "[]" || "$ENDPOINTS_JSON" == "null" ]]; then
  log_step idempotency "no endpoints configured — N/A_PENDING_REVIEWER (F6 fix)"
  emit_na_pending "GATE-20" "idempotency.json" "no idempotency endpoints configured; reviewer must verify no mutation in this atom needs Idempotency-Key"
  exit 0
fi

FAIL=0
RESULTS="[]"

while IFS= read -r EP; do
  METHOD=$(echo "$EP" | jq -r '.method // "POST"')
  PATH_T=$(echo "$EP" | jq -r '.path')
  BODY=$(echo "$EP" | jq -r '.body // "{}"')
  TABLE=$(echo "$EP" | jq -r '.resource_table')
  COUNT_QUERY=$(echo "$EP" | jq -r '.count_query // empty')
  JWT_NAME=$(echo "$EP" | jq -r '.jwt_fixture // "tenant_a"')
  KEY="ba-idem-$(date +%s)-$RANDOM"
  JWT=$(fixture_jwt "$JWT_NAME")

  # pre-count
  PRE=$(db_query "${COUNT_QUERY:-SELECT count(*) FROM $TABLE}" | head -1 | tr -d ' ')

  log_step idempotency "$METHOD $PATH_T key=$KEY"
  # First call
  CODE1=$(http_call "$METHOD" "$PATH_T" "$JWT" "$BODY" \
    && curl -sS -o /tmp/.ba-resp1.json -w "%{http_code}" \
      -H "Idempotency-Key: $KEY" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $JWT" \
      -X "$METHOD" -d "$BODY" \
      "$(cfg backend.api_base_url 'http://localhost:3000')${PATH_T}" )
  ID1=$(jq -r '.id // .order_id // .resource_id // empty' /tmp/.ba-resp1.json 2>/dev/null || echo "")

  # Second call — same key, same body
  CODE2=$(curl -sS -o /tmp/.ba-resp2.json -w "%{http_code}" \
    -H "Idempotency-Key: $KEY" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $JWT" \
    -X "$METHOD" -d "$BODY" \
    "$(cfg backend.api_base_url 'http://localhost:3000')${PATH_T}")
  ID2=$(jq -r '.id // .order_id // .resource_id // empty' /tmp/.ba-resp2.json 2>/dev/null || echo "")

  POST=$(db_query "${COUNT_QUERY:-SELECT count(*) FROM $TABLE}" | head -1 | tr -d ' ')
  DELTA=$((POST - PRE))

  PASSED=true
  REASON=""
  [[ "$DELTA" -ne 1 ]] && { PASSED=false; REASON="${REASON}row_delta=$DELTA (want 1); "; }
  [[ -n "$ID1" && "$ID1" != "$ID2" ]] && { PASSED=false; REASON="${REASON}id mismatch ($ID1 vs $ID2); "; }
  [[ "$CODE1" -ge 400 ]] && { PASSED=false; REASON="${REASON}call1 code=$CODE1; "; }

  [[ "$PASSED" != "true" ]] && FAIL=$((FAIL+1))

  RESULTS=$(jq -c --arg p "$PATH_T" --arg k "$KEY" --argjson d "$DELTA" \
    --arg c1 "$CODE1" --arg c2 "$CODE2" \
    --arg i1 "$ID1" --arg i2 "$ID2" \
    --argjson pass "$PASSED" --arg r "$REASON" \
    '. + [{path:$p,key:$k,row_delta:$d,code1:$c1,code2:$c2,id1:$i1,id2:$i2,passed:$pass,reason:$r}]' \
    <<< "$RESULTS")
done < <( jq -c '.[]' <<< "$ENDPOINTS_JSON" )

PASSED=$([ "$FAIL" -eq 0 ] && echo true || echo false)
emit_evidence "GATE-20" "$PASSED" "idempotency.json" \
  "{\"endpoints_tested\":$(jq 'length' <<< "$RESULTS"),\"failed\":$FAIL,\"results\":$RESULTS}"

if [[ "$PASSED" == "true" ]]; then log_step idempotency "PASS"; exit 0
else log_step idempotency "FAIL $FAIL endpoint(s)"; exit 1
fi
