#!/usr/bin/env bash
# coverage-trust-test.sh — meta-gate for GATE-IMPL machine-coverage corroboration
# (UBS v9.0 LAW-COV-EXEC).
#
# Locks the fix for the FB-clone field report: a Stage-4 implementer coverage PASS
# must NOT stand on AGENT SELF-REPORT alone. When tests were dispatched against
# declared core_flows, the verdict must be corroborated by a real machine coverage
# artifact (GATE-10). Absent / N/A / 0-instrumented coverage ⇒ N/A_PENDING_REVIEWER,
# never a silent PASS — which is how "test coverage 100% FE+BE" was reported on a
# backend that never booted.
#
# Cases:
#   1. clean self-report, NO machine coverage         → N/A_PENDING_REVIEWER (uncorroborated)
#   2. clean self-report, GATE-10 N/A (dead backend)  → N/A_PENDING_REVIEWER
#   3. clean self-report, GATE-10 PASS (lines>0)      → PASS   (happy path)
#   4. clean self-report, GATE-10 PASS but 0 lines    → N/A_PENDING_REVIEWER (vacuous)
#   5. hard violation (tests verdict FAIL) + GATE-10  → FAIL   (structural always wins)
#   6. tests dispatched but no core_flows declared    → PASS   (nothing to corroborate)
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$SKILL_ROOT/scripts/implementer/implementer-coverage-gate.sh"

OUT_BASE="$(mktemp -d -t cov-trust-meta-XXXXXX)"
declare -a PASSED FAILED
log() { echo "[meta:coverage-trust] $*" >&2; }

[[ -f "$GATE" ]] || { log "FATAL: gate missing: $GATE"; exit 2; }

# mk_base <case-dir> [core_flows-json] [tests-verdict] → echoes atom dir
# Builds a structurally-clean multi-persona atom (no allowlist/overlap violations).
mk_base() {
  local cd="$1" core_flows="${2:-[\"signup\",\"post\"]}" tests_verdict="${3:-PASS}"
  local atom="$cd/atom"
  mkdir -p "$atom/implementer" "$atom/intent" "$atom/gate-mechanical"
  cat > "$atom/implementer/concern-split.json" <<EOF
{"mode":"multi-persona","concerns":{
  "backend":{"dispatch":true,"globs":["backend/**"]},
  "frontend":{"dispatch":false,"globs":["frontend/**"]},
  "tests":{"dispatch":true,"globs":["tests/**"]}}}
EOF
  cat > "$atom/implementer/backend-status.json" <<EOF
{"verdict":"PASS","files_changed":["backend/api.js"]}
EOF
  cat > "$atom/implementer/tests-status.json" <<EOF
{"verdict":"$tests_verdict","files_changed":["tests/api.test.js"],"core_flows_covered":["signup","post"]}
EOF
  cat > "$atom/intent/verdict.json" <<EOF
{"declared":{"core_flows":$core_flows}}
EOF
  echo "$atom"
}

# write_cov <atom> <json> — drop a GATE-10 coverage artifact the corroboration reads.
write_cov() { printf '%s' "$2" > "$1/gate-mechanical/coverage.json"; }

run_case() {
  local name="$1" atom="$2" want_verdict="$3" want_rc="$4"
  local cd; cd="$(dirname "$atom")"
  set +e
  bash "$GATE" --atom-dir "$atom" --project-root "$cd" >"$cd/out" 2>"$cd/err"
  local rc=$?
  set -e
  local vf="$atom/gate-impl/coverage.json"
  if [[ ! -f "$vf" ]]; then log "  $name -> FAIL (no verdict file; rc=$rc)"; FAILED+=("$name(no-verdict)"); return; fi
  local v; v=$(jq -r '.verdict' "$vf" 2>/dev/null)
  if [[ "$v" == "$want_verdict" && "$rc" == "$want_rc" ]]; then
    log "  $name -> PASS (verdict=$v rc=$rc)"; PASSED+=("$name")
  else
    log "  $name -> FAIL (got verdict=$v rc=$rc, want $want_verdict/$want_rc)"
    FAILED+=("$name(verdict=$v,rc=$rc)")
  fi
}

# 1: clean self-report, no machine coverage → N/A (uncorroborated)
A=$(mk_base "$OUT_BASE/1_no_cov")
run_case "1_no_machine_coverage" "$A" "N/A_PENDING_REVIEWER" "0"

# 2: clean self-report, GATE-10 N/A (dead backend) → N/A
A=$(mk_base "$OUT_BASE/2_cov_na")
write_cov "$A" '{"gate":"GATE-10","passed":null,"verdict":"N/A_PENDING_REVIEWER","extra":{}}'
run_case "2_machine_coverage_na" "$A" "N/A_PENDING_REVIEWER" "0"

# 3: clean self-report, GATE-10 PASS with instrumented lines → PASS
A=$(mk_base "$OUT_BASE/3_cov_pass")
write_cov "$A" '{"gate":"GATE-10-line","passed":true,"score":92,"extra":{"total_lines_instrumented":120}}'
run_case "3_machine_coverage_pass" "$A" "PASS" "0"

# 4: clean self-report, GATE-10 "PASS" but 0 instrumented lines → N/A (vacuous)
A=$(mk_base "$OUT_BASE/4_cov_zero")
write_cov "$A" '{"gate":"GATE-10-line","passed":true,"score":100,"extra":{"total_lines_instrumented":0}}'
run_case "4_machine_coverage_vacuous" "$A" "N/A_PENDING_REVIEWER" "0"

# 5: hard violation (tests verdict FAIL) even with good coverage → FAIL
A=$(mk_base "$OUT_BASE/5_hard_violation" '["signup","post"]' "FAIL")
write_cov "$A" '{"gate":"GATE-10-line","passed":true,"score":92,"extra":{"total_lines_instrumented":120}}'
run_case "5_structural_violation_wins" "$A" "FAIL" "1"

# 6: tests dispatched but no core_flows declared → PASS (nothing to corroborate)
A=$(mk_base "$OUT_BASE/6_no_core_flows" '[]')
run_case "6_no_core_flows_no_require" "$A" "PASS" "0"

if [[ ${#FAILED[@]} -gt 0 ]]; then
  log "FAILED: ${FAILED[*]}"; log "summary: pass=${#PASSED[@]} fail=${#FAILED[@]} verdict=FAIL"; exit 1
fi
log "summary: pass=${#PASSED[@]} fail=0 verdict=PASS"
exit 0
