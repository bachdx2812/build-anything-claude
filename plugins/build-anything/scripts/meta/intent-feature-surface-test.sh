#!/usr/bin/env bash
# intent-feature-surface-test.sh — meta-gate for v8.7.2 LAW-INTENT-FS.
#
# Asserts that Stage 0.1 INTENT refuses to mark READY when:
#   - feature_surface[] has < 3 items (normal floor)
#   - feature_surface[] has < 5 items AND prompt references a known product
#   - feature_surface[] populated but history[] missing user-confirm entry
#
# And accepts READY when:
#   - feature_surface[] ≥ floor AND has user-confirm-feature-surface in history[]
#
# Why: v8.7.1 colleague test shipped under-scoped Flappy Bird + Notion clone
# atoms because intent stage delegated feature enumeration to research and
# never anchored user expectations. This gate guards the new anchor.
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INTENT_SCRIPT="$SKILL_ROOT/scripts/intent/declare-intent.sh"

OUT_BASE="$(mktemp -d -t intent-fs-meta-XXXXXX)"
declare -a CASES_PASSED CASES_FAILED

log() { echo "[meta:intent-fs] $*" >&2; }

if [[ ! -x "$INTENT_SCRIPT" ]]; then
  log "FATAL: intent script not executable: $INTENT_SCRIPT"
  exit 2
fi

# Helpers ─────────────────────────────────────────────────────────────
# Each case builds a fresh atom-dir, writes a raw prompt, writes a
# pre-populated intent.json (simulating the agent's LLM extraction),
# runs declare-intent.sh, then asserts on verdict.next_action.
#
# We pre-populate intent.json instead of running a real LLM because we
# only want to test the script's guard logic — not LLM extraction.

mk_atom() {
  local name="$1" prompt="$2" intent_state="$3"
  local atom_dir="$OUT_BASE/$name"
  mkdir -p "$atom_dir/intent"
  printf '%s\n' "$prompt" > "$atom_dir/intent/raw-prompt.md"
  printf '%s\n' "$intent_state" > "$atom_dir/intent/intent.json"
  echo "$atom_dir"
}

run_case() {
  local name="$1" atom_dir="$2" expected_action="$3"
  log "case=$name expect=$expected_action"
  set +e
  bash "$INTENT_SCRIPT" --atom-dir "$atom_dir" --project-root "$OUT_BASE" \
    --threshold 95 --max-iter 5 \
    >"$atom_dir/stdout" 2>"$atom_dir/stderr"
  local rc=$?
  set -e
  local verdict_file="$atom_dir/intent/verdict.json"
  if [[ ! -f "$verdict_file" ]]; then
    log "  -> FAIL: no verdict file (rc=$rc)"
    CASES_FAILED+=("$name(no-verdict)")
    return
  fi
  local actual_action
  actual_action=$(jq -r '.next_action' "$verdict_file" 2>/dev/null)
  if [[ "$actual_action" == "$expected_action" ]]; then
    log "  -> PASS (action=$actual_action)"
    CASES_PASSED+=("$name")
  else
    log "  -> FAIL: got next_action=$actual_action (rc=$rc)"
    jq -c '{next_action, na_pending_reason, confidence}' "$verdict_file" 2>/dev/null | sed 's/^/         /' >&2 || true
    CASES_FAILED+=("$name(action=$actual_action)")
  fi
}

# Common "high-confidence" intent body with all v8.5 fields populated.
# Cases differ only in feature_surface[] + history[].
base_declared() {
  cat <<'JSON'
{
  "product_type": "notion-clone",
  "primary_user": "knowledge worker",
  "core_flows": ["register & create workspace", "create nested page", "share page with team"],
  "success_criteria": ["user can register", "user can create nested pages", "user can share"],
  "out_of_scope": [],
  "constraints": [],
  "scale_tier": "mvp",
  "cost": { "monthly_usd_ceiling": 200, "currency": "USD" },
  "team": { "size": 2, "ops_maturity": "small" }
}
JSON
}

# ── Case 1: feature_surface empty + plain prompt → HALT (floor=3) ──────
ATOM=$(mk_atom "1_fs_empty" "build me a simple internal tool" "$(jq -n --argjson decl "$(base_declared)" '{
  iter: 1, confidence: 97,
  declared: ($decl + { product_type: "internal-tool", feature_surface: [] }),
  ambiguities: [], history: []
}')")
run_case "1_fs_empty" "$ATOM" "HALT"

# ── Case 2: feature_surface = 2 items + plain prompt → HALT (below floor=3) ─
ATOM=$(mk_atom "2_fs_two_items" "build me a simple internal tool" "$(jq -n --argjson decl "$(base_declared)" '{
  iter: 1, confidence: 97,
  declared: ($decl + {
    product_type: "internal-tool",
    feature_surface: [
      { name: "user login", must: true, synonyms: [], rationale: "auth" },
      { name: "dashboard", must: true, synonyms: [], rationale: "home" }
    ]
  }),
  ambiguities: [],
  history: [{ iter: 1, source: "user-confirm-feature-surface", added: [], removed: [] }]
}')")
run_case "2_fs_two_items" "$ATOM" "HALT"

# ── Case 3: feature_surface = 5 items + confirm history + READY → READY ─
ATOM=$(mk_atom "3_fs_complete_confirmed" "build me an internal tool" "$(jq -n --argjson decl "$(base_declared)" '{
  iter: 1, confidence: 97,
  declared: ($decl + {
    product_type: "internal-tool",
    feature_surface: [
      { name: "user login",     must: true, synonyms: ["auth","signin"], rationale: "" },
      { name: "dashboard",      must: true, synonyms: ["home"],          rationale: "" },
      { name: "user management", must: true, synonyms: ["admin"],         rationale: "" },
      { name: "audit log",      must: true, synonyms: [],                rationale: "" },
      { name: "settings",       must: true, synonyms: [],                rationale: "" }
    ]
  }),
  ambiguities: [],
  history: [{ iter: 1, source: "user-confirm-feature-surface", added: [], removed: [] }]
}')")
run_case "3_fs_complete_confirmed" "$ATOM" "READY"

# ── Case 4: feature_surface populated but NO user-confirm history → HALT ─
ATOM=$(mk_atom "4_fs_no_confirm" "build me an internal tool" "$(jq -n --argjson decl "$(base_declared)" '{
  iter: 1, confidence: 97,
  declared: ($decl + {
    product_type: "internal-tool",
    feature_surface: [
      { name: "user login", must: true, synonyms: [], rationale: "" },
      { name: "dashboard",  must: true, synonyms: [], rationale: "" },
      { name: "user management", must: true, synonyms: [], rationale: "" },
      { name: "audit log",  must: true, synonyms: [], rationale: "" },
      { name: "settings",   must: true, synonyms: [], rationale: "" }
    ]
  }),
  ambiguities: [],
  history: []
}')")
run_case "4_fs_no_confirm" "$ATOM" "HALT"

# ── Case 5: referenced-product prompt + only 3 items → HALT (floor=5) ──
ATOM=$(mk_atom "5_notion_clone_shallow" "build a notion clone" "$(jq -n --argjson decl "$(base_declared)" '{
  iter: 1, confidence: 97,
  declared: ($decl + {
    feature_surface: [
      { name: "register",    must: true, synonyms: ["signup"], rationale: "" },
      { name: "workspace",   must: true, synonyms: [],         rationale: "" },
      { name: "nested page", must: true, synonyms: [],         rationale: "" }
    ]
  }),
  ambiguities: [],
  history: [{ iter: 1, source: "user-confirm-feature-surface", added: [], removed: [] }]
}')")
run_case "5_notion_clone_shallow" "$ATOM" "HALT"

# ── Aggregate ──────────────────────────────────────────────────────────
TOTAL=$(( ${#CASES_PASSED[@]} + ${#CASES_FAILED[@]} ))
log "cases pass=${#CASES_PASSED[@]} fail=${#CASES_FAILED[@]} total=$TOTAL"

if [[ ${#CASES_FAILED[@]} -gt 0 ]]; then
  log "FAILED cases:"
  for c in "${CASES_FAILED[@]}"; do log "  - $c"; done
  exit 1
fi
exit 0
