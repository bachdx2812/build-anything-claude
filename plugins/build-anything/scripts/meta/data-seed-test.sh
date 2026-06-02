#!/usr/bin/env bash
# data-seed-test.sh — meta-gate for GATE-SEED (v8.8).
#
# Asserts the data-seed gate catches the audit §5/§8 shape: a data-driven feature
# whose backing table is EMPTY (vocabulary had 0 rows → lesson generator returned
# nothing, yet every functional gate still PASSed because none asserted the data
# the feature reads actually exists).
#
#   1. PASS — table count meets its declared minimum (150 >= 50).
#   2. FAIL — empty table below minimum (0 >= 50 is false) — the mandarin shape.
#   3. FAIL — count_cmd produces a non-integer / errors (no row count to trust).
#   4. N/A  — no backend.seed_check declared (LAW-F6: no vacuous PASS).
#
# Why this exists: GATE-SEED is the v8.8 fix for the empty-vocabulary finding.
# Without this regression a future edit could let an empty data table sail
# through and the audit's finding would silently return.
#
# Count commands use plain echo-shims — NO real DB. The gate parses the LAST
# integer token from count_cmd stdout, so `echo 150` stands in for
# `psql -tAc 'select count(*) from vocabulary'`.
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE_SCRIPT="$SKILL_ROOT/scripts/backend/data-seed-check.sh"

OUT_BASE="$(mktemp -d -t data-seed-meta-XXXXXX)"
declare -a CASES_PASSED CASES_FAILED

log() { echo "[meta:data-seed] $*" >&2; }

[[ -f "$GATE_SCRIPT" ]] || { log "FATAL: gate script missing: $GATE_SCRIPT"; exit 2; }

# setup <name> <config-json> → echoes case_dir
setup() {
  local name="$1" cfg="$2"
  local case_dir="$OUT_BASE/$name"
  local atom_dir="$case_dir/atom"
  mkdir -p "$atom_dir/gate-backend"
  printf '%s' "$cfg" > "$case_dir/.build-anything.json"
  echo "$case_dir"
}

run_case() {
  local name="$1" case_dir="$2" expected_verdict="$3" expected_rc="$4"
  local atom_dir="$case_dir/atom"
  log "case=$name expect=verdict:$expected_verdict rc:$expected_rc"
  set +e
  bash "$GATE_SCRIPT" --atom-dir "$atom_dir" --project-root "$case_dir" \
    >"$case_dir/stdout" 2>"$case_dir/stderr"
  local actual_rc=$?
  set -e
  local verdict_file="$atom_dir/gate-backend/data-seed.json"
  if [[ ! -f "$verdict_file" ]]; then
    log "  -> FAIL: no verdict file"; CASES_FAILED+=("$name(no-verdict)"); return
  fi
  local actual_verdict
  actual_verdict=$(jq -r '.verdict' "$verdict_file" 2>/dev/null)
  if [[ "$actual_verdict" == "$expected_verdict" && "$actual_rc" == "$expected_rc" ]]; then
    log "  -> PASS"; CASES_PASSED+=("$name")
  else
    log "  -> FAIL: got verdict=$actual_verdict rc=$actual_rc"
    jq -c '{gate,schema_version,verdict,evidence:(.evidence.findings // null),reason}' "$verdict_file" 2>/dev/null | sed 's/^/       /' >&2 || true
    CASES_FAILED+=("$name(verdict=$actual_verdict,rc=$actual_rc)")
  fi
}

# ── Case 1: seeded table meets minimum → PASS ──────────────────────────
CD=$(setup "1_seeded" '{
  "backend": { "seed_check": [
    { "name": "vocabulary", "count_cmd": "echo 150", "min_rows": 50 }
  ] }
}')
run_case "1_seeded" "$CD" "PASS" "0"

# ── Case 2: empty vocabulary table → FAIL (the §5/§8 mandarin shape) ───
CD=$(setup "2_empty_table" '{
  "backend": { "seed_check": [
    { "name": "vocabulary", "count_cmd": "echo 0", "min_rows": 50 }
  ] }
}')
run_case "2_empty_table" "$CD" "FAIL" "1"

# ── Case 3: count_cmd yields no integer → FAIL ─────────────────────────
CD=$(setup "3_bad_cmd" '{
  "backend": { "seed_check": [
    { "name": "x", "count_cmd": "echo notanumber", "min_rows": 1 }
  ] }
}')
run_case "3_bad_cmd" "$CD" "FAIL" "1"

# ── Case 4: no seed_check declared → N/A (LAW-F6) ──────────────────────
CD=$(setup "4_no_seed_check" '{"env":"test"}')
run_case "4_no_seed_check" "$CD" "N/A_PENDING_REVIEWER" "0"

# ── Aggregate ──────────────────────────────────────────────────────────
if [[ ${#CASES_FAILED[@]} -gt 0 ]]; then
  log "FAILED cases:"; for c in "${CASES_FAILED[@]}"; do log "  - $c"; done
  log "summary: pass=${#CASES_PASSED[@]} fail=${#CASES_FAILED[@]} verdict=FAIL"
  exit 1
fi
log "summary: pass=${#CASES_PASSED[@]} fail=0 verdict=PASS"
exit 0
