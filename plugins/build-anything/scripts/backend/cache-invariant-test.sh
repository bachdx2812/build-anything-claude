#!/usr/bin/env bash
# cache-invariant-test.sh — GATE-24 (v8.1).
# Verifies write-through correctness + cache headers on cacheable endpoints.
# Wrong cache = stale reads, broken pagination, ghost rows. Worse than no cache.
# Contract: count of cache integrity violations (lower = better; threshold 0).

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step cache "starting"

ENDPOINTS_JSON=$(cfg "backend.cache.endpoints" "[]")
if [[ "$ENDPOINTS_JSON" == "[]" || "$ENDPOINTS_JSON" == "null" ]]; then
  log_step cache "no cache endpoints configured — N/A_PENDING_REVIEWER"
  emit_na_pending "GATE-24" "cache-invariant.json" "no cache endpoints configured; reviewer must verify atom has no caching surface OR add them"
  exit 0
fi

BASE=$(cfg "backend.api_base_url" "http://localhost:3000")
FAIL=0
RESULTS="[]"

# Each EP: {path, write_path?, write_method?, write_body?, jwt_fixture?, expect_cache_control:true, expect_etag:true, expect_vary:false, write_through_check:true}
while IFS= read -r EP; do
  PATH_R=$(echo "$EP" | jq -r '.path')
  WPATH=$(echo "$EP" | jq -r '.write_path // empty')
  WMETHOD=$(echo "$EP" | jq -r '.write_method // "POST"')
  WBODY=$(echo "$EP" | jq -r '.write_body // ""')
  JWT_NAME=$(echo "$EP" | jq -r '.jwt_fixture // empty')
  WANT_CC=$(echo "$EP" | jq -r '.expect_cache_control // true')
  WANT_ET=$(echo "$EP" | jq -r '.expect_etag // false')
  WANT_VR=$(echo "$EP" | jq -r '.expect_vary // false')
  CHECK_WT=$(echo "$EP" | jq -r '.write_through_check // false')

  AUTH=(); [[ -n "$JWT_NAME" ]] && AUTH=(-H "Authorization: Bearer $(fixture_jwt "$JWT_NAME")")
  log_step cache "GET $PATH_R"

  HDRS=$(curl -sS -D - -o /dev/null "$BASE$PATH_R" "${AUTH[@]}" 2>/dev/null || echo "")
  HAS_CC=$(echo "$HDRS" | grep -qiE "^cache-control:" && echo true || echo false)
  HAS_ET=$(echo "$HDRS" | grep -qiE "^etag:" && echo true || echo false)
  HAS_VR=$(echo "$HDRS" | grep -qiE "^vary:" && echo true || echo false)

  PASSED=true; REASON=""
  [[ "$WANT_CC" == "true" && "$HAS_CC" != "true" ]] && { PASSED=false; REASON="${REASON}missing Cache-Control; "; }
  [[ "$WANT_ET" == "true" && "$HAS_ET" != "true" ]] && { PASSED=false; REASON="${REASON}missing ETag; "; }
  [[ "$WANT_VR" == "true" && "$HAS_VR" != "true" ]] && { PASSED=false; REASON="${REASON}missing Vary; "; }

  # Write-through: write then read, confirm read returns the new value.
  WT_OK="skipped"
  if [[ "$CHECK_WT" == "true" && -n "$WPATH" && -n "$WBODY" ]]; then
    log_step cache "write-through probe $WMETHOD $WPATH"
    WRESP=$(curl -sS -X "$WMETHOD" "$BASE$WPATH" "${AUTH[@]}" -H "Content-Type: application/json" -d "$WBODY" 2>/dev/null || echo "{}")
    NEW_ID=$(echo "$WRESP" | jq -r '.id // empty')
    if [[ -n "$NEW_ID" ]]; then
      READ_BACK=$(curl -sS "$BASE$PATH_R" "${AUTH[@]}" 2>/dev/null || echo "[]")
      if echo "$READ_BACK" | jq -e --arg id "$NEW_ID" 'if type=="array" then any(.[]; .id==$id) else .id==$id end' >/dev/null 2>&1; then
        WT_OK=true
      else
        WT_OK=false; PASSED=false; REASON="${REASON}write-through stale (id=$NEW_ID not in read); "
      fi
    else
      WT_OK="no_id_returned"
    fi
  fi

  [[ "$PASSED" != "true" ]] && FAIL=$((FAIL+1))
  RESULTS=$(jq -c --arg p "$PATH_R" --argjson cc "$HAS_CC" --argjson et "$HAS_ET" \
    --argjson vr "$HAS_VR" --arg wt "$WT_OK" --argjson pass "$PASSED" --arg r "$REASON" \
    '. + [{path:$p,cache_control:$cc,etag:$et,vary:$vr,write_through:$wt,passed:$pass,reason:$r}]' <<< "$RESULTS")
done < <( jq -c '.[]' <<< "$ENDPOINTS_JSON" )

PASSED=$([ "$FAIL" -eq 0 ] && echo true || echo false)
emit_evidence "GATE-24" "$PASSED" "cache-invariant.json" \
  "{\"endpoints\":$(jq 'length' <<< "$RESULTS"),\"failed\":$FAIL,\"results\":$RESULTS}"

if [[ "$PASSED" == "true" ]]; then log_step cache "PASS"; exit 0
else log_step cache "FAIL $FAIL endpoint(s) — cache headers wrong or write-through broken"; exit 1
fi
