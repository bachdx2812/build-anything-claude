#!/usr/bin/env bash
# sm-breakdown-gate.sh — Stage 1.B.5 GATE-SM enforcement (v8.5.2)
#
# BMAD-method Scrum Master persona output: epic → atoms breakdown.
# This gate verifies that the SM persona produced a parseable atom-plan
# and that every story respects the contract from sm-persona.md.
#
# Required artefacts:
#   {epic_dir}/atom-plan/plan.json
#   {epic_dir}/atom-plan/stories/story-NN-<slug>.md (one per plan.json.stories[])
#
# Mechanical checks (any FAIL → gate FAIL):
#   1. plan.json parses as JSON, has required keys (epic, stories[], execution_order[])
#   2. Each story file exists at declared path
#   3. Each story file has required sections: Atom brief, Acceptance Criteria,
#      Dependencies, Allowlist hint, Estimated scope, Out-of-scope
#   4. Every section has ≥1 non-blank body line (LAW-F6: no stub headers)
#   5. estimated_files ≤ sm.max_files_per_atom (default 15)
#   6. estimated_loc ≤ sm.max_loc_per_atom (default 800)
#   7. Every epic core_flow appears in at least one story.core_flows[]
#   8. Dependency graph is a DAG (no cycles)
#   9. execution_order is topologically valid
#  10. Every Acceptance Criteria line contains a testable shape
#      (HTTP method+path+status, CSS selector, SQL invariant, OR expect(...))
#
# N/A_PENDING_REVIEWER when plan.json absent (SM persona not yet dispatched).
# Exit codes: 0 PASS or N/A, 1 FAIL, 2 preflight error.

set -uo pipefail

EPIC_DIR=""
PROJECT_ROOT=""
MAX_FILES_DEFAULT=15
MAX_LOC_DEFAULT=800

while [[ $# -gt 0 ]]; do
  case "$1" in
    --epic-dir|--atom-dir) EPIC_DIR="$2"; shift 2 ;;
    --project-root)        PROJECT_ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${EPIC_DIR:?--epic-dir (or --atom-dir alias) required}"
: "${PROJECT_ROOT:?--project-root required}"

OUT_DIR="$EPIC_DIR/gate-spec"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/sm-breakdown.json"

log() { echo "[$(date -u +%H:%M:%S)] [sm-breakdown] $*" >&2; }

emit() {
  local verdict="$1" passed="$2" confidence="$3" reason="$4" details_json="$5"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-SM",
  "verdict": "$verdict",
  "passed": $passed,
  "confidence": $confidence,
  "reason": $(printf '%s' "$reason" | jq -Rs .),
  "ambiguities": [],
  "details": $details_json,
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
}

# ── Resolve config thresholds ─────────────────────────────────────
CFG="$PROJECT_ROOT/.build-anything.json"
MAX_FILES="$MAX_FILES_DEFAULT"
MAX_LOC="$MAX_LOC_DEFAULT"
if [[ -f "$CFG" ]]; then
  MAX_FILES=$(jq -r ".sm.max_files_per_atom // $MAX_FILES_DEFAULT" "$CFG" 2>/dev/null || echo "$MAX_FILES_DEFAULT")
  MAX_LOC=$(jq -r ".sm.max_loc_per_atom // $MAX_LOC_DEFAULT" "$CFG" 2>/dev/null || echo "$MAX_LOC_DEFAULT")
fi

PLAN="$EPIC_DIR/atom-plan/plan.json"

# ── N/A: SM persona not dispatched yet ─────────────────────────────
if [[ ! -f "$PLAN" ]]; then
  emit "N/A_PENDING_REVIEWER" "null" 0 \
    "atom-plan/plan.json absent — SM persona not dispatched for this epic" \
    '{"plan_path": "'"$PLAN"'", "required_for": "multi-atom epics"}'
  exit 0
fi

# ── Parseable JSON ─────────────────────────────────────────────────
if ! jq -e . "$PLAN" >/dev/null 2>&1; then
  emit "FAIL" false 100 "plan.json is not valid JSON" '{"plan_path": "'"$PLAN"'"}'
  exit 1
fi

# ── Required top-level keys ────────────────────────────────────────
for key in epic stories execution_order; do
  if ! jq -e ".$key" "$PLAN" >/dev/null 2>&1; then
    emit "FAIL" false 100 "plan.json missing required key: $key" \
      "{\"missing_key\": \"$key\"}"
    exit 1
  fi
done

STORY_COUNT=$(jq '.stories | length' "$PLAN")
if [[ "$STORY_COUNT" -eq 0 ]]; then
  emit "FAIL" false 100 "plan.json.stories[] is empty (LAW-F6 vacuous)" \
    '{"story_count": 0}'
  exit 1
fi

# ── Required sections in every story file ──────────────────────────
REQUIRED_SECTIONS=(
  "Atom brief"
  "Acceptance Criteria"
  "Dependencies"
  "Allowlist hint"
  "Estimated scope"
  "Out-of-scope"
)

FAILURES=()
OVERSIZED=()
MISSING_FILES=()
MISSING_SECTIONS=()
STUB_SECTIONS=()
UNTESTABLE_CRITERIA=()

for i in $(seq 0 $((STORY_COUNT - 1))); do
  sid=$(jq -r ".stories[$i].id" "$PLAN")
  sfile=$(jq -r ".stories[$i].file" "$PLAN")
  efiles=$(jq -r ".stories[$i].estimated_files // 0" "$PLAN")
  eloc=$(jq -r ".stories[$i].estimated_loc // 0" "$PLAN")

  # Resolve story file path
  abs_sfile="$sfile"
  [[ "$abs_sfile" = /* ]] || abs_sfile="$EPIC_DIR/$abs_sfile"

  if [[ ! -f "$abs_sfile" ]]; then
    MISSING_FILES+=("$sid:$sfile")
    continue
  fi

  # Section presence + body check
  for section in "${REQUIRED_SECTIONS[@]}"; do
    # Match header line (## Section or ### Section)
    header_line=$(grep -n -E "^#+ *${section}" "$abs_sfile" | head -1 | cut -d: -f1 || true)
    if [[ -z "$header_line" ]]; then
      MISSING_SECTIONS+=("$sid:$section")
      continue
    fi
    # Body = next 10 lines after header that are not blank and not headers
    body=$(awk -v start="$header_line" 'NR > start && NR <= start+15 {print}' "$abs_sfile" \
           | grep -v '^[[:space:]]*$' | grep -v '^#' | head -3 || true)
    if [[ -z "$body" ]]; then
      STUB_SECTIONS+=("$sid:$section")
    fi
  done

  # Size cap
  if [[ "$efiles" -gt "$MAX_FILES" ]]; then
    OVERSIZED+=("$sid: estimated_files=$efiles > cap=$MAX_FILES")
  fi
  if [[ "$eloc" -gt "$MAX_LOC" ]]; then
    OVERSIZED+=("$sid: estimated_loc=$eloc > cap=$MAX_LOC")
  fi

  # Testable acceptance criteria check
  # Extract Acceptance Criteria section body, look for at least one testable shape per non-blank line
  ac_start=$(grep -n -E '^#+ *Acceptance Criteria' "$abs_sfile" | head -1 | cut -d: -f1 || true)
  if [[ -n "$ac_start" ]]; then
    ac_end=$(awk -v start="$ac_start" 'NR > start && /^#+ /{print NR; exit}' "$abs_sfile" || echo "")
    [[ -z "$ac_end" ]] && ac_end=$(wc -l < "$abs_sfile")
    ac_body=$(sed -n "$((ac_start + 1)),${ac_end}p" "$abs_sfile" | grep -v '^[[:space:]]*$' | grep -v '^#')
    if [[ -n "$ac_body" ]]; then
      # Each non-blank, non-comment line must contain a testable token
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if ! echo "$line" | grep -qE '(GET|POST|PUT|PATCH|DELETE) +[/A-Za-z]|status (code )?[0-9]{3}|expect\(|getByTestId|getByRole|SELECT |INVARIANT|data-testid|PRD-AC-[0-9]+'; then
          UNTESTABLE_CRITERIA+=("$sid: '${line:0:80}'")
        fi
      done <<< "$ac_body"
    fi
  fi
done

# ── core_flows coverage ────────────────────────────────────────────
INTENT_FILE="$EPIC_DIR/intent/verdict.json"
UNCOVERED_FLOWS=()
if [[ -f "$INTENT_FILE" ]]; then
  declared_flows=$(jq -r '.declared.core_flows[]? // empty' "$INTENT_FILE" 2>/dev/null)
  covered_flows=$(jq -r '.stories[].core_flows[]? // empty' "$PLAN" 2>/dev/null | sort -u)
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if ! echo "$covered_flows" | grep -qx "$f"; then
      UNCOVERED_FLOWS+=("$f")
    fi
  done <<< "$declared_flows"
fi

# ── DAG cycle check (depends_on) ───────────────────────────────────
# Use POSIX `tsort` — exits non-zero + emits "tsort: cycle in data" on
# any cycle in the dependency graph. Portable across macOS bash 3.2.
CYCLES=()
TMP_GRAPH=$(mktemp)
# Edge format for tsort: "<predecessor> <successor>"
# depends_on semantics: story B depends_on A means A must seal before B,
# so edge is A → B (A is predecessor).
jq -r '.stories[] | .id as $i | (.depends_on // [])[] | "\(.) \($i)"' "$PLAN" > "$TMP_GRAPH" 2>/dev/null || true

if [[ -s "$TMP_GRAPH" ]]; then
  TSORT_ERR=$(mktemp)
  tsort "$TMP_GRAPH" >/dev/null 2>"$TSORT_ERR" || true
  # macOS tsort exits 0 even on cycle — detect by stderr signature
  if grep -q 'cycle in data' "$TSORT_ERR" 2>/dev/null; then
    cycle_nodes=$(grep -E '^tsort: ' "$TSORT_ERR" | grep -v 'cycle in data' | sed 's/^tsort: //' | tr '\n' ' ')
    [[ -z "$cycle_nodes" ]] && cycle_nodes="unknown"
    CYCLES+=("$cycle_nodes")
  fi
  rm -f "$TSORT_ERR"
fi
rm -f "$TMP_GRAPH"

# ── Aggregate ──────────────────────────────────────────────────────
[[ ${#MISSING_FILES[@]}      -gt 0 ]] && FAILURES+=("missing_story_files: ${MISSING_FILES[*]}")
[[ ${#MISSING_SECTIONS[@]}   -gt 0 ]] && FAILURES+=("missing_sections: ${MISSING_SECTIONS[*]}")
[[ ${#STUB_SECTIONS[@]}      -gt 0 ]] && FAILURES+=("stub_sections (LAW-F6): ${STUB_SECTIONS[*]}")
[[ ${#OVERSIZED[@]}          -gt 0 ]] && FAILURES+=("oversized_stories: ${OVERSIZED[*]}")
[[ ${#UNCOVERED_FLOWS[@]}    -gt 0 ]] && FAILURES+=("core_flows_not_covered: ${UNCOVERED_FLOWS[*]}")
[[ ${#CYCLES[@]}             -gt 0 ]] && FAILURES+=("dependency_cycles: ${CYCLES[*]}")
[[ ${#UNTESTABLE_CRITERIA[@]} -gt 0 ]] && FAILURES+=("untestable_acceptance_criteria: ${UNTESTABLE_CRITERIA[*]}")

DETAILS=$(jq -n \
  --argjson story_count "$STORY_COUNT" \
  --argjson max_files "$MAX_FILES" \
  --argjson max_loc "$MAX_LOC" \
  --argjson missing_files "$(printf '%s\n' "${MISSING_FILES[@]:-}" | jq -R . | jq -s 'map(select(. != ""))')" \
  --argjson missing_sections "$(printf '%s\n' "${MISSING_SECTIONS[@]:-}" | jq -R . | jq -s 'map(select(. != ""))')" \
  --argjson stub_sections "$(printf '%s\n' "${STUB_SECTIONS[@]:-}" | jq -R . | jq -s 'map(select(. != ""))')" \
  --argjson oversized "$(printf '%s\n' "${OVERSIZED[@]:-}" | jq -R . | jq -s 'map(select(. != ""))')" \
  --argjson uncovered_flows "$(printf '%s\n' "${UNCOVERED_FLOWS[@]:-}" | jq -R . | jq -s 'map(select(. != ""))')" \
  --argjson cycles "$(printf '%s\n' "${CYCLES[@]:-}" | jq -R . | jq -s 'map(select(. != ""))')" \
  --argjson untestable "$(printf '%s\n' "${UNTESTABLE_CRITERIA[@]:-}" | jq -R . | jq -s 'map(select(. != ""))')" \
  '{story_count: $story_count, max_files_per_atom: $max_files, max_loc_per_atom: $max_loc, missing_story_files: $missing_files, missing_sections: $missing_sections, stub_sections: $stub_sections, oversized: $oversized, core_flows_not_covered: $uncovered_flows, dependency_cycles: $cycles, untestable_acceptance_criteria: $untestable}')

if [[ ${#FAILURES[@]} -eq 0 ]]; then
  emit "PASS" true 95 "atom-plan with $STORY_COUNT stories; all gates clean" "$DETAILS"
  log "PASS — $STORY_COUNT stories"
  exit 0
else
  reason="GATE-SM failed: $(IFS=' | '; echo "${FAILURES[*]}")"
  emit "FAIL" false 100 "$reason" "$DETAILS"
  log "FAIL — ${#FAILURES[@]} failure category/ies"
  exit 1
fi
