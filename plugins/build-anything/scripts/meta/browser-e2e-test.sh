#!/usr/bin/env bash
# browser-e2e-test.sh — meta-gate for v8.7 desktop-browser layer
# (GATE-25-E2E-BROWSER + GATE-BROWSER-WPT)
#
# Asserts both desktop-browser mechanical gates correctly enforce LAW-F6
# (no vacuous PASS):
#
# e2e-browser fixtures:
#   1. project_type=backend → e2e-browser N/A_PENDING_REVIEWER (non-browser passthrough)
#   2. project_type=desktop-browser-chromium with browser.binary_path empty → FAIL (LAW-F6)
#   3. project_type=desktop-browser-chromium binary set but no journeys_dir → FAIL
#   4. project_type=desktop-browser-chromium with journeys_dir but 0 journey files → FAIL
#
# browser-wpt fixtures:
#   5. project_type=frontend → wpt N/A_PENDING_REVIEWER
#   6. project_type=desktop-browser-chromium with wpt.enabled=false → FAIL (LAW-F6 declared-but-skipped)
#   7. project_type=desktop-browser-chromium with wpt.enabled=true but empty subset → FAIL
#
# Why this exists: v8.7 introduces desktop-browser-* project_type. Without this
# meta-gate, the desktop-browser dispatch path could silently relax (e.g. accept
# missing binary, accept empty WPT subset) and Devin could ship "a browser" with
# zero standards conformance evidence.
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BROWSER_E2E_SCRIPT="$SKILL_ROOT/scripts/mechanical/e2e-browser.sh"
WPT_SCRIPT="$SKILL_ROOT/scripts/mechanical/browser-wpt-check.sh"

OUT_BASE="$(mktemp -d -t browser-e2e-meta-XXXXXX)"
SUMMARY="$OUT_BASE/summary.json"
declare -a CASES_PASSED CASES_FAILED

log() { echo "[meta:browser-e2e] $*" >&2; }

if [[ ! -x "$BROWSER_E2E_SCRIPT" ]]; then
  log "FATAL: e2e-browser script not executable: $BROWSER_E2E_SCRIPT"
  exit 2
fi
if [[ ! -x "$WPT_SCRIPT" ]]; then
  log "FATAL: browser-wpt script not executable: $WPT_SCRIPT"
  exit 2
fi

mk_project() {
  local name="$1" config_json="$2"
  local proj_dir="$OUT_BASE/$name"
  mkdir -p "$proj_dir"
  echo "$config_json" > "$proj_dir/.build-anything.json"
  mkdir -p "$proj_dir/atom/gate-mechanical"
  echo "$proj_dir"
}

run_case() {
  local name="$1" gate_script="$2" proj_dir="$3" verdict_file="$4" expected_verdict="$5" expected_rc="$6"
  log "case=$name script=$(basename "$gate_script") expect=verdict:$expected_verdict rc:$expected_rc"

  set +e
  bash "$gate_script" --atom-dir "$proj_dir/atom" --project-root "$proj_dir" \
    >"$proj_dir/stdout" 2>"$proj_dir/stderr"
  local actual_rc=$?
  set -e

  if [[ ! -f "$proj_dir/atom/$verdict_file" ]]; then
    log "  -> FAIL: no verdict file at $proj_dir/atom/$verdict_file"
    CASES_FAILED+=("$name(no-verdict-file)")
    return
  fi

  local actual_verdict
  actual_verdict=$(jq -r '.verdict' "$proj_dir/atom/$verdict_file" 2>/dev/null)

  if [[ "$actual_verdict" == "$expected_verdict" && "$actual_rc" == "$expected_rc" ]]; then
    log "  -> PASS"
    CASES_PASSED+=("$name")
  else
    log "  -> FAIL: got verdict=$actual_verdict rc=$actual_rc"
    log "       file: $proj_dir/atom/$verdict_file"
    jq -c '.' "$proj_dir/atom/$verdict_file" 2>/dev/null | sed 's/^/         /' >&2 || true
    CASES_FAILED+=("$name(verdict=$actual_verdict,rc=$actual_rc)")
  fi
}

# ── Case 1: backend → e2e-browser N/A ───────────────────────────────
PROJ=$(mk_project "1_browser_backend_na" '{"project_type":"backend"}')
run_case "1_browser_backend_na" "$BROWSER_E2E_SCRIPT" "$PROJ" "gate-mechanical/e2e-browser.json" "N/A_PENDING_REVIEWER" "0"

# ── Case 2: desktop-browser-chromium no binary_path → FAIL ──────────
PROJ=$(mk_project "2_browser_no_binary" '{"project_type":"desktop-browser-chromium"}')
run_case "2_browser_no_binary" "$BROWSER_E2E_SCRIPT" "$PROJ" "gate-mechanical/e2e-browser.json" "FAIL" "1"

# ── Case 3: desktop-browser-chromium binary set, no journeys_dir → FAIL ─
PROJ=$(mk_project "3_browser_no_journeys_dir" "{\"project_type\":\"desktop-browser-chromium\",\"browser\":{\"binary_path\":\"$BROWSER_E2E_SCRIPT\",\"journeys_dir\":\".browser-journeys\"}}")
# binary_path points to the gate script itself (file exists) — journeys_dir absent triggers FAIL
run_case "3_browser_no_journeys_dir" "$BROWSER_E2E_SCRIPT" "$PROJ" "gate-mechanical/e2e-browser.json" "FAIL" "1"

# ── Case 4: desktop-browser-chromium journeys_dir empty → FAIL ──────
PROJ=$(mk_project "4_browser_empty_journeys" "{\"project_type\":\"desktop-browser-chromium\",\"browser\":{\"binary_path\":\"$BROWSER_E2E_SCRIPT\",\"journeys_dir\":\".browser-journeys\"}}")
mkdir -p "$PROJ/.browser-journeys"
# Empty dir — no journey files
run_case "4_browser_empty_journeys" "$BROWSER_E2E_SCRIPT" "$PROJ" "gate-mechanical/e2e-browser.json" "FAIL" "1"

# ── Case 5: frontend → wpt N/A ──────────────────────────────────────
PROJ=$(mk_project "5_wpt_frontend_na" '{"project_type":"frontend"}')
run_case "5_wpt_frontend_na" "$WPT_SCRIPT" "$PROJ" "gate-mechanical/browser-wpt.json" "N/A_PENDING_REVIEWER" "0"

# ── Case 6: desktop-browser-chromium wpt.enabled=false → FAIL (LAW-F6) ─
PROJ=$(mk_project "6_wpt_disabled_fail" '{"project_type":"desktop-browser-chromium","browser":{"wpt":{"enabled":false}}}')
run_case "6_wpt_disabled_fail" "$WPT_SCRIPT" "$PROJ" "gate-mechanical/browser-wpt.json" "FAIL" "1"

# ── Case 7: desktop-browser-chromium wpt.enabled=true empty subset → FAIL ─
PROJ=$(mk_project "7_wpt_empty_subset" '{"project_type":"desktop-browser-chromium","browser":{"wpt":{"enabled":true,"subset":[]}}}')
run_case "7_wpt_empty_subset" "$WPT_SCRIPT" "$PROJ" "gate-mechanical/browser-wpt.json" "FAIL" "1"

# ── Aggregate ──────────────────────────────────────────────────────
TOTAL=$(( ${#CASES_PASSED[@]} + ${#CASES_FAILED[@]} ))
jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson total "$TOTAL" \
  --argjson pass "${#CASES_PASSED[@]}" \
  --argjson fail "${#CASES_FAILED[@]}" \
  --argjson passed "$(printf '%s\n' "${CASES_PASSED[@]:-}" | jq -R . | jq -s 'map(select(length>0))')" \
  --argjson failed "$(printf '%s\n' "${CASES_FAILED[@]:-}" | jq -R . | jq -s 'map(select(length>0))')" \
  '{
    meta_gate: "browser-e2e-test",
    schema_version: "ubs-v8.7-meta",
    timestamp: $ts,
    cases_total: $total,
    cases_pass: $pass,
    cases_fail: $fail,
    cases_passed: $passed,
    cases_failed: $failed,
    verdict: (if $fail == 0 then "PASS" else "FAIL" end),
    interpretation: (if $fail == 0
      then "GATE-25-E2E-BROWSER + GATE-BROWSER-WPT correctly enforce LAW-F6 — v8.7 browser-layer invariant holds"
      else "Browser-layer gate regressed — one or more fixtures returned unexpected verdict"
    end)
  }' > "$SUMMARY"

log "summary: $SUMMARY"
jq -r '"cases pass=" + (.cases_pass|tostring) + " fail=" + (.cases_fail|tostring) + " verdict=" + .verdict' "$SUMMARY" >&2

if [[ ${#CASES_FAILED[@]} -gt 0 ]]; then
  log "FAILED cases:"
  for c in "${CASES_FAILED[@]}"; do log "  - $c"; done
  exit 1
fi
exit 0
