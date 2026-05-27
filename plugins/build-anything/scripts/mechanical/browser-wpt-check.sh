#!/usr/bin/env bash
# browser-wpt-check.sh — GATE-BROWSER-WPT (v8.7)
#
# Runs a declared subset of the Web Platform Tests (WPT) against the atom's
# browser binary. WPT is the W3C/WHATWG standards conformance suite. Every
# shipping browser (Chromium, Firefox, Safari) runs WPT in CI; v8.7 makes
# WPT a hard gate so a "we built a browser" atom cannot pass without
# standards conformance evidence.
#
# Inputs (from .build-anything.json):
#   project_type        (must match desktop-browser-*)
#   browser.wpt.enabled       (bool, default false — LAW-F6: false = FAIL for desktop-browser-*)
#   browser.wpt.runner_cmd    (default: $(which wpt) run --product=chrome --binary=$BIN $SUBSET)
#   browser.wpt.subset        (array of test paths, e.g. ["html/dom", "css/css-color"])
#   browser.wpt.threshold     (pass-rate float, default 0.95)
#   browser.binary_path       (reused from e2e-browser config)
#
# Rules (LAW-F6 no vacuous PASS):
#   - project_type NOT desktop-browser-* → N/A_PENDING_REVIEWER
#   - project_type ∈ desktop-browser-* AND wpt.enabled=false → FAIL
#   - wpt.subset empty → FAIL
#   - wpt.runner_cmd binary not found → FAIL with install hint
#   - vacuous run (0 tests executed) → FAIL
#   - pass-rate below threshold → FAIL
#
# Exit: 0 PASS or N/A, 1 FAIL, 2 preflight error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../backend/_common.sh"

atom_dir_from_args "$@"
EVIDENCE_LOCAL="$ATOM_DIR/gate-mechanical"
mkdir -p "$EVIDENCE_LOCAL"
OUT="$EVIDENCE_LOCAL/browser-wpt.json"

PROJECT_TYPE=$(cfg "project_type" "backend")
WPT_ENABLED=$(cfg "browser.wpt.enabled" "false")
BINARY_PATH=$(cfg "browser.binary_path" "")
RUNNER_CMD=$(cfg "browser.wpt.runner_cmd" "")
THRESHOLD=$(cfg "browser.wpt.threshold" "0.95")

# Read subset array (jq array slice)
SUBSET_JSON=$(jq -r '.browser.wpt.subset // [] | @json' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo '[]')
SUBSET_COUNT=$(echo "$SUBSET_JSON" | jq 'length')

emit_wpt_na() {
  jq -n --arg reason "$1" --arg ran_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{gate:"GATE-BROWSER-WPT", passed:null, verdict:"N/A_PENDING_REVIEWER",
      reason:$reason, review_required:true, ran_at:$ran_at}' > "$OUT"
  exit 0
}

emit_wpt_fail() {
  local reason="$1" details="${2:-}"
  [[ -z "$details" ]] && details='{}'
  jq -n --arg reason "$reason" --argjson evidence "$details" \
    --arg ran_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{gate:"GATE-BROWSER-WPT", passed:false, verdict:"FAIL",
      reason:$reason, evidence:$evidence, ran_at:$ran_at}' > "$OUT"
  exit 1
}

emit_wpt_pass() {
  local details="$1"
  jq -n --argjson evidence "$details" --arg ran_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{gate:"GATE-BROWSER-WPT", passed:true, verdict:"PASS",
      evidence:$evidence, ran_at:$ran_at}' > "$OUT"
  exit 0
}

# ── Trigger check ──────────────────────────────────────────────────
case "$PROJECT_TYPE" in
  desktop-browser-*) : ;;
  *)
    emit_wpt_na "project_type=$PROJECT_TYPE — WPT conformance applies to desktop-browser-* only"
    ;;
esac

# ── LAW-F6: declared-but-skipped FAIL ──────────────────────────────
if [[ "$WPT_ENABLED" != "true" ]]; then
  emit_wpt_fail "project_type=$PROJECT_TYPE requires browser.wpt.enabled=true; LAW-F6 forbids skipping standards conformance for a browser" \
    '{"hint": "Add { \"browser\": { \"wpt\": { \"enabled\": true, \"subset\": [\"html/dom\", \"css/css-color\"], \"threshold\": 0.95 } } } to .build-anything.json"}'
fi

# ── Subset present ─────────────────────────────────────────────────
if [[ "$SUBSET_COUNT" -eq 0 ]]; then
  emit_wpt_fail "browser.wpt.subset is empty — declare at least one WPT path (e.g. \"html/dom\")" \
    '{"hint": "Browse https://wpt.fyi for paths; pin a stable subset rather than running all 1.8M tests"}'
fi

# ── Binary path present ────────────────────────────────────────────
if [[ -z "$BINARY_PATH" ]]; then
  emit_wpt_fail "browser.binary_path is required for WPT runner; same value used by e2e-browser" '{}'
fi
[[ "$BINARY_PATH" = /* ]] || BINARY_PATH="$PROJECT_ROOT/$BINARY_PATH"

if [[ ! -e "$BINARY_PATH" ]]; then
  emit_wpt_fail "browser.binary_path not found at $BINARY_PATH" '{}'
fi

# ── Build / verify runner command ──────────────────────────────────
# Default: assume `wpt` is on PATH (cloned via `git clone https://github.com/web-platform-tests/wpt`).
# The wpt binary is a Python wrapper that drives the suite.
if [[ -z "$RUNNER_CMD" ]]; then
  if ! command -v wpt >/dev/null 2>&1; then
    emit_wpt_fail "wpt binary not on PATH; declare browser.wpt.runner_cmd or install wpt" \
      '{"install": "git clone https://github.com/web-platform-tests/wpt && export PATH=$PWD/wpt:$PATH", "docs": "https://web-platform-tests.org/running-tests/from-local-system.html"}'
  fi
  SUBSET_ARGS=$(echo "$SUBSET_JSON" | jq -r '.[]' | tr '\n' ' ')
  RUNNER_CMD="wpt run --product=chrome --binary=\"$BINARY_PATH\" --log-wptreport=- $SUBSET_ARGS"
fi

run_log=$(mktemp)
echo "[browser-wpt] running: $RUNNER_CMD" >&2
set +e
(cd "$PROJECT_ROOT" && eval "$RUNNER_CMD") >"$run_log" 2>&1
rc=$?
set -e

# ── Parse WPT report ───────────────────────────────────────────────
# wpt run --log-wptreport emits JSON-lines with per-test results:
#   {"action": "test_end", "test": "...", "status": "OK|PASS|FAIL|TIMEOUT|ERROR", ...}
# Aggregate by status.
test_total=$(grep -cE '"action":\s*"test_end"' "$run_log" 2>/dev/null || echo 0)
test_pass=$(grep -cE '"status":\s*"(OK|PASS)"' "$run_log" 2>/dev/null || echo 0)
test_fail=$(grep -cE '"status":\s*"(FAIL|TIMEOUT|ERROR|CRASH)"' "$run_log" 2>/dev/null || echo 0)

test_total=${test_total//[^0-9]/}
test_pass=${test_pass//[^0-9]/}
test_fail=${test_fail//[^0-9]/}
: "${test_total:=0}"
: "${test_pass:=0}"
: "${test_fail:=0}"

# Vacuous-run guard
if [[ "$test_total" -eq 0 ]]; then
  details=$(jq -n \
    --argjson rc "$rc" \
    --arg log "$(tail -50 "$run_log" 2>/dev/null | jq -Rs . | sed 's/^"//;s/"$//')" \
    '{exit_code: $rc, tail_log: $log, tests_executed: 0}')
  rm -f "$run_log"
  emit_wpt_fail "wpt run reported 0 tests executed (vacuous — subset may not match installed WPT corpus)" "$details"
fi

# Pass-rate check
rate=$(awk -v p="$test_pass" -v t="$test_total" 'BEGIN { if (t == 0) print 0; else printf "%.4f", p / t }')

details=$(jq -n \
  --arg pt "$PROJECT_TYPE" \
  --arg bin "$BINARY_PATH" \
  --argjson subset "$SUBSET_JSON" \
  --arg threshold "$THRESHOLD" \
  --arg rate "$rate" \
  --argjson total "$test_total" \
  --argjson pass "$test_pass" \
  --argjson fail "$test_fail" \
  --argjson rc "$rc" \
  '{project_type: $pt, binary_path: $bin, subset: $subset, threshold: ($threshold | tonumber), pass_rate: ($rate | tonumber), tests_total: $total, tests_passed: $pass, tests_failed: $fail, exit_code: $rc}')

rm -f "$run_log"

# Compare pass-rate to threshold
below=$(awk -v r="$rate" -v t="$THRESHOLD" 'BEGIN { print (r < t) ? 1 : 0 }')

if [[ "$below" == "1" ]]; then
  emit_wpt_fail "WPT pass-rate $rate below threshold $THRESHOLD ($test_pass/$test_total)" "$details"
fi

emit_wpt_pass "$details"
