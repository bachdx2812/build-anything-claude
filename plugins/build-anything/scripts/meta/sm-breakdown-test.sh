#!/usr/bin/env bash
# sm-breakdown-test.sh — meta-gate for GATE-SM (Stage 1.B.5 BMAD Scrum-Master)
#
# Asserts the sm-breakdown gate correctly:
#   1. N/A_PENDING_REVIEWER when atom-plan/plan.json is absent (SM not dispatched).
#   2. PASSes a valid 2-story plan with full sections + testable AC.
#   3. FAILs when a story file omits a required section.
#   4. FAILs when a story exceeds size cap (estimated_files > sm.max_files_per_atom).
#   5. FAILs when an epic core_flow is uncovered by any story.
#   6. FAILs on dependency cycle (A → B → A).
#   7. FAILs on untestable Acceptance Criteria (no HTTP/CSS/SQL/expect shape).
#
# Why this exists: Stage 1.B.5 closes the BMAD-method epic→atom breakdown gap.
# Without this meta-gate, GATE-SM could silently relax body / size / cycle checks
# and break the "atom small enough to test" guarantee.
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE_SCRIPT="$SKILL_ROOT/scripts/spec/sm-breakdown-gate.sh"

OUT_BASE="$(mktemp -d -t sm-breakdown-meta-XXXXXX)"
SUMMARY="$OUT_BASE/summary.json"
declare -a CASES_PASSED CASES_FAILED

log() { echo "[meta:sm-breakdown] $*" >&2; }

if [[ ! -x "$GATE_SCRIPT" ]]; then
  log "FATAL: gate script not executable: $GATE_SCRIPT"
  exit 2
fi

# ── Story-file helpers ────────────────────────────────────────────
mk_epic() {
  local name="$1"
  local epic_dir="$OUT_BASE/$name/epic"
  mkdir -p "$epic_dir/intent" "$epic_dir/atom-plan/stories" "$epic_dir/gate-spec"
  cat > "$epic_dir/intent/verdict.json" <<EOF
{ "declared": { "product_type": "todo-app", "core_flows": ["add","complete"] }, "next_action": "READY", "confidence": 100 }
EOF
  echo "$epic_dir"
}

write_story() {
  local epic_dir="$1" file_rel="$2" body="$3"
  local abs="$epic_dir/$file_rel"
  mkdir -p "$(dirname "$abs")"
  printf '%s' "$body" > "$abs"
}

# Valid story body template (all sections + testable AC + body lines)
valid_story() {
  cat <<'MD'
# Story 01 — add-todo

## Atom brief
User can add a new todo via POST /todos. Scope: schema + handler + smoke test. product_type=todo-app, scale_tier=mvp, cost.monthly_usd_ceiling=10.

## Acceptance Criteria
1. POST /todos returns 201 with the created todo
2. GET /todos returns 200 with the list (PRD-AC-01)

## Dependencies
None — root story.

## Allowlist hint
- backend/internal/todos/**
- backend/internal/router/**

## Estimated scope
- files: 6
- loc: 350
- core_flows: ["add"]
- journeys: ["J-01"]

## Out-of-scope (for this atom)
- Authentication (deferred to story-02)
- Persistence beyond in-memory (deferred to story-03)
MD
}

valid_story_02() {
  cat <<'MD'
# Story 02 — complete-todo

## Atom brief
User can mark a todo as complete via PATCH /todos/:id/complete. product_type=todo-app, scale_tier=mvp.

## Acceptance Criteria
1. PATCH /todos/:id/complete returns 200 with updated todo
2. GET /todos/:id returns 200 with status=complete after patch

## Dependencies
- story-01-add-todo (must seal first; introduces the schema)

## Allowlist hint
- backend/internal/todos/**

## Estimated scope
- files: 4
- loc: 200
- core_flows: ["complete"]
- journeys: ["J-02"]

## Out-of-scope (for this atom)
- Delete operation (future story)
MD
}

run_case() {
  local name="$1" epic_dir="$2" expected_verdict="$3" expected_rc="$4"
  log "case=$name expect=verdict:$expected_verdict rc:$expected_rc"

  set +e
  bash "$GATE_SCRIPT" --epic-dir "$epic_dir" --project-root "$(dirname "$epic_dir")" \
    >"$epic_dir/stdout" 2>"$epic_dir/stderr"
  local actual_rc=$?
  set -e

  local verdict_file="$epic_dir/gate-spec/sm-breakdown.json"
  if [[ ! -f "$verdict_file" ]]; then
    log "  -> FAIL: no verdict file emitted"
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
    log "       file: $verdict_file"
    jq -c '.' "$verdict_file" 2>/dev/null | sed 's/^/         /' >&2 || true
    CASES_FAILED+=("$name(verdict=$actual_verdict,rc=$actual_rc)")
  fi
}

# ── Case 1: plan.json absent → N/A ──────────────────────────────────
EPIC=$(mk_epic "1_no_plan")
run_case "1_no_plan" "$EPIC" "N/A_PENDING_REVIEWER" "0"

# ── Case 2: valid 2-story plan with full sections → PASS ────────────
EPIC=$(mk_epic "2_valid_plan")
write_story "$EPIC" "atom-plan/stories/story-01-add-todo.md" "$(valid_story)"
write_story "$EPIC" "atom-plan/stories/story-02-complete-todo.md" "$(valid_story_02)"
cat > "$EPIC/atom-plan/plan.json" <<EOF
{
  "epic": "todo-app",
  "epic_dir": "$EPIC",
  "total_stories": 2,
  "execution_order": ["story-01-add-todo", "story-02-complete-todo"],
  "stories": [
    {
      "id": "story-01-add-todo",
      "slug": "add-todo",
      "file": "atom-plan/stories/story-01-add-todo.md",
      "atom_brief": "User can add todo via POST /todos.",
      "depends_on": [],
      "estimated_files": 6,
      "estimated_loc": 350,
      "core_flows": ["add"],
      "journeys_covered": ["J-01"],
      "allowlist_hint": ["backend/internal/todos/**"],
      "status": "pending"
    },
    {
      "id": "story-02-complete-todo",
      "slug": "complete-todo",
      "file": "atom-plan/stories/story-02-complete-todo.md",
      "atom_brief": "User can mark todo complete via PATCH.",
      "depends_on": ["story-01-add-todo"],
      "estimated_files": 4,
      "estimated_loc": 200,
      "core_flows": ["complete"],
      "journeys_covered": ["J-02"],
      "allowlist_hint": ["backend/internal/todos/**"],
      "status": "pending"
    }
  ]
}
EOF
run_case "2_valid_plan" "$EPIC" "PASS" "0"

# ── Case 3: story missing required section → FAIL ──────────────────
EPIC=$(mk_epic "3_missing_section")
# Story without "## Out-of-scope"
write_story "$EPIC" "atom-plan/stories/story-01-add-todo.md" "$(cat <<'MD'
# Story 01 — add-todo
## Atom brief
brief body
## Acceptance Criteria
1. POST /todos returns 201
## Dependencies
none
## Allowlist hint
- backend/**
## Estimated scope
- files: 6
MD
)"
write_story "$EPIC" "atom-plan/stories/story-02-complete-todo.md" "$(valid_story_02)"
cat > "$EPIC/atom-plan/plan.json" <<EOF
{
  "epic": "todo-app",
  "total_stories": 2,
  "execution_order": ["story-01-add-todo", "story-02-complete-todo"],
  "stories": [
    {"id":"story-01-add-todo","slug":"add-todo","file":"atom-plan/stories/story-01-add-todo.md","atom_brief":"a","depends_on":[],"estimated_files":6,"estimated_loc":350,"core_flows":["add"]},
    {"id":"story-02-complete-todo","slug":"complete-todo","file":"atom-plan/stories/story-02-complete-todo.md","atom_brief":"b","depends_on":["story-01-add-todo"],"estimated_files":4,"estimated_loc":200,"core_flows":["complete"]}
  ]
}
EOF
run_case "3_missing_section" "$EPIC" "FAIL" "1"

# ── Case 4: story oversized → FAIL ──────────────────────────────────
EPIC=$(mk_epic "4_oversized")
write_story "$EPIC" "atom-plan/stories/story-01-add-todo.md" "$(valid_story)"
write_story "$EPIC" "atom-plan/stories/story-02-complete-todo.md" "$(valid_story_02)"
cat > "$EPIC/atom-plan/plan.json" <<EOF
{
  "epic": "todo-app",
  "total_stories": 2,
  "execution_order": ["story-01-add-todo", "story-02-complete-todo"],
  "stories": [
    {"id":"story-01-add-todo","slug":"add-todo","file":"atom-plan/stories/story-01-add-todo.md","atom_brief":"a","depends_on":[],"estimated_files":40,"estimated_loc":350,"core_flows":["add"]},
    {"id":"story-02-complete-todo","slug":"complete-todo","file":"atom-plan/stories/story-02-complete-todo.md","atom_brief":"b","depends_on":["story-01-add-todo"],"estimated_files":4,"estimated_loc":200,"core_flows":["complete"]}
  ]
}
EOF
run_case "4_oversized" "$EPIC" "FAIL" "1"

# ── Case 5: core_flow uncovered → FAIL ──────────────────────────────
EPIC=$(mk_epic "5_uncovered_flow")
write_story "$EPIC" "atom-plan/stories/story-01-add-todo.md" "$(valid_story)"
cat > "$EPIC/atom-plan/plan.json" <<EOF
{
  "epic": "todo-app",
  "total_stories": 1,
  "execution_order": ["story-01-add-todo"],
  "stories": [
    {"id":"story-01-add-todo","slug":"add-todo","file":"atom-plan/stories/story-01-add-todo.md","atom_brief":"a","depends_on":[],"estimated_files":6,"estimated_loc":350,"core_flows":["add"]}
  ]
}
EOF
# Intent declares ["add","complete"] but plan only covers ["add"] → FAIL
run_case "5_uncovered_flow" "$EPIC" "FAIL" "1"

# ── Case 6: dependency cycle → FAIL ─────────────────────────────────
EPIC=$(mk_epic "6_cycle")
write_story "$EPIC" "atom-plan/stories/story-01-add-todo.md" "$(valid_story)"
write_story "$EPIC" "atom-plan/stories/story-02-complete-todo.md" "$(valid_story_02)"
# A → B AND B → A
cat > "$EPIC/atom-plan/plan.json" <<EOF
{
  "epic": "todo-app",
  "total_stories": 2,
  "execution_order": ["story-01-add-todo", "story-02-complete-todo"],
  "stories": [
    {"id":"story-01-add-todo","slug":"add-todo","file":"atom-plan/stories/story-01-add-todo.md","atom_brief":"a","depends_on":["story-02-complete-todo"],"estimated_files":6,"estimated_loc":350,"core_flows":["add"]},
    {"id":"story-02-complete-todo","slug":"complete-todo","file":"atom-plan/stories/story-02-complete-todo.md","atom_brief":"b","depends_on":["story-01-add-todo"],"estimated_files":4,"estimated_loc":200,"core_flows":["complete"]}
  ]
}
EOF
run_case "6_cycle" "$EPIC" "FAIL" "1"

# ── Case 7: untestable Acceptance Criteria → FAIL ───────────────────
EPIC=$(mk_epic "7_untestable_ac")
write_story "$EPIC" "atom-plan/stories/story-01-add-todo.md" "$(cat <<'MD'
# Story 01 — add-todo
## Atom brief
brief body
## Acceptance Criteria
1. Users should be happy when they add a todo
2. The system should feel responsive
## Dependencies
none
## Allowlist hint
- backend/**
## Estimated scope
- files: 6
- loc: 350
- core_flows: ["add"]
## Out-of-scope (for this atom)
- nothing
MD
)"
write_story "$EPIC" "atom-plan/stories/story-02-complete-todo.md" "$(valid_story_02)"
cat > "$EPIC/atom-plan/plan.json" <<EOF
{
  "epic": "todo-app",
  "total_stories": 2,
  "execution_order": ["story-01-add-todo", "story-02-complete-todo"],
  "stories": [
    {"id":"story-01-add-todo","slug":"add-todo","file":"atom-plan/stories/story-01-add-todo.md","atom_brief":"a","depends_on":[],"estimated_files":6,"estimated_loc":350,"core_flows":["add"]},
    {"id":"story-02-complete-todo","slug":"complete-todo","file":"atom-plan/stories/story-02-complete-todo.md","atom_brief":"b","depends_on":["story-01-add-todo"],"estimated_files":4,"estimated_loc":200,"core_flows":["complete"]}
  ]
}
EOF
run_case "7_untestable_ac" "$EPIC" "FAIL" "1"

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
    meta_gate: "sm-breakdown-test",
    schema_version: "ubs-v8.5.2-meta",
    timestamp: $ts,
    cases_total: $total,
    cases_pass: $pass,
    cases_fail: $fail,
    cases_passed: $passed,
    cases_failed: $failed,
    verdict: (if $fail == 0 then "PASS" else "FAIL" end),
    interpretation: (if $fail == 0
      then "GATE-SM correctly enforces BMAD-method epic→atom breakdown contract — v8.5.2 invariant holds"
      else "GATE-SM regressed — one or more fixtures returned unexpected verdict"
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
