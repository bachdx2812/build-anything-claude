#!/usr/bin/env bash
# data-seed-check.sh — GATE-SEED (v8.8).
#
# Data-driven features need SEED rows or they silently produce nothing.
# Audit §5/§8 shape: the `vocabulary` table was empty, so the lesson generator
# returned no lessons — every functional gate still PASSed because none of them
# asserted that the data the feature reads actually exists. GATE-SEED closes that
# hole: for each declared table it runs a count command and FAILs when rows are
# below the declared minimum.
#
# DB-agnostic by design: the gate never speaks SQL itself. Each entry supplies a
# `count_cmd` shim that prints a row count to stdout — in prod that's typically
#   psql -tAc 'select count(*) from vocabulary'
# but it could equally be mysql, sqlite3, a redis DBSIZE, or an HTTP probe. The
# gate only cares that the LAST integer token on stdout is >= min_rows.
#
# Input: .build-anything.json#backend.seed_check[] = array of
#   { "name": "...", "count_cmd": "<shell cmd printing an integer>", "min_rows": N }
# Absent/empty → N/A_PENDING_REVIEWER (LAW-F6: never a silent PASS).
#
# Output: $ATOM_DIR/gate-backend/data-seed.json
# Exit: 0 PASS/NA, 1 FAIL.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

GATE_ID="GATE-SEED"
SCHEMA_VERSION="ubs-v8.8-seed"
OUT_FILE="data-seed.json"

# ── verdict emitters (inline; GATE-SEED owns its schema_version field, which the
# shared emit_evidence does not carry — so we write the JSON here rather than
# editing _common.sh). Mirrors the shape of emit_evidence / emit_na_pending. ──

# emit_seed_evidence <passed:true|false> <evidence-json>
emit_seed_evidence() {
  local passed="$1" evidence="$2"
  local verdict
  verdict=$([ "$passed" == "true" ] && echo '"PASS"' || echo '"FAIL"')
  cat > "$EVIDENCE_DIR/$OUT_FILE" <<JSON
{
  "gate": "$GATE_ID",
  "schema_version": "$SCHEMA_VERSION",
  "passed": $passed,
  "verdict": $verdict,
  "evidence": $evidence,
  "confidence": 100,
  "ambiguities": [],
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project": "$(basename "$PROJECT_ROOT")"
}
JSON
}

# emit_seed_na <reason> — LAW-F6: empty config is N/A, never a silent PASS.
# LAW-CL-95: N/A means confidence=0; the reason is the single declared ambiguity.
emit_seed_na() {
  local reason="$1"
  local reason_json
  reason_json=$(printf '%s' "$reason" | jq -Rs . 2>/dev/null || printf '"%s"' "$reason")
  cat > "$EVIDENCE_DIR/$OUT_FILE" <<JSON
{
  "gate": "$GATE_ID",
  "schema_version": "$SCHEMA_VERSION",
  "passed": null,
  "verdict": "N/A_PENDING_REVIEWER",
  "reason": "$reason",
  "confidence": 0,
  "ambiguities": [$reason_json],
  "review_required": true,
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project": "$(basename "$PROJECT_ROOT")"
}
JSON
}

atom_dir_from_args "$@"
log_step data-seed "starting"

SEED_JSON=$(cfg "backend.seed_check" "[]")
if [[ "$SEED_JSON" == "[]" || "$SEED_JSON" == "null" || -z "$SEED_JSON" ]]; then
  log_step data-seed "no seed_check entries configured — N/A_PENDING_REVIEWER (F6 fix)"
  emit_seed_na "no backend.seed_check entries; reviewer must verify the atom has no data-driven feature OR declare the tables that require seed rows in .build-anything.json"
  exit 0
fi

FAIL_COUNT=0
RESULTS_JSON="[]"
FINDINGS_JSON="[]"

# Each entry: { name, count_cmd, min_rows }
while IFS= read -r ENTRY; do
  NAME=$(echo "$ENTRY" | jq -r '.name // "(unnamed)"')
  COUNT_CMD=$(echo "$ENTRY" | jq -r '.count_cmd // empty')
  MIN_ROWS=$(echo "$ENTRY" | jq -r '.min_rows // 1')

  if [[ -z "$COUNT_CMD" ]]; then
    log_fatal "seed_check entry '$NAME' has no count_cmd"
  fi
  # min_rows must be an integer for the comparison below.
  if ! [[ "$MIN_ROWS" =~ ^[0-9]+$ ]]; then
    log_fatal "seed_check entry '$NAME' has non-integer min_rows='$MIN_ROWS'"
  fi

  log_step data-seed "counting '$NAME' (min_rows=$MIN_ROWS)"

  # Run the count shim from PROJECT_ROOT. set +e so a non-zero exit is captured,
  # not fatal — a failed count command is itself a FAIL finding.
  set +e
  CMD_OUT=$( cd "$PROJECT_ROOT" && bash -c "$COUNT_CMD" 2>&1 )
  CMD_RC=$?
  set -e

  # Parse the LAST integer token from stdout. Robust to chatter / column headers /
  # trailing newlines that real DB CLIs sometimes emit. The `|| true` keeps a
  # no-match grep (non-integer output) from tripping set -e/pipefail — an empty
  # parse is itself a FAIL finding handled below, not a script crash.
  PARSED_COUNT=$(printf '%s' "$CMD_OUT" | grep -oE '[0-9]+' | tail -n 1 || true)

  PASSED=true
  FAIL_REASON=""
  if [[ "$CMD_RC" -ne 0 ]]; then
    PASSED=false
    FAIL_REASON="count_cmd exited non-zero (rc=$CMD_RC)"
  elif [[ -z "$PARSED_COUNT" ]]; then
    PASSED=false
    FAIL_REASON="count_cmd produced no integer on stdout"
  elif [[ "$PARSED_COUNT" -lt "$MIN_ROWS" ]]; then
    PASSED=false
    FAIL_REASON="row count $PARSED_COUNT below required minimum $MIN_ROWS (empty/under-seeded table)"
  fi

  # JSON-safe count for the report (null when unparsed).
  if [[ -n "$PARSED_COUNT" ]]; then COUNT_FOR_JSON="$PARSED_COUNT"; else COUNT_FOR_JSON="null"; fi

  if [[ "$PASSED" != "true" ]]; then
    FAIL_COUNT=$((FAIL_COUNT+1))
    FINDINGS_JSON=$(jq -c \
      --arg n "$NAME" \
      --arg r "$FAIL_REASON" \
      '. + [{"name":$n,"reason":$r}]' \
      <<< "$FINDINGS_JSON")
  fi

  RESULTS_JSON=$(jq -c \
    --arg n "$NAME" \
    --argjson c "$COUNT_FOR_JSON" \
    --argjson m "$MIN_ROWS" \
    --argjson rc "$CMD_RC" \
    --argjson p "$PASSED" \
    '. + [{"name":$n,"count":$c,"min_rows":$m,"cmd_rc":$rc,"passed":$p}]' \
    <<< "$RESULTS_JSON")
done < <( jq -c '.[]' <<< "$SEED_JSON" )

PASSED=$([ "$FAIL_COUNT" -eq 0 ] && echo true || echo false)
TOTAL=$(jq 'length' <<< "$RESULTS_JSON")

# LAW-CL-95 — verdict carries confidence + ambiguities. The count commands ran
# concretely (numeric proof in hand) so confidence is 100 and ambiguities empty.
EVIDENCE_JSON=$(jq -c -n \
  --argjson total "$TOTAL" \
  --argjson failed "$FAIL_COUNT" \
  --argjson results "$RESULTS_JSON" \
  --argjson findings "$FINDINGS_JSON" \
  '{tables_checked:$total,failed:$failed,results:$results,findings:$findings}')

emit_seed_evidence "$PASSED" "$EVIDENCE_JSON"

if [[ "$PASSED" == "true" ]]; then
  log_step data-seed "PASS all $TOTAL table(s) seeded"
  exit 0
else
  log_step data-seed "FAIL $FAIL_COUNT table(s) under-seeded"
  exit 1
fi
