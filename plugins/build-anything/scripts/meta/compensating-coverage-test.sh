#!/usr/bin/env bash
# compensating-coverage-test.sh — meta-gate for v8.7.1 GATE-COMP-COV
#
# Verifies that the compensating-coverage gate correctly enforces LAW-F6
# for uncovered project_types (library / cli / sdk / daemon / ...).
#
# Fixtures:
#   1. project_type=frontend → N/A (covered by playwright)
#   2. project_type=library, no compensating_coverage block → FAIL (LAW-F6)
#   3. project_type=library + enabled, coverage_cmd missing → FAIL
#   4. project_type=library + enabled + cmd succeeds + line=92 branch=88 (above) → PASS
#   5. project_type=library + enabled + cmd succeeds + line=75 (below 90) → FAIL
#   6. project_type=cli + enabled + cmd succeeds + line=0 branch=0 (vacuous) → FAIL
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE_SCRIPT="$SKILL_ROOT/scripts/mechanical/compensating-coverage.sh"

OUT_BASE="$(mktemp -d -t comp-cov-meta-XXXXXX)"
declare -a CASES_PASSED CASES_FAILED

log() { echo "[meta:comp-cov] $*" >&2; }

if [[ ! -x "$GATE_SCRIPT" ]]; then
  log "FATAL: gate script not executable: $GATE_SCRIPT"
  exit 2
fi

mk_project() {
  local name="$1" config_json="$2"
  local proj_dir="$OUT_BASE/$name"
  mkdir -p "$proj_dir/atom/gate-mechanical"
  echo "$config_json" > "$proj_dir/.build-anything.json"
  echo "$proj_dir"
}

# Write a simple-format coverage report at $1 with line=$2 branch=$3
write_simple_report() {
  local path="$1" line="$2" branch="$3"
  mkdir -p "$(dirname "$path")"
  printf '{"line": %s, "branch": %s}\n' "$line" "$branch" > "$path"
}

run_case() {
  local name="$1" proj_dir="$2" expected_verdict="$3" expected_rc="$4"
  log "case=$name expect=verdict:$expected_verdict rc:$expected_rc"

  set +e
  bash "$GATE_SCRIPT" --atom-dir "$proj_dir/atom" --project-root "$proj_dir" \
    >"$proj_dir/stdout" 2>"$proj_dir/stderr"
  local actual_rc=$?
  set -e

  local verdict_file="$proj_dir/atom/gate-mechanical/compensating-coverage.json"
  if [[ ! -f "$verdict_file" ]]; then
    log "  -> FAIL: no verdict file"
    CASES_FAILED+=("$name(no-verdict-file)")
    return
  fi

  local actual_verdict
  actual_verdict=$(jq -r '.verdict' "$verdict_file" 2>/dev/null)

  if [[ "$actual_verdict" == "$expected_verdict" && "$actual_rc" == "$expected_rc" ]]; then
    log "  -> PASS"
    CASES_PASSED+=("$name")
  else
    log "  -> FAIL: got verdict=$actual_verdict rc=$actual_rc"
    jq -c '.' "$verdict_file" 2>/dev/null | sed 's/^/         /' >&2 || true
    CASES_FAILED+=("$name(verdict=$actual_verdict,rc=$actual_rc)")
  fi
}

# ── Case 1: frontend → N/A ─────────────────────────────────────────
PROJ=$(mk_project "1_frontend_na" '{"project_type":"frontend"}')
run_case "1_frontend_na" "$PROJ" "N/A_PENDING_REVIEWER" "0"

# ── Case 2: library no compensating_coverage block → FAIL ──────────
PROJ=$(mk_project "2_library_no_config" '{"project_type":"library"}')
run_case "2_library_no_config" "$PROJ" "FAIL" "1"

# ── Case 3: library + enabled, coverage_cmd missing → FAIL ─────────
PROJ=$(mk_project "3_library_no_cmd" '{"project_type":"library","compensating_coverage":{"enabled":true,"reason":"library atom"}}')
run_case "3_library_no_cmd" "$PROJ" "FAIL" "1"

# ── Case 4: library + cmd that produces simple report line=92 branch=88 → PASS ─
PROJ=$(mk_project "4_library_pass" "$(jq -n '{
  project_type: "library",
  compensating_coverage: {
    enabled: true,
    reason: "library atom — no UI, no HTTP boundary; behavioral test path not applicable",
    coverage_cmd: "true",
    coverage_report_path: "coverage/coverage.json",
    coverage_report_format: "simple"
  }
}')")
write_simple_report "$PROJ/coverage/coverage.json" 92 88
run_case "4_library_pass" "$PROJ" "PASS" "0"

# ── Case 5: library + line=75 (below 90 floor) → FAIL ──────────────
PROJ=$(mk_project "5_library_below_floor" "$(jq -n '{
  project_type: "library",
  compensating_coverage: {
    enabled: true,
    reason: "library atom",
    coverage_cmd: "true",
    coverage_report_path: "coverage/coverage.json",
    coverage_report_format: "simple"
  }
}')")
write_simple_report "$PROJ/coverage/coverage.json" 75 90
run_case "5_library_below_floor" "$PROJ" "FAIL" "1"

# ── Case 6: cli + line=0 branch=0 (vacuous) → FAIL ─────────────────
PROJ=$(mk_project "6_cli_vacuous" "$(jq -n '{
  project_type: "cli",
  compensating_coverage: {
    enabled: true,
    reason: "CLI atom — no UI surface",
    coverage_cmd: "true",
    coverage_report_path: "coverage/coverage.json",
    coverage_report_format: "simple"
  }
}')")
write_simple_report "$PROJ/coverage/coverage.json" 0 0
run_case "6_cli_vacuous" "$PROJ" "FAIL" "1"

# ── Aggregate ──────────────────────────────────────────────────────
TOTAL=$(( ${#CASES_PASSED[@]} + ${#CASES_FAILED[@]} ))
log "cases pass=${#CASES_PASSED[@]} fail=${#CASES_FAILED[@]} total=$TOTAL"

if [[ ${#CASES_FAILED[@]} -gt 0 ]]; then
  log "FAILED cases:"
  for c in "${CASES_FAILED[@]}"; do log "  - $c"; done
  exit 1
fi
exit 0
