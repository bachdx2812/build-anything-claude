#!/usr/bin/env bash
# concurrency-test.sh — GATE-18b.
# Parallel POSTs (xargs -P N) to each mutation endpoint with identical payload.
# Proves: no duplicate rows, consistent response codes, no DB constraint violations.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
require_test_db "GATE-18b" "concurrency.json"
log_step concurrency "starting"

ENDPOINTS_JSON=$(cfg "backend.concurrency.endpoints" "[]")
PARALLELISM=$(cfg "backend.concurrency.parallel" "10")
if [[ "$ENDPOINTS_JSON" == "[]" || "$ENDPOINTS_JSON" == "null" ]]; then
  log_step concurrency "no endpoints configured — N/A_PENDING_REVIEWER (F6: no vacuous PASS)"
  emit_na_pending "GATE-18b" "concurrency.json" "no concurrency endpoints configured; reviewer must add backend.concurrency.endpoints OR confirm atom has no concurrent-write surface"
  exit 0
fi

FAIL=0
RESULTS="[]"
BASE=$(cfg "backend.api_base_url" "http://localhost:3000")

while IFS= read -r EP; do
  PATH_T=$(echo "$EP" | jq -r '.path')
  METHOD=$(echo "$EP" | jq -r '.method // "POST"')
  BODY=$(echo "$EP" | jq -r '.body // "{}"')
  TABLE=$(echo "$EP" | jq -r '.resource_table')
  UNIQUE_KEY=$(echo "$EP" | jq -r '.unique_key // empty')
  JWT=$(fixture_jwt "$(echo "$EP" | jq -r '.jwt_fixture // "tenant_a"')")

  PRE=$(db_query "SELECT count(*) FROM $TABLE" | head -1 | tr -d ' ')

  # fire N parallel
  CODES_FILE="$(mktemp)"
  trap 'rm -f "$CODES_FILE"' EXIT
  seq 1 "$PARALLELISM" | xargs -P "$PARALLELISM" -I{} bash -c "
    curl -sS -o /dev/null -w '%{http_code}\n' \
      -H 'Content-Type: application/json' \
      -H 'Authorization: Bearer $JWT' \
      -X '$METHOD' -d '$BODY' \
      '$BASE$PATH_T'" > "$CODES_FILE" || true

  POST=$(db_query "SELECT count(*) FROM $TABLE" | head -1 | tr -d ' ')
  DELTA=$((POST - PRE))

  # check uniqueness — if unique_key specified, the column must have no duplicates among new rows
  DUPES=0
  if [[ -n "$UNIQUE_KEY" ]]; then
    DUPES=$(db_query "SELECT count(*) FROM (SELECT $UNIQUE_KEY, count(*) c FROM $TABLE GROUP BY $UNIQUE_KEY HAVING count(*) > 1) t" | head -1 | tr -d ' ')
  fi

  # response codes
  C2XX=$(grep -cE '^2' "$CODES_FILE" || true)
  C4XX=$(grep -cE '^4' "$CODES_FILE" || true)
  C5XX=$(grep -cE '^5' "$CODES_FILE" || true)

  PASSED=true; REASON=""
  [[ "$DUPES" -gt 0 ]] && { PASSED=false; REASON="${REASON}dupes=$DUPES; "; }
  [[ "$C5XX" -gt 0 ]] && { PASSED=false; REASON="${REASON}5xx=$C5XX; "; }
  # spec-dependent: idempotent → delta MUST be 1; create-many → delta MUST be N
  EXPECTED=$(echo "$EP" | jq -r '.expected_row_delta // 0')
  if [[ "$EXPECTED" -gt 0 && "$DELTA" -ne "$EXPECTED" ]]; then
    PASSED=false; REASON="${REASON}delta=$DELTA expected=$EXPECTED; "
  fi

  [[ "$PASSED" != "true" ]] && FAIL=$((FAIL+1))

  RESULTS=$(jq -c \
    --arg p "$PATH_T" --argjson d "$DELTA" --argjson dup "$DUPES" \
    --argjson c2 "$C2XX" --argjson c4 "$C4XX" --argjson c5 "$C5XX" \
    --argjson pass "$PASSED" --arg r "$REASON" \
    '. + [{path:$p,row_delta:$d,duplicates:$dup,codes_2xx:$c2,codes_4xx:$c4,codes_5xx:$c5,passed:$pass,reason:$r}]' \
    <<< "$RESULTS")
done < <( jq -c '.[]' <<< "$ENDPOINTS_JSON" )

PASSED=$([ "$FAIL" -eq 0 ] && echo true || echo false)
emit_evidence "GATE-18b" "$PASSED" "concurrency.json" \
  "{\"parallelism\":$PARALLELISM,\"endpoints_tested\":$(jq 'length' <<< "$RESULTS"),\"failed\":$FAIL,\"results\":$RESULTS}"

if [[ "$PASSED" == "true" ]]; then log_step concurrency "PASS"; exit 0
else log_step concurrency "FAIL $FAIL endpoint(s)"; exit 1
fi
