#!/usr/bin/env bash
# background-job-assertion.sh — GATE-18d.
# Triggers a mutation that enqueues a job. Asserts:
#   1. Queue depth increased
#   2. Job executed (depth returns to baseline within timeout)
#   3. Side-effect probed (e.g. mock email body sha, DB row, S3 object)

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
require_test_db
log_step bg-job "starting"

SCENARIOS_JSON=$(cfg "backend.background_jobs.scenarios" "[]")
if [[ "$SCENARIOS_JSON" == "[]" || "$SCENARIOS_JSON" == "null" ]]; then
  log_step bg-job "no scenarios configured — N/A_PENDING_REVIEWER (F6 fix)"
  emit_na_pending "GATE-18d" "background-job.json" "no bg-job scenarios; reviewer must verify atom enqueues no background work OR add scenarios"
  exit 0
fi

BASE=$(cfg "backend.api_base_url" "http://localhost:3000")
POLL_TIMEOUT=$(cfg "backend.background_jobs.poll_timeout_sec" "30")
FAIL=0
RESULTS="[]"

# Each scenario: { name, queue, trigger_method, trigger_path, trigger_body, side_effect_probe }
while IFS= read -r SC; do
  NAME=$(echo "$SC" | jq -r '.name')
  QUEUE=$(echo "$SC" | jq -r '.queue')
  METHOD=$(echo "$SC" | jq -r '.trigger_method // "POST"')
  PATH_T=$(echo "$SC" | jq -r '.trigger_path')
  BODY=$(echo "$SC" | jq -r '.trigger_body // "{}"')
  PROBE_CMD=$(echo "$SC" | jq -r '.side_effect_probe')
  JWT=$(fixture_jwt "$(echo "$SC" | jq -r '.jwt_fixture // "tenant_a"')")

  # baseline queue depth — admin endpoint exposed by app, or direct queue inspect
  PRE_DEPTH=$(curl -sS "$BASE/admin/queues/$QUEUE/depth" 2>/dev/null || echo 0)
  log_step bg-job "$NAME pre_depth=$PRE_DEPTH"

  # trigger
  curl -sS -o /tmp/.ba-bg-resp.json -w "%{http_code}\n" \
    -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
    -X "$METHOD" -d "$BODY" "$BASE$PATH_T" >/dev/null

  # immediately check depth went up
  AFTER_TRIGGER=$(curl -sS "$BASE/admin/queues/$QUEUE/depth" 2>/dev/null || echo 0)
  ENQUEUED=false
  [[ "$AFTER_TRIGGER" -gt "$PRE_DEPTH" ]] && ENQUEUED=true

  # poll until depth returns to baseline OR timeout
  EXECUTED=false
  for i in $(seq 1 "$POLL_TIMEOUT"); do
    sleep 1
    NOW=$(curl -sS "$BASE/admin/queues/$QUEUE/depth" 2>/dev/null || echo 0)
    if [[ "$NOW" -le "$PRE_DEPTH" ]]; then EXECUTED=true; break; fi
  done

  # side effect probe — shell-escape user query; expect non-empty stdout = PASS
  SIDE_OUT=$( bash -c "$PROBE_CMD" 2>&1 || true )
  SIDE_OK=false
  [[ -n "$SIDE_OUT" ]] && SIDE_OK=true

  PASSED=true; REASON=""
  [[ "$ENQUEUED" != "true" ]] && { PASSED=false; REASON="${REASON}not enqueued; "; }
  [[ "$EXECUTED" != "true" ]] && { PASSED=false; REASON="${REASON}not executed within ${POLL_TIMEOUT}s; "; }
  [[ "$SIDE_OK" != "true" ]] && { PASSED=false; REASON="${REASON}side effect not observed; "; }

  [[ "$PASSED" != "true" ]] && FAIL=$((FAIL+1))

  RESULTS=$(jq -c \
    --arg n "$NAME" --arg q "$QUEUE" \
    --argjson pd "$PRE_DEPTH" --argjson td "$AFTER_TRIGGER" \
    --argjson en "$ENQUEUED" --argjson ex "$EXECUTED" --argjson se "$SIDE_OK" \
    --argjson pass "$PASSED" --arg r "$REASON" \
    '. + [{name:$n,queue:$q,pre_depth:$pd,after_trigger_depth:$td,enqueued:$en,executed:$ex,side_effect_ok:$se,passed:$pass,reason:$r}]' \
    <<< "$RESULTS")
done < <( jq -c '.[]' <<< "$SCENARIOS_JSON" )

PASSED=$([ "$FAIL" -eq 0 ] && echo true || echo false)
emit_evidence "GATE-18d" "$PASSED" "background-job.json" \
  "{\"poll_timeout_sec\":$POLL_TIMEOUT,\"scenarios_run\":$(jq 'length' <<< "$RESULTS"),\"failed\":$FAIL,\"results\":$RESULTS}"

if [[ "$PASSED" == "true" ]]; then log_step bg-job "PASS"; exit 0
else log_step bg-job "FAIL $FAIL scenario(s)"; exit 1
fi
