#!/usr/bin/env bash
# db-invariant-check.sh — GATE-18a.
# Runs every named invariant query from .build-anything.json#backend.invariants.
# Each query MUST return 0 rows (violation queries). Any non-zero row = FAIL.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
require_test_db
log_step db-invariant "starting against DB_DRIVER=$DB_DRIVER"

INVARIANTS_JSON=$(cfg "backend.invariants" "[]")
if [[ "$INVARIANTS_JSON" == "[]" || "$INVARIANTS_JSON" == "null" ]]; then
  log_step db-invariant "no invariants configured — N/A_PENDING_REVIEWER (F6 fix)"
  emit_na_pending "GATE-18a" "db-invariant.json" "no invariants configured; reviewer must verify the atom genuinely has no DB invariants OR list them in .build-anything.json"
  exit 0
fi

# Each invariant: { name, query OR query_file, expect_zero_rows: true }
FAIL_COUNT=0
RESULTS_JSON="[]"

while IFS= read -r INV; do
  NAME=$(echo "$INV" | jq -r '.name')
  EXPECT_ZERO=$(echo "$INV" | jq -r '.expect_zero_rows // true')
  QUERY=$(echo "$INV" | jq -r '.query // empty')
  QUERY_FILE=$(echo "$INV" | jq -r '.query_file // empty')

  if [[ -z "$QUERY" && -n "$QUERY_FILE" ]]; then
    # Support "path/to.sql:section_name" — extracts text between ::section:: markers.
    QF_PATH="${QUERY_FILE%%:*}"
    QF_SECTION="${QUERY_FILE#*:}"
    [[ "$QF_SECTION" == "$QUERY_FILE" ]] && QF_SECTION=""
    [[ ! -f "$PROJECT_ROOT/$QF_PATH" ]] && log_fatal "query file not found: $QF_PATH"
    if [[ -n "$QF_SECTION" ]]; then
      QUERY=$(awk -v s="::$QF_SECTION::" '
        $0 ~ s {found=1; next}
        found && /^-- ::/ {found=0}
        found {print}
      ' "$PROJECT_ROOT/$QF_PATH")
      [[ -z "$QUERY" ]] && log_fatal "section '$QF_SECTION' not found in $QF_PATH"
    else
      QUERY=$(cat "$PROJECT_ROOT/$QF_PATH")
    fi
  fi
  [[ -z "$QUERY" ]] && log_fatal "invariant '$NAME' has neither query nor query_file"

  log_step db-invariant "running '$NAME'"
  ROWS=$(db_query "$QUERY" | wc -l | tr -d ' ')

  PASSED=false
  if [[ "$EXPECT_ZERO" == "true" && "$ROWS" -eq 0 ]]; then
    PASSED=true
  elif [[ "$EXPECT_ZERO" == "false" && "$ROWS" -gt 0 ]]; then
    PASSED=true
  fi

  [[ "$PASSED" != "true" ]] && FAIL_COUNT=$((FAIL_COUNT+1))

  QHASH=$(printf '%s' "$QUERY" | shasum -a 256 | awk '{print $1}')
  RESULTS_JSON=$(jq -c \
    --arg n "$NAME" \
    --argjson r "$ROWS" \
    --argjson p "$PASSED" \
    --arg qh "$QHASH" \
    '. + [{"name":$n,"violation_rows":$r,"passed":$p,"query_sha256":$qh}]' \
    <<< "$RESULTS_JSON")
done < <( jq -c '.[]' <<< "$INVARIANTS_JSON" )

PASSED=$([ "$FAIL_COUNT" -eq 0 ] && echo true || echo false)
emit_evidence "GATE-18a" "$PASSED" "db-invariant.json" \
  "{\"invariants_run\":$(jq 'length' <<< "$RESULTS_JSON"),\"failed\":$FAIL_COUNT,\"results\":$RESULTS_JSON}"

if [[ "$PASSED" == "true" ]]; then
  log_step db-invariant "PASS all $(jq 'length' <<< "$RESULTS_JSON") invariants"
  exit 0
else
  log_step db-invariant "FAIL $FAIL_COUNT invariant(s) violated"
  exit 1
fi
