#!/usr/bin/env bash
# implementer-coverage-test.sh — meta-gate for GATE-IMPL (Stage 4 BMAD-method).
#
# Asserts the implementer-coverage gate correctly:
#   1. N/A_PENDING_REVIEWER (rc=0) when concern-split.json missing — atom did
#      not reach Stage 4. NOT an ERROR: reviewer decides if dispatch expected.
#   2. PASS multi-persona when every dispatched persona wrote a status report with
#      verdict=PASS, files_changed ⊆ that persona's allowlist subset, allowlists
#      disjoint, and tests-status.core_flows_covered ⊇ intent.core_flows.
#   3. FAIL multi-persona when one persona's files_changed escape its allowlist.
#   4. FAIL multi-persona when tests-status.core_flows_covered missing entries
#      from intent/verdict.json.core_flows.
#   5. FAIL when a dispatched persona left no *-status.json file (silent drop —
#      LAW-F6 at Stage 4 level).
#   6. PASS single-persona happy path (one fullstack-developer with all files
#      inside the unified allowlist).
#   7. FAIL when persona verdict is neither PASS nor PENDING (e.g. FAIL).
#
# Why this exists: Stage 4 is the BUILD step. v8.4 split it into 3 personas
# (backend/frontend/tests) to remove the single-author bias the v8.2 audit
# surfaced. Without this regression, a future skill edit could relax the
# files_changed-subset check and re-introduce silent overlap, or accept a
# missing tests persona, which would mean "code shipped without E2E proof".
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE_SCRIPT="$SKILL_ROOT/scripts/implementer/implementer-coverage-gate.sh"

OUT_BASE="$(mktemp -d -t impl-cov-meta-XXXXXX)"
SUMMARY="$OUT_BASE/summary.json"
declare -a CASES_PASSED CASES_FAILED

log() { echo "[meta:impl-cov] $*" >&2; }

if [[ ! -x "$GATE_SCRIPT" ]]; then
  log "FATAL: gate script not executable: $GATE_SCRIPT"
  exit 2
fi

# Make an atom dir with intent verdict declaring core_flows.
mk_atom() {
  local name="$1" core_flows="${2:-[\"upload\",\"play\"]}"
  local atom_dir="$OUT_BASE/$name/atom"
  mkdir -p "$atom_dir/intent" "$atom_dir/implementer" "$atom_dir/gate-impl"
  cat > "$atom_dir/intent/verdict.json" <<EOF
{
  "declared": { "product_type": "todo-app", "core_flows": $core_flows },
  "next_action": "READY",
  "confidence": 100
}
EOF
  echo "$atom_dir"
}

# Write a concern-split.json. Args: atom_dir, mode, be_dispatch, fe_dispatch, ts_dispatch,
#                                    be_globs, fe_globs, ts_globs
write_split() {
  local atom_dir="$1" mode="$2" be_d="$3" fe_d="$4" ts_d="$5" \
        be_g="$6" fe_g="$7" ts_g="$8"
  cat > "$atom_dir/implementer/concern-split.json" <<EOF
{
  "schema_version": "ubs-v8.4-implementer-split",
  "mode": "$mode",
  "concerns": {
    "backend":  { "globs": $be_g, "files": [], "dispatch": $be_d },
    "frontend": { "globs": $fe_g, "files": [], "dispatch": $fe_d },
    "tests":    { "globs": $ts_g, "files": [], "dispatch": $ts_d }
  },
  "uncategorised": []
}
EOF
}

# Write a persona status report. Args: atom_dir, persona, verdict, files_changed_json, [core_flows_covered_json]
write_status() {
  local atom_dir="$1" persona="$2" verdict="$3" files="$4" core="${5:-[]}"
  cat > "$atom_dir/implementer/${persona}-status.json" <<EOF
{
  "persona": "$persona",
  "verdict": "$verdict",
  "files_changed": $files,
  "commits": [],
  "core_flows_covered": $core,
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

run_case() {
  local name="$1" atom_dir="$2" expected_verdict="$3" expected_rc="$4"
  log "case=$name expect=verdict:$expected_verdict rc:$expected_rc"

  set +e
  bash "$GATE_SCRIPT" --atom-dir "$atom_dir" --project-root "$(dirname "$atom_dir")" \
    >"$atom_dir/stdout" 2>"$atom_dir/stderr"
  local actual_rc=$?
  set -e

  local verdict_file="$atom_dir/gate-impl/coverage.json"
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

# ── Case 1: concern-split.json missing → N/A_PENDING_REVIEWER rc=0 ──
ATOM=$(mk_atom "1_no_split")
# No write_split call. Atom never reached Stage 4 — gate cannot run, but it is
# not a silent-drop ERROR either. Reviewer must decide whether dispatch was
# expected. LAW-F6: surface as N/A_PENDING_REVIEWER.
run_case "1_no_split" "$ATOM" "N/A_PENDING_REVIEWER" "0"

# ── Case 2: multi-persona happy path → PASS ─────────────────────────
ATOM=$(mk_atom "2_multi_ok")
write_split "$ATOM" "multi-persona" "true" "true" "true" \
  '["backend/**","api/**"]' \
  '["frontend/**","src/components/**"]' \
  '["e2e/**","tests/e2e/**"]'
write_status "$ATOM" "backend"  "PASS" '["backend/routes/upload.ts","api/handlers/play.ts"]'
write_status "$ATOM" "frontend" "PASS" '["frontend/pages/upload.tsx","src/components/Player.tsx"]'
write_status "$ATOM" "tests"    "PASS" '["e2e/upload.spec.ts","e2e/play.spec.ts"]' '["upload","play"]'
run_case "2_multi_ok" "$ATOM" "PASS" "0"

# ── Case 3: backend files escape its allowlist → FAIL ───────────────
ATOM=$(mk_atom "3_outside_allowlist")
write_split "$ATOM" "multi-persona" "true" "true" "true" \
  '["backend/**"]' \
  '["frontend/**"]' \
  '["e2e/**"]'
# Backend touches frontend file — must be rejected.
write_status "$ATOM" "backend"  "PASS" '["backend/routes/upload.ts","frontend/pages/sneaky.tsx"]'
write_status "$ATOM" "frontend" "PASS" '["frontend/pages/upload.tsx"]'
write_status "$ATOM" "tests"    "PASS" '["e2e/upload.spec.ts","e2e/play.spec.ts"]' '["upload","play"]'
run_case "3_outside_allowlist" "$ATOM" "FAIL" "1"

# ── Case 4: tests-status missing a core_flow → FAIL ─────────────────
ATOM=$(mk_atom "4_missing_core_flow")
write_split "$ATOM" "multi-persona" "true" "true" "true" \
  '["backend/**"]' \
  '["frontend/**"]' \
  '["e2e/**"]'
write_status "$ATOM" "backend"  "PASS" '["backend/routes/upload.ts"]'
write_status "$ATOM" "frontend" "PASS" '["frontend/pages/upload.tsx"]'
# core_flows declared upload+play; covered only upload.
write_status "$ATOM" "tests"    "PASS" '["e2e/upload.spec.ts"]' '["upload"]'
run_case "4_missing_core_flow" "$ATOM" "FAIL" "1"

# ── Case 5: dispatched persona left no status file → FAIL ───────────
ATOM=$(mk_atom "5_silent_drop")
write_split "$ATOM" "multi-persona" "true" "true" "true" \
  '["backend/**"]' \
  '["frontend/**"]' \
  '["e2e/**"]'
# No backend-status.json written.
write_status "$ATOM" "frontend" "PASS" '["frontend/pages/upload.tsx"]'
write_status "$ATOM" "tests"    "PASS" '["e2e/upload.spec.ts","e2e/play.spec.ts"]' '["upload","play"]'
run_case "5_silent_drop" "$ATOM" "FAIL" "1"

# ── Case 6: single-persona happy path → PASS ────────────────────────
ATOM=$(mk_atom "6_single_ok")
write_split "$ATOM" "single-persona" "true" "false" "false" \
  '["backend/**","api/**"]' '[]' '[]'
cat > "$ATOM/implementer/single-status.json" <<'EOF'
{
  "persona": "fullstack",
  "verdict": "PASS",
  "files_changed": ["backend/routes/upload.ts","api/handlers/play.ts"],
  "commits": [],
  "ran_at": "1970-01-01T00:00:00Z"
}
EOF
run_case "6_single_ok" "$ATOM" "PASS" "0"

# ── Case 7: persona verdict=FAIL → FAIL ─────────────────────────────
ATOM=$(mk_atom "7_bad_verdict")
write_split "$ATOM" "multi-persona" "true" "true" "true" \
  '["backend/**"]' \
  '["frontend/**"]' \
  '["e2e/**"]'
write_status "$ATOM" "backend"  "FAIL" '["backend/routes/upload.ts"]'
write_status "$ATOM" "frontend" "PASS" '["frontend/pages/upload.tsx"]'
write_status "$ATOM" "tests"    "PASS" '["e2e/upload.spec.ts","e2e/play.spec.ts"]' '["upload","play"]'
run_case "7_bad_verdict" "$ATOM" "FAIL" "1"

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
    meta_gate: "implementer-coverage-test",
    schema_version: "ubs-v8.4-meta",
    timestamp: $ts,
    cases_total: $total,
    cases_pass: $pass,
    cases_fail: $fail,
    cases_passed: $passed,
    cases_failed: $failed,
    verdict: (if $fail == 0 then "PASS" else "FAIL" end),
    interpretation: (if $fail == 0
      then "GATE-IMPL correctly enforces BMAD-method Stage 4 dispatch invariants — allowlist subset + core_flow coverage + silent-drop guard hold"
      else "GATE-IMPL regressed — one or more fixtures returned unexpected verdict"
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
