#!/usr/bin/env bash
# compensating-coverage.sh — GATE-COMP-COV (v8.7.1)
#
# Purpose: catch atoms whose project_type has NO specialized behavioral gate
# (library / cli / sdk / daemon / worker / firmware / kernel / game / ml-model
# / data-pipeline / extension / plugin / dsl / ...). Without a safety net,
# such atoms pass with a single stub test because GATE-25-E2E (Playwright),
# GATE-25-E2E-MOBILE (Maestro), and GATE-25-E2E-BROWSER (CDP) all N/A out.
#
# Compensating-coverage law: when no behavioral path exists, the atom MUST
# declare WHY, run a coverage-producing command, and meet RAISED thresholds
# (line ≥ 90, branch ≥ 85 by default — above the backend default 80/70).
#
# Trigger:
#   - project_type ∉ {frontend, mixed, backend, mobile-*, desktop-browser-*}
#   - OR compensating_coverage.enabled = true
#
# LAW-F6: never silent PASS. Empty trigger → N/A_PENDING_REVIEWER. Triggered
# but missing config / failing cmd / below threshold / vacuous (0% / 0%) → FAIL.

set -uo pipefail

ATOM_DIR=""
PROJECT_ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --atom-dir)     ATOM_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done
: "${ATOM_DIR:?--atom-dir required}"
: "${PROJECT_ROOT:?--project-root required}"

OUT_DIR="$ATOM_DIR/gate-mechanical"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/compensating-coverage.json"

log() { echo "[$(date -u +%H:%M:%S)] [comp-cov] $*" >&2; }

# ── Config reader (shallow path syntax: a.b.c) ─────────────────────
cfg() {
  local key="$1" default="${2:-}"
  local f="$PROJECT_ROOT/.build-anything.json"
  if [[ -f "$f" ]]; then
    jq -r --arg k "$key" --arg d "$default" \
      '. as $r | ($k | split(".")) as $p | reduce $p[] as $s ($r; .[$s] // null) // $d' "$f"
  else
    echo "$default"
  fi
}

PROJECT_TYPE=$(cfg "project_type" "backend")
ENABLED=$(cfg "compensating_coverage.enabled" "false")
REASON=$(cfg "compensating_coverage.reason" "")
COVERAGE_CMD=$(cfg "compensating_coverage.coverage_cmd" "")
REPORT_PATH=$(cfg "compensating_coverage.coverage_report_path" "")
REPORT_FORMAT=$(cfg "compensating_coverage.coverage_report_format" "istanbul")
THRESHOLD_LINE=$(cfg "compensating_coverage.thresholds.line" "90")
THRESHOLD_BRANCH=$(cfg "compensating_coverage.thresholds.branch" "85")

# ── Emit helpers (jq-safe quoting — same pattern as v8.7 fix) ──────
emit_na() {
  jq -n --arg reason "$1" --arg ran_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{gate:"GATE-COMP-COV", passed:null, verdict:"N/A_PENDING_REVIEWER",
      reason:$reason, review_required:true, confidence:0, ambiguities:[$reason],
      schema_version:"ubs-v8.7.1-comp-cov", ran_at:$ran_at}' > "$OUT"
  exit 0
}

emit_fail() {
  local reason="$1" details="${2:-}"
  [[ -z "$details" ]] && details='{}'
  jq -n --arg reason "$reason" --argjson evidence "$details" \
    --arg ran_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{gate:"GATE-COMP-COV", passed:false, verdict:"FAIL",
      reason:$reason, evidence:$evidence, confidence:100, ambiguities:[],
      schema_version:"ubs-v8.7.1-comp-cov", ran_at:$ran_at}' > "$OUT"
  exit 1
}

emit_pass() {
  local details="$1"
  jq -n --argjson evidence "$details" --arg ran_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{gate:"GATE-COMP-COV", passed:true, verdict:"PASS",
      evidence:$evidence, confidence:100, ambiguities:[],
      schema_version:"ubs-v8.7.1-comp-cov", ran_at:$ran_at}' > "$OUT"
  exit 0
}

# ── Trigger detection ──────────────────────────────────────────────
# Specialized-coverage set: behavioral gates exist for these.
case "$PROJECT_TYPE" in
  frontend|mixed|backend|mobile-*|desktop-browser-*)
    HAS_SPECIALIZED=1 ;;
  *)
    HAS_SPECIALIZED=0 ;;
esac

if [[ "$HAS_SPECIALIZED" -eq 1 && "$ENABLED" != "true" ]]; then
  emit_na "project_type=$PROJECT_TYPE has a specialized behavioral gate (playwright/maestro/browser-cdp); compensating-coverage opt-in not declared"
fi

# ── Triggered: enforce config presence ─────────────────────────────
if [[ -z "$REASON" ]]; then
  emit_fail "compensating_coverage.reason is empty — agent MUST justify why no behavioral testing path applies for project_type=$PROJECT_TYPE (LAW-F6)" \
    "{\"hint\": \"Add { \\\"compensating_coverage\\\": { \\\"enabled\\\": true, \\\"reason\\\": \\\"...why no E2E...\\\", \\\"coverage_cmd\\\": \\\"...\\\", \\\"coverage_report_path\\\": \\\"...\\\", \\\"coverage_report_format\\\": \\\"istanbul|simple|text\\\" } } to .build-anything.json\"}"
fi

if [[ -z "$COVERAGE_CMD" ]]; then
  emit_fail "compensating_coverage.coverage_cmd is empty — declare the command that produces coverage data" '{}'
fi

if [[ -z "$REPORT_PATH" ]]; then
  emit_fail "compensating_coverage.coverage_report_path is empty — declare where the coverage report will be written" '{}'
fi

case "$REPORT_FORMAT" in
  istanbul|simple|text) : ;;
  *)
    emit_fail "compensating_coverage.coverage_report_format=$REPORT_FORMAT not supported; expected istanbul|simple|text" '{}'
    ;;
esac

# ── Clamp thresholds (atom can raise, cannot lower below defaults) ─
if [[ "$THRESHOLD_LINE" -lt 90 ]]; then
  log "atom requested line threshold $THRESHOLD_LINE < 90; clamping to 90 (v8.7.1 floor)"
  THRESHOLD_LINE=90
fi
if [[ "$THRESHOLD_BRANCH" -lt 85 ]]; then
  log "atom requested branch threshold $THRESHOLD_BRANCH < 85; clamping to 85 (v8.7.1 floor)"
  THRESHOLD_BRANCH=85
fi

# Resolve report path against project root if relative
[[ "$REPORT_PATH" = /* ]] || REPORT_PATH="$PROJECT_ROOT/$REPORT_PATH"

# ── Execute coverage command ───────────────────────────────────────
CMD_LOG="$OUT_DIR/comp-cov-cmd.log"
log "executing: $COVERAGE_CMD (cwd=$PROJECT_ROOT)"
(cd "$PROJECT_ROOT" && eval "$COVERAGE_CMD") >"$CMD_LOG" 2>&1
CMD_RC=$?
if [[ "$CMD_RC" -ne 0 ]]; then
  emit_fail "compensating_coverage.coverage_cmd exited rc=$CMD_RC" \
    "{\"cmd\": $(echo "$COVERAGE_CMD" | jq -Rs .), \"log\": $(tail -50 "$CMD_LOG" 2>/dev/null | jq -Rs .)}"
fi

if [[ ! -f "$REPORT_PATH" ]]; then
  emit_fail "coverage_report_path not found at $REPORT_PATH after cmd ran" \
    "{\"cmd\": $(echo "$COVERAGE_CMD" | jq -Rs .), \"expected_path\": $(echo "$REPORT_PATH" | jq -Rs .)}"
fi

# ── Parse coverage by format ───────────────────────────────────────
LINE_PCT=0
BRANCH_PCT=0

case "$REPORT_FORMAT" in
  istanbul)
    # coverage-summary.json: { total: { lines: { pct: N }, branches: { pct: N } } }
    LINE_PCT=$(jq -r '.total.lines.pct // 0' "$REPORT_PATH" 2>/dev/null || echo 0)
    BRANCH_PCT=$(jq -r '.total.branches.pct // 0' "$REPORT_PATH" 2>/dev/null || echo 0)
    ;;
  simple)
    # { "line": N, "branch": N }
    LINE_PCT=$(jq -r '.line // 0' "$REPORT_PATH" 2>/dev/null || echo 0)
    BRANCH_PCT=$(jq -r '.branch // 0' "$REPORT_PATH" 2>/dev/null || echo 0)
    ;;
  text)
    # Grep for "lines ... N%" / "branches ... N%" patterns (e.g. Go test output, pytest --cov stdout)
    LINE_PCT=$(grep -oE '[Ll]ines?[^0-9]*[0-9]+(\.[0-9]+)?%' "$REPORT_PATH" 2>/dev/null | head -1 | grep -oE '[0-9]+(\.[0-9]+)?' | head -1 || echo 0)
    BRANCH_PCT=$(grep -oE '[Bb]ranch(es)?[^0-9]*[0-9]+(\.[0-9]+)?%' "$REPORT_PATH" 2>/dev/null | head -1 | grep -oE '[0-9]+(\.[0-9]+)?' | head -1 || echo 0)
    LINE_PCT=${LINE_PCT:-0}
    BRANCH_PCT=${BRANCH_PCT:-0}
    ;;
esac

# Truncate to integer for comparison (bash arithmetic doesn't do floats)
LINE_INT=${LINE_PCT%.*}
BRANCH_INT=${BRANCH_PCT%.*}
LINE_INT=${LINE_INT:-0}
BRANCH_INT=${BRANCH_INT:-0}

log "parsed: line=$LINE_PCT% branch=$BRANCH_PCT% (thresholds: line≥$THRESHOLD_LINE, branch≥$THRESHOLD_BRANCH)"

# ── Vacuous guard: both zero = no tests actually ran ───────────────
if [[ "$LINE_INT" -eq 0 && "$BRANCH_INT" -eq 0 ]]; then
  emit_fail "vacuous coverage — both line=0% and branch=0%; the coverage command ran but no test execution was recorded" \
    "{\"line_pct\": $LINE_PCT, \"branch_pct\": $BRANCH_PCT, \"report_path\": $(echo "$REPORT_PATH" | jq -Rs .)}"
fi

# ── Threshold check ────────────────────────────────────────────────
FAILED_THRESHOLDS=()
if [[ "$LINE_INT" -lt "$THRESHOLD_LINE" ]]; then
  FAILED_THRESHOLDS+=("line=$LINE_PCT% < threshold=$THRESHOLD_LINE%")
fi
if [[ "$BRANCH_INT" -lt "$THRESHOLD_BRANCH" ]]; then
  FAILED_THRESHOLDS+=("branch=$BRANCH_PCT% < threshold=$THRESHOLD_BRANCH%")
fi

if [[ ${#FAILED_THRESHOLDS[@]} -gt 0 ]]; then
  DETAILS=$(jq -n \
    --arg line "$LINE_PCT" --arg branch "$BRANCH_PCT" \
    --argjson line_thr "$THRESHOLD_LINE" --argjson branch_thr "$THRESHOLD_BRANCH" \
    --argjson failed "$(printf '%s\n' "${FAILED_THRESHOLDS[@]}" | jq -R . | jq -s .)" \
    '{line_pct:$line, branch_pct:$branch, line_threshold:$line_thr, branch_threshold:$branch_thr, failed:$failed}')
  emit_fail "compensating coverage below required threshold" "$DETAILS"
fi

# ── Pass ───────────────────────────────────────────────────────────
DETAILS=$(jq -n \
  --arg line "$LINE_PCT" --arg branch "$BRANCH_PCT" \
  --argjson line_thr "$THRESHOLD_LINE" --argjson branch_thr "$THRESHOLD_BRANCH" \
  --arg project_type "$PROJECT_TYPE" --arg reason "$REASON" \
  '{project_type:$project_type, reason:$reason, line_pct:$line, branch_pct:$branch, line_threshold:$line_thr, branch_threshold:$branch_thr}')
log "PASS: line=$LINE_PCT% branch=$BRANCH_PCT%"
emit_pass "$DETAILS"
