#!/usr/bin/env bash
# rate-limit-test.sh — GATE-23 (v8.1).
# Bursts N req/s and verifies the server returns 429 + Retry-After header.
# Without RL, an attacker can drain DB / cost / auth-retry surface.
# Contract: count of endpoints where RL was expected and NOT enforced (lower = better; threshold 0).

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step rate-limit "starting"

ENDPOINTS_JSON=$(cfg "backend.rate_limit.endpoints" "[]")
if [[ "$ENDPOINTS_JSON" == "[]" || "$ENDPOINTS_JSON" == "null" ]]; then
  log_step rate-limit "no endpoints configured — N/A_PENDING_REVIEWER"
  emit_na_pending "GATE-23" "rate-limit.json" "no rate-limit endpoints configured; reviewer must verify atom has no rate-sensitive surface OR add them"
  exit 0
fi

BASE=$(cfg "backend.api_base_url" "http://localhost:3000")
FAIL=0
RESULTS="[]"

# Each EP: {method, path, body?, burst:int, jwt_fixture?, expected_status:429, require_retry_after:true}
while IFS= read -r EP; do
  METHOD=$(echo "$EP" | jq -r '.method // "GET"')
  PATH_T=$(echo "$EP" | jq -r '.path')
  BURST=$(echo "$EP"  | jq -r '.burst // 100')
  BODY=$(echo "$EP"   | jq -r '.body // ""')
  JWT_NAME=$(echo "$EP" | jq -r '.jwt_fixture // empty')
  EXP=$(echo "$EP" | jq -r '.expected_status // "429"')
  NEED_RA=$(echo "$EP" | jq -r '.require_retry_after // true')
  AUTH=(); [[ -n "$JWT_NAME" ]] && AUTH=(-H "Authorization: Bearer $(fixture_jwt "$JWT_NAME")")
  DATA=(); [[ -n "$BODY" ]] && DATA=(-H "Content-Type: application/json" -d "$BODY")

  log_step rate-limit "$METHOD $PATH_T burst=$BURST"
  CODES_FILE=$(mktemp)
  HDRS_FILE=$(mktemp)
  # Fire BURST requests in parallel, capture codes + retry-after header
  seq "$BURST" | xargs -P 20 -I{} sh -c "curl -sS -o /dev/null -D - -w '%{http_code}\\n' -X '$METHOD' ${AUTH[*]:+${AUTH[*]}} ${DATA[*]:+${DATA[*]}} '$BASE$PATH_T' 2>/dev/null | tee -a '$HDRS_FILE' | tail -1 >> '$CODES_FILE'" 2>/dev/null || true

  N429=$(grep -c "^$EXP$" "$CODES_FILE" 2>/dev/null || echo 0)
  HAS_RA=false
  grep -qiE "^retry-after:" "$HDRS_FILE" 2>/dev/null && HAS_RA=true
  rm -f "$CODES_FILE" "$HDRS_FILE"

  PASSED=true; REASON=""
  [[ "$N429" -eq 0 ]] && { PASSED=false; REASON="${REASON}no $EXP across $BURST req; "; }
  [[ "$NEED_RA" == "true" && "$HAS_RA" != "true" ]] && { PASSED=false; REASON="${REASON}missing Retry-After header; "; }

  [[ "$PASSED" != "true" ]] && FAIL=$((FAIL+1))
  RESULTS=$(jq -c --arg p "$PATH_T" --argjson n "$N429" --argjson b "$BURST" \
    --argjson ra "$HAS_RA" --argjson pass "$PASSED" --arg r "$REASON" \
    '. + [{path:$p,n_429:$n,burst:$b,retry_after:$ra,passed:$pass,reason:$r}]' <<< "$RESULTS")
done < <( jq -c '.[]' <<< "$ENDPOINTS_JSON" )

PASSED=$([ "$FAIL" -eq 0 ] && echo true || echo false)
emit_evidence "GATE-23" "$PASSED" "rate-limit.json" \
  "{\"endpoints\":$(jq 'length' <<< "$RESULTS"),\"failed\":$FAIL,\"results\":$RESULTS}"

if [[ "$PASSED" == "true" ]]; then log_step rate-limit "PASS"; exit 0
else log_step rate-limit "FAIL $FAIL endpoint(s) — rate limit absent or weak"; exit 1
fi
