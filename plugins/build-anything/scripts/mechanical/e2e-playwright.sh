#!/usr/bin/env bash
# e2e-playwright.sh — GATE-25-E2E
#
# Enforces Playwright E2E coverage for declared user journeys.
#
# Inputs (from .build-anything.json):
#   e2e.enabled         (bool)
#   e2e.tool            ("playwright" | "cypress" — only playwright handled here)
#   e2e.root            (default "tests/e2e" or "e2e")
#   e2e.run_cmd         (default "npx playwright test --reporter=line")
#   e2e.min_per_journey (int, default 1)
#   e2e.journeys[]      [{name, must_visit: ["/path", ...]}, ...]
#
# Rules:
#   F6: e2e.enabled=false AND project_type ∈ {frontend, mixed} → N/A_PENDING_REVIEWER
#   F6: e2e.enabled=true but 0 test files found → FAIL (not vacuous PASS)
#   F6: tests exist but all skipped → FAIL
#   PASS: each journey has >= min_per_journey tests AND `npx playwright test` exits 0

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../backend/_common.sh"

atom_dir_from_args "$@"
EVIDENCE_LOCAL="$ATOM_DIR/gate-mechanical"
mkdir -p "$EVIDENCE_LOCAL"
OUT="$EVIDENCE_LOCAL/e2e-playwright.json"

E2E_ENABLED=$(cfg "e2e.enabled" "false")
PROJECT_TYPE=$(cfg "project_type" "backend")

emit_e2e_na() {
  cat > "$OUT" <<JSON
{
  "gate": "GATE-25-E2E",
  "passed": null,
  "verdict": "N/A_PENDING_REVIEWER",
  "reason": "$1",
  "review_required": true,
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

emit_e2e_fail() {
  local reason="$1" details="${2:-{}}"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-25-E2E",
  "passed": false,
  "verdict": "FAIL",
  "reason": "$reason",
  "evidence": $details,
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 1
}

emit_e2e_pass() {
  local details="$1"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-25-E2E",
  "passed": true,
  "verdict": "PASS",
  "evidence": $details,
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

# ── Trigger check ──────────────────────────────────────────────────
if [[ "$E2E_ENABLED" != "true" ]]; then
  if [[ "$PROJECT_TYPE" == "frontend" || "$PROJECT_TYPE" == "mixed" ]]; then
    emit_e2e_na "e2e.enabled=false but project has UI (project_type=$PROJECT_TYPE) — reviewer must justify"
  else
    emit_e2e_na "no UI surface (project_type=$PROJECT_TYPE)"
  fi
fi

E2E_TOOL=$(cfg "e2e.tool" "playwright")
if [[ "$E2E_TOOL" != "playwright" ]]; then
  emit_e2e_na "tool $E2E_TOOL not supported by this runner; reviewer must verify"
fi

E2E_ROOT=$(cfg "e2e.root" "tests/e2e")
[[ "$E2E_ROOT" = /* ]] || E2E_ROOT="$PROJECT_ROOT/$E2E_ROOT"

if [[ ! -d "$E2E_ROOT" ]]; then
  emit_e2e_fail "e2e.enabled=true but root not found: $E2E_ROOT" '{}'
fi

# ── Count tests per journey ────────────────────────────────────────
MIN_PER=$(cfg "e2e.min_per_journey" "1")
JOURNEYS=$(jq -c '.e2e.journeys // []' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo "[]")

# Discover test files
TEST_FILES=$(find "$E2E_ROOT" -type f \( -name '*.spec.ts' -o -name '*.spec.js' -o -name '*.test.ts' -o -name '*.e2e.ts' \) 2>/dev/null)
TOTAL_FILES=$(echo "$TEST_FILES" | grep -c . || echo 0)

if [[ "$TOTAL_FILES" -eq 0 ]]; then
  emit_e2e_fail "no Playwright spec files under $E2E_ROOT" '{"files_found":0}'
fi

# Per-journey enforcement
JOURNEY_COUNT=$(echo "$JOURNEYS" | jq 'length')
COVERAGE_REPORT='[]'
INSUFFICIENT=()
for i in $(seq 0 $((JOURNEY_COUNT - 1))); do
  jname=$(echo "$JOURNEYS" | jq -r ".[$i].name")
  jname_lc=$(echo "$jname" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  # Count files whose name contains the journey slug OR whose content mentions the name
  matched=$(echo "$TEST_FILES" | grep -ic "$jname_lc" || true)
  if [[ "$matched" -lt "$MIN_PER" ]]; then
    # try content search
    content_match=0
    while IFS= read -r tf; do
      if grep -qi "$jname" "$tf" 2>/dev/null; then content_match=$((content_match+1)); fi
    done <<< "$TEST_FILES"
    matched=$((matched > content_match ? matched : content_match))
  fi
  COVERAGE_REPORT=$(echo "$COVERAGE_REPORT" | jq --arg n "$jname" --argjson c "$matched" '. + [{journey: $n, tests: $c}]')
  if [[ "$matched" -lt "$MIN_PER" ]]; then
    INSUFFICIENT+=("$jname")
  fi
done

if [[ ${#INSUFFICIENT[@]} -gt 0 ]]; then
  missing_json=$(printf '%s\n' "${INSUFFICIENT[@]}" | jq -R . | jq -s .)
  emit_e2e_fail "journeys without enough E2E tests (min=$MIN_PER per journey)" \
    "{\"insufficient_journeys\": $missing_json, \"coverage\": $COVERAGE_REPORT}"
fi

# ── Actually run Playwright ────────────────────────────────────────
RUN_CMD=$(cfg "e2e.run_cmd" "npx playwright test --reporter=line")
RUN_LOG="$EVIDENCE_LOCAL/e2e-playwright.log"

log_step e2e "running: $RUN_CMD"
set +e
( cd "$PROJECT_ROOT" && eval "$RUN_CMD" ) > "$RUN_LOG" 2>&1
RC=$?
set -e

# Parse summary line
SUMMARY_LINE=$(grep -E '([0-9]+ passed|failed|skipped)' "$RUN_LOG" | tail -1 || echo "")
PASSED=$(echo "$SUMMARY_LINE" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' || echo 0)
FAILED=$(echo "$SUMMARY_LINE" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' || echo 0)
SKIPPED=$(echo "$SUMMARY_LINE" | grep -oE '[0-9]+ skipped' | grep -oE '[0-9]+' || echo 0)

DETAILS=$(jq -n \
  --argjson rc "$RC" \
  --argjson passed "${PASSED:-0}" \
  --argjson failed "${FAILED:-0}" \
  --argjson skipped "${SKIPPED:-0}" \
  --argjson total_files "$TOTAL_FILES" \
  --argjson coverage "$COVERAGE_REPORT" \
  --arg cmd "$RUN_CMD" \
  --arg log "$RUN_LOG" \
  '{exit_code:$rc, tests_passed:$passed, tests_failed:$failed, tests_skipped:$skipped, total_spec_files:$total_files, per_journey_coverage:$coverage, run_cmd:$cmd, log_path:$log}')

# Vacuous-PASS guard: passed=0 AND skipped=0 means tool didn't actually run anything useful
if [[ "$RC" -eq 0 && "$PASSED" -eq 0 && "$FAILED" -eq 0 ]]; then
  emit_e2e_fail "Playwright ran but reported 0 passed and 0 failed — vacuous run" "$DETAILS"
fi

if [[ "$RC" -ne 0 || "$FAILED" -gt 0 ]]; then
  emit_e2e_fail "Playwright reported failures or non-zero exit" "$DETAILS"
fi

emit_e2e_pass "$DETAILS"
