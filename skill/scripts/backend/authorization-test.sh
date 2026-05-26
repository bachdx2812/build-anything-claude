#!/usr/bin/env bash
# authorization-test.sh — GATE-18f.
# For each endpoint, attempts:
#   1. anonymous (no JWT) → expect 401
#   2. wrong-user JWT → expect 403 (or 404 for resource-not-found-style hides)
#   3. owner JWT → expect 2xx
# Records curl transcripts for all three calls.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step authorization "starting"

ENDPOINTS_JSON=$(cfg "backend.authorization.endpoints" "[]")
if [[ "$ENDPOINTS_JSON" == "[]" || "$ENDPOINTS_JSON" == "null" ]]; then
  log_step authorization "no endpoints configured — N/A_PENDING_REVIEWER (F6 fix)"
  emit_na_pending "GATE-18f" "authorization.json" "no authorization endpoints configured; reviewer must verify atom has no protected endpoints OR add them"
  exit 0
fi

BASE=$(cfg "backend.api_base_url" "http://localhost:3000")
FAIL=0
RESULTS="[]"

# Each endpoint: { method, path, body?, owner_fixture, wrong_fixture, expected_anon?, expected_wrong?, expected_owner? }
while IFS= read -r EP; do
  METHOD=$(echo "$EP" | jq -r '.method')
  PATH_T=$(echo "$EP" | jq -r '.path')
  BODY=$(echo "$EP" | jq -r '.body // ""')
  OWNER_FIX=$(echo "$EP" | jq -r '.owner_fixture // "tenant_a"')
  WRONG_FIX=$(echo "$EP" | jq -r '.wrong_fixture // "tenant_b"')
  EXP_ANON=$(echo "$EP" | jq -r '.expected_anon // "401"')
  EXP_WRONG=$(echo "$EP" | jq -r '.expected_wrong // "403"')
  EXP_OWNER=$(echo "$EP" | jq -r '.expected_owner // "2xx"')

  OWNER_JWT=$(fixture_jwt "$OWNER_FIX")
  WRONG_JWT=$(fixture_jwt "$WRONG_FIX")

  DATA=()
  [[ -n "$BODY" ]] && DATA=(-H "Content-Type: application/json" -d "$BODY")

  CODE_ANON=$(curl -sS -o /dev/null -w "%{http_code}" \
    -X "$METHOD" ${DATA[@]+"${DATA[@]}"} "$BASE$PATH_T")

  CODE_WRONG=$(curl -sS -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $WRONG_JWT" \
    -X "$METHOD" ${DATA[@]+"${DATA[@]}"} "$BASE$PATH_T")

  CODE_OWNER=$(curl -sS -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $OWNER_JWT" \
    -X "$METHOD" ${DATA[@]+"${DATA[@]}"} "$BASE$PATH_T")

  # validate expectations
  match() {
    local actual="$1" pat="$2"
    case "$pat" in
      2xx) [[ "$actual" -ge 200 && "$actual" -lt 300 ]] && return 0 ;;
      4xx) [[ "$actual" -ge 400 && "$actual" -lt 500 ]] && return 0 ;;
      5xx) [[ "$actual" -ge 500 ]] && return 0 ;;
      *)   [[ "$actual" == "$pat" ]] && return 0 ;;
    esac
    return 1
  }

  PASSED=true; REASON=""
  if ! match "$CODE_ANON"  "$EXP_ANON"  ; then PASSED=false; REASON="${REASON}anon=$CODE_ANON want=$EXP_ANON; "; fi
  if ! match "$CODE_WRONG" "$EXP_WRONG" ; then PASSED=false; REASON="${REASON}wrong=$CODE_WRONG want=$EXP_WRONG; "; fi
  if ! match "$CODE_OWNER" "$EXP_OWNER" ; then PASSED=false; REASON="${REASON}owner=$CODE_OWNER want=$EXP_OWNER; "; fi

  [[ "$PASSED" != "true" ]] && FAIL=$((FAIL+1))

  RESULTS=$(jq -c \
    --arg m "$METHOD" --arg p "$PATH_T" \
    --arg a "$CODE_ANON" --arg w "$CODE_WRONG" --arg o "$CODE_OWNER" \
    --arg ea "$EXP_ANON" --arg ew "$EXP_WRONG" --arg eo "$EXP_OWNER" \
    --argjson pass "$PASSED" --arg r "$REASON" \
    '. + [{method:$m,path:$p,code_anon:$a,code_wrong:$w,code_owner:$o,expected_anon:$ea,expected_wrong:$ew,expected_owner:$eo,passed:$pass,reason:$r}]' \
    <<< "$RESULTS")
done < <( jq -c '.[]' <<< "$ENDPOINTS_JSON" )

PASSED=$([ "$FAIL" -eq 0 ] && echo true || echo false)
emit_evidence "GATE-18f" "$PASSED" "authorization.json" \
  "{\"endpoints_tested\":$(jq 'length' <<< "$RESULTS"),\"failed\":$FAIL,\"results\":$RESULTS}"

if [[ "$PASSED" == "true" ]]; then log_step authorization "PASS"; exit 0
else log_step authorization "FAIL $FAIL endpoint(s)"; exit 1
fi
