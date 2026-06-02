#!/usr/bin/env bash
# e2e-semantic-floor-test.sh — meta-gate for GATE-E2E-SEM (v8.8 Stage 5).
#
# Asserts the E2E semantic-floor gate STATICALLY distinguishes a journey that
# asserts something SPECIFIC from one that merely ran / matched by filename:
#   1. PASS — journey's spec file contains every declared semantic assertion
#             AND a generic assertion keyword.
#   2. FAIL — a declared semantic assertion string is ABSENT from the spec
#             (the §16.4 tautology shape: file matched the journey but never
#             asserts the thing that was declared).
#   3. FAIL — journey declares ZERO semantic_assertions[] (tautology risk:
#             nothing specific is required of the test).
#   4. N/A  — backend project / e2e.enabled=false (LAW-F6: no vacuous PASS).
#
# Why this exists: GATE-25-E2E proved the Playwright suite was GREEN against
# stubs (§11.1) — green is not meaningful. GATE-E2E-SEM is the v8.8 static
# complement. Without this regression a future edit could collapse the check
# back to filename matching and the tautology hole returns. Pure static — this
# meta-test writes spec files and config; it boots nothing (no node/playwright).
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE_SCRIPT="$SKILL_ROOT/scripts/mechanical/e2e-semantic-floor-check.sh"

OUT_BASE="$(mktemp -d -t e2e-sem-meta-XXXXXX)"
declare -a CASES_PASSED CASES_FAILED

log() { echo "[meta:e2e-sem] $*" >&2; }

[[ -f "$GATE_SCRIPT" ]] || { log "FATAL: gate script missing: $GATE_SCRIPT"; exit 2; }

# setup <name> <config-json> → echoes case_dir (config + atom dirs only)
setup() {
  local name="$1" cfg="$2"
  local case_dir="$OUT_BASE/$name"
  mkdir -p "$case_dir/atom/gate-mechanical"
  printf '%s' "$cfg" > "$case_dir/.build-anything.json"
  echo "$case_dir"
}

run_case() {
  local name="$1" case_dir="$2" expected_verdict="$3" expected_rc="$4"
  local atom_dir="$case_dir/atom"
  log "case=$name expect=verdict:$expected_verdict rc:$expected_rc"
  set +e
  bash "$GATE_SCRIPT" --atom-dir "$atom_dir" --project-root "$case_dir" \
    >"$case_dir/stdout" 2>"$case_dir/stderr"
  local actual_rc=$?
  set -e
  local verdict_file="$atom_dir/gate-mechanical/e2e-semantic.json"
  if [[ ! -f "$verdict_file" ]]; then
    log "  -> FAIL: no verdict file"; CASES_FAILED+=("$name(no-verdict)"); return
  fi
  local actual_verdict
  actual_verdict=$(jq -r '.verdict' "$verdict_file" 2>/dev/null)
  if [[ "$actual_verdict" == "$expected_verdict" && "$actual_rc" == "$expected_rc" ]]; then
    log "  -> PASS"; CASES_PASSED+=("$name")
  else
    log "  -> FAIL: got verdict=$actual_verdict rc=$actual_rc"
    jq -c '{verdict,findings,journeys_verified,reason}' "$verdict_file" 2>/dev/null | sed 's/^/       /' >&2 || true
    CASES_FAILED+=("$name(verdict=$actual_verdict,rc=$actual_rc)")
  fi
}

# ── Case 1: fully asserted → PASS ──────────────────────────────────────
# Journey "login" declares two semantic assertions; the spec contains both
# plus a generic assertion keyword (`expect(`).
CFG1='{
  "project_type": "frontend",
  "e2e": {
    "enabled": true,
    "root": "tests/e2e",
    "journeys": [
      { "name": "login", "semantic_assertions": ["data-testid=login-form", "toBeVisible"] }
    ]
  }
}'
CD=$(setup "1_fully_asserted" "$CFG1")
mkdir -p "$CD/tests/e2e"
printf '%s\n' "import { test, expect } from '@playwright/test';
test('login', async ({ page }) => {
  await page.goto('/login');
  const form = page.locator('[data-testid=login-form]');
  await expect(form).toBeVisible();
});" > "$CD/tests/e2e/login.spec.ts"
run_case "1_fully_asserted" "$CD" "PASS" "0"

# ── Case 2: declared assertion missing from spec → FAIL ────────────────
# Same journey, but the spec omits "data-testid=login-form" (matched by name,
# asserts something else). The §16.4 tautology shape.
CD=$(setup "2_missing_assertion" "$CFG1")
mkdir -p "$CD/tests/e2e"
printf '%s\n' "import { test, expect } from '@playwright/test';
test('login', async ({ page }) => {
  await page.goto('/login');
  await expect(page).toBeVisible();
});" > "$CD/tests/e2e/login.spec.ts"
run_case "2_missing_assertion" "$CD" "FAIL" "1"

# ── Case 3: journey declares zero semantic assertions → FAIL ───────────
# A spec file is present (so e2e.root exists), but the journey requires nothing
# specific — tautology risk.
CFG3='{
  "project_type": "frontend",
  "e2e": {
    "enabled": true,
    "root": "tests/e2e",
    "journeys": [
      { "name": "home", "semantic_assertions": [] }
    ]
  }
}'
CD=$(setup "3_no_semantic_declared" "$CFG3")
mkdir -p "$CD/tests/e2e"
printf '%s\n' "import { test, expect } from '@playwright/test';
test('home', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveURL('/');
});" > "$CD/tests/e2e/home.spec.ts"
run_case "3_no_semantic_declared" "$CD" "FAIL" "1"

# ── Case 4: backend / e2e disabled → N/A (LAW-F6) ──────────────────────
CD=$(setup "4_backend_disabled" '{"project_type":"backend","e2e":{"enabled":false}}')
run_case "4_backend_disabled" "$CD" "N/A_PENDING_REVIEWER" "0"

# ── Aggregate ──────────────────────────────────────────────────────────
if [[ ${#CASES_FAILED[@]} -gt 0 ]]; then
  log "FAILED cases:"; for c in "${CASES_FAILED[@]}"; do log "  - $c"; done
  log "summary: pass=${#CASES_PASSED[@]} fail=${#CASES_FAILED[@]} verdict=FAIL"
  exit 1
fi
log "summary: pass=${#CASES_PASSED[@]} fail=0 verdict=PASS"
exit 0
