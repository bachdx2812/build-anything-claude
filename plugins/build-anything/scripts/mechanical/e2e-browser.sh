#!/usr/bin/env bash
# e2e-browser.sh — GATE-25-E2E-BROWSER (v8.7)
#
# Desktop-browser-equivalent of e2e-playwright.sh / e2e-maestro.sh.
# Drives the browser binary the atom is building, via either CDP (Chrome
# DevTools Protocol) or WebDriver. Asserts declared journeys pass.
#
# Inputs (from .build-anything.json):
#   project_type           (must match desktop-browser-*)
#   browser.binary_path    (absolute path to built browser binary)
#   browser.driver         ("cdp" | "webdriver" — default "cdp")
#   browser.journeys_dir   (default ".browser-journeys/" — *.json or *.yaml files)
#   browser.run_cmd        (default: $SCRIPT_DIR/_browser-cdp-runner.sh $BINARY $JOURNEYS_DIR)
#   browser.startup_timeout_s (default 30)
#
# Journey shape (JSON):
#   { "name": "load-homepage", "url": "https://example.com",
#     "assertions": [ { "type": "title_matches", "value": "Example" } ] }
#
# Rules (mirroring v8.5.1 Playwright + v8.6 Maestro mandates at LAW-F6 layer):
#   - project_type ∈ desktop-browser-* AND browser.binary_path empty → FAIL
#   - project_type NOT desktop-browser-* → N/A_PENDING_REVIEWER (Playwright/Maestro cover web/mobile)
#   - journeys_dir absent OR contains 0 journey files → FAIL
#   - vacuous run (0 passed AND 0 failed) → FAIL
#   - any journey failed OR runner rc != 0 → FAIL
#
# Exit: 0 PASS or N/A, 1 FAIL, 2 preflight error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../backend/_common.sh"

atom_dir_from_args "$@"
EVIDENCE_LOCAL="$ATOM_DIR/gate-mechanical"
mkdir -p "$EVIDENCE_LOCAL"
OUT="$EVIDENCE_LOCAL/e2e-browser.json"

PROJECT_TYPE=$(cfg "project_type" "backend")
BINARY_PATH=$(cfg "browser.binary_path" "")
DRIVER=$(cfg "browser.driver" "cdp")
JOURNEYS_DIR=$(cfg "browser.journeys_dir" ".browser-journeys")
RUN_CMD=$(cfg "browser.run_cmd" "")
STARTUP_TIMEOUT=$(cfg "browser.startup_timeout_s" "30")

[[ "$JOURNEYS_DIR" = /* ]] || JOURNEYS_DIR="$PROJECT_ROOT/$JOURNEYS_DIR"

emit_browser_na() {
  jq -n --arg reason "$1" --arg ran_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{gate:"GATE-25-E2E-BROWSER", passed:null, verdict:"N/A_PENDING_REVIEWER",
      reason:$reason, review_required:true, ran_at:$ran_at}' > "$OUT"
  exit 0
}

emit_browser_fail() {
  local reason="$1" details="${2:-}"
  [[ -z "$details" ]] && details='{}'
  jq -n --arg reason "$reason" --argjson evidence "$details" \
    --arg ran_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{gate:"GATE-25-E2E-BROWSER", passed:false, verdict:"FAIL",
      reason:$reason, evidence:$evidence, ran_at:$ran_at}' > "$OUT"
  exit 1
}

emit_browser_pass() {
  local details="$1"
  jq -n --argjson evidence "$details" --arg ran_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{gate:"GATE-25-E2E-BROWSER", passed:true, verdict:"PASS",
      evidence:$evidence, ran_at:$ran_at}' > "$OUT"
  exit 0
}

# ── Trigger check: only for desktop-browser-* project_type ──────────
case "$PROJECT_TYPE" in
  desktop-browser-*) : ;;
  *)
    emit_browser_na "project_type=$PROJECT_TYPE — e2e-browser handles desktop-browser-* only"
    ;;
esac

# ── LAW-F6: binary_path required ────────────────────────────────────
if [[ -z "$BINARY_PATH" ]]; then
  emit_browser_fail "browser.binary_path is required for project_type=$PROJECT_TYPE; LAW-F6 forbids skipping browser E2E" \
    '{"hint": "Add { \"browser\": { \"binary_path\": \"/path/to/build/browser\", \"journeys_dir\": \".browser-journeys\", \"driver\": \"cdp\" } } to .build-anything.json"}'
fi

# Resolve relative binary path against project root
[[ "$BINARY_PATH" = /* ]] || BINARY_PATH="$PROJECT_ROOT/$BINARY_PATH"

if [[ ! -e "$BINARY_PATH" ]]; then
  emit_browser_fail "browser.binary_path not found at $BINARY_PATH" \
    "{\"hint\": \"Build the browser first (e.g. ninja -C out/Default chrome); then re-run\"}"
fi

# ── Driver validation ──────────────────────────────────────────────
case "$DRIVER" in
  cdp|webdriver) : ;;
  *)
    emit_browser_fail "browser.driver=$DRIVER not supported; expected cdp|webdriver" \
      "{\"got\": \"$DRIVER\"}"
    ;;
esac

# ── Journeys directory check ───────────────────────────────────────
if [[ ! -d "$JOURNEYS_DIR" ]]; then
  emit_browser_fail "browser.journeys_dir not found at $JOURNEYS_DIR" \
    "{\"expected\": \"$JOURNEYS_DIR\", \"hint\": \"Author journey *.json or *.yaml files under .browser-journeys/\"}"
fi

journey_count=$(find "$JOURNEYS_DIR" -type f \( -name "*.json" -o -name "*.yaml" -o -name "*.yml" \) 2>/dev/null | wc -l | tr -d ' ')
if [[ "$journey_count" -eq 0 ]]; then
  emit_browser_fail "no browser journey files found under $JOURNEYS_DIR (looking for *.json/*.yaml/*.yml)" \
    "{\"journeys_dir\": \"$JOURNEYS_DIR\", \"count\": 0}"
fi

# ── Build run command ──────────────────────────────────────────────
# Default runner: walk journeys_dir, launch binary with CDP/WebDriver port,
# execute each journey via curl + jq against the protocol, count pass/fail.
# Atoms can override with browser.run_cmd to plug their own harness.
if [[ -z "$RUN_CMD" ]]; then
  RUN_CMD="$SCRIPT_DIR/_browser-cdp-runner.sh \"$BINARY_PATH\" \"$JOURNEYS_DIR\" \"$DRIVER\" \"$STARTUP_TIMEOUT\""
fi

run_log=$(mktemp)
echo "[e2e-browser] running: $RUN_CMD" >&2
set +e
(cd "$PROJECT_ROOT" && eval "$RUN_CMD") >"$run_log" 2>&1
rc=$?
set -e

# ── Parse runner output ────────────────────────────────────────────
# Runner is expected to emit lines:
#   "[Passed] <journey-name>"
#   "[Failed] <journey-name> <reason>"
# Summary line: "X passed, Y failed"
passed_count=$(grep -cE '\[Passed\]' "$run_log" 2>/dev/null || echo 0)
failed_count=$(grep -cE '\[Failed\]' "$run_log" 2>/dev/null || echo 0)

passed_count=${passed_count//[^0-9]/}
failed_count=${failed_count//[^0-9]/}
: "${passed_count:=0}"
: "${failed_count:=0}"

details=$(jq -n \
  --arg pt "$PROJECT_TYPE" \
  --arg bin "$BINARY_PATH" \
  --arg drv "$DRIVER" \
  --arg jd "$JOURNEYS_DIR" \
  --arg log "$(tail -50 "$run_log" 2>/dev/null | jq -Rs . | sed 's/^"//;s/"$//')" \
  --argjson jc "$journey_count" \
  --argjson passed "$passed_count" \
  --argjson failed "$failed_count" \
  --argjson rc "$rc" \
  '{project_type: $pt, binary_path: $bin, driver: $drv, journeys_dir: $jd, journey_count: $jc, passed: $passed, failed: $failed, exit_code: $rc, tail_log: $log}')

rm -f "$run_log"

# Vacuous-run guard (LAW-F6)
if [[ "$rc" -eq 0 && "$passed_count" -eq 0 && "$failed_count" -eq 0 ]]; then
  emit_browser_fail "e2e-browser reported 0 passed AND 0 failed (vacuous run — likely no journeys executed)" "$details"
fi

if [[ "$rc" -ne 0 || "$failed_count" -gt 0 ]]; then
  emit_browser_fail "e2e-browser: rc=$rc passed=$passed_count failed=$failed_count" "$details"
fi

if [[ "$passed_count" -eq 0 ]]; then
  emit_browser_fail "e2e-browser: 0 journeys passed (rc=$rc; check tail_log)" "$details"
fi

emit_browser_pass "$details"
