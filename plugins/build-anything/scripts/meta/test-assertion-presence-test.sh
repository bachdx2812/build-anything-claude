#!/usr/bin/env bash
# test-assertion-presence-test.sh — meta-gate for GATE-ASSERT (v8.8 Stage 5).
#
# Fixtures mirror the §16.4 "coverage gaming" class the audit warned about:
#   1. ASSERTING  → PASS — a test that actually checks behavior
#      (expect(doLogin()).toBe(true)). Real verification.
#   2. ZERO-ASSERT → FAIL — a test that runs code but checks nothing
#      (const r = doThing()). Drives coverage, proves nothing.
#   3. NO-TARGETS  → N/A  — no assert_scan + no changed files. Nothing resolved.
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE_SCRIPT="$SKILL_ROOT/scripts/mechanical/test-assertion-presence-check.sh"
OUT_BASE="$(mktemp -d -t assert-meta-XXXXXX)"
declare -a CASES_PASSED CASES_FAILED
log() { echo "[meta:assert] $*" >&2; }
[[ -f "$GATE_SCRIPT" ]] || { log "FATAL: gate script missing: $GATE_SCRIPT"; exit 2; }

setup() {  # <name> <config-json> → echoes case_dir
  local name="$1" cfg="$2"
  local case_dir="$OUT_BASE/$name"
  mkdir -p "$case_dir/atom/gate-mechanical"
  printf '%s' "$cfg" > "$case_dir/.build-anything.json"
  echo "$case_dir"
}

run_case() {
  local name="$1" case_dir="$2" want_verdict="$3" want_rc="$4"
  log "case=$name expect=verdict:$want_verdict rc:$want_rc"
  set +e
  bash "$GATE_SCRIPT" --atom-dir "$case_dir/atom" --project-root "$case_dir" \
    >"$case_dir/stdout" 2>"$case_dir/stderr"
  local rc=$?
  set -e
  local vf="$case_dir/atom/gate-mechanical/assertion-presence.json"
  [[ -f "$vf" ]] || { log "  -> FAIL: no verdict file"; CASES_FAILED+=("$name(no-verdict)"); return; }
  local v; v=$(jq -r '.verdict' "$vf" 2>/dev/null)
  if [[ "$v" == "$want_verdict" && "$rc" == "$want_rc" ]]; then
    log "  -> PASS"; CASES_PASSED+=("$name")
  else
    log "  -> FAIL: got verdict=$v rc=$rc"
    jq -c '{verdict,findings,reason}' "$vf" 2>/dev/null | sed 's/^/       /' >&2 || true
    CASES_FAILED+=("$name(verdict=$v,rc=$rc)")
  fi
}

# ── Case 1: asserting test → PASS ─────────────────────────────────────
CD=$(setup "1_asserting" '{"env":"test","assert_scan":{"test_globs":["*.test.js"]}}')
cat > "$CD/login.test.js" <<'JS'
test('login', () => { expect(doLogin()).toBe(true) })
JS
run_case "1_asserting" "$CD" "PASS" "0"

# ── Case 2: zero-assertion test → FAIL ────────────────────────────────
CD=$(setup "2_zero_assert" '{"env":"test","assert_scan":{"test_globs":["*.test.js"]}}')
cat > "$CD/bad.test.js" <<'JS'
test('noop', () => { const r = doThing() })
JS
run_case "2_zero_assert" "$CD" "FAIL" "1"

# ── Case 3: nothing to scan → N/A ─────────────────────────────────────
CD=$(setup "3_no_targets" '{"env":"test"}')
run_case "3_no_targets" "$CD" "N/A_PENDING_REVIEWER" "0"

if [[ ${#CASES_FAILED[@]} -gt 0 ]]; then
  log "FAILED cases:"; for c in "${CASES_FAILED[@]}"; do log "  - $c"; done
  log "summary: pass=${#CASES_PASSED[@]} fail=${#CASES_FAILED[@]} verdict=FAIL"
  exit 1
fi
log "summary: pass=${#CASES_PASSED[@]} fail=0 verdict=PASS"
exit 0
