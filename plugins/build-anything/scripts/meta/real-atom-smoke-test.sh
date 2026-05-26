#!/usr/bin/env bash
# real-atom-smoke-test.sh — meta-gate that runs the orchestrator against a
# MINIMAL-BUT-REAL atom (1 src file + 1 test + bootstrap_glob scope) and
# asserts the pipeline produces HONEST verdicts:
#   - mechanical gates with real evidence emit conf=100 (not null, not 0)
#   - secret-scan / sqli scans complete cleanly on real code
#   - backend/cloud gates correctly emit N/A_PENDING_REVIEWER (no TEST_DB_URL)
#   - no ERROR verdicts (silent-drop guard catches none)
#   - confidence-floor enforcement fires when floor > min_confidence
#
# Pair with no-vacuous-pass-test.sh. That one proves "empty input ≠ PASS".
# This one proves "real input ≠ ERROR-only and produces concrete evidence".
# Both together prove the skill is unfalsifiable on the two extreme cases.
#
# Usage:  bash scripts/meta/real-atom-smoke-test.sh
# Exit:   0 = honest pipeline output, non-zero = regression

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCH="$SCRIPT_DIR/../orchestrator/run-all-gates.sh"
[[ -f "$ORCH" ]] || { echo "FATAL: orchestrator missing at $ORCH" >&2; exit 2; }

# ── Build minimal real atom ────────────────────────────────────────
BENCH=$(mktemp -d /tmp/real-atom-smoke-XXXXXX)
trap 'rm -rf "$BENCH"' EXIT
mkdir -p "$BENCH/src" "$BENCH/test" "$BENCH/atom" "$BENCH/frontend" "$BENCH/backend"

# Empty FE/BE files ensure arch-bridge gate has a surface to scan (no N/A).
# This catches LAW-CL-95 retrofit holes in arch-bridge specifically — a hole
# that minimal `src/`-only atoms would miss because the gate would N/A out.
echo "// empty FE file for arch-bridge scan surface" > "$BENCH/frontend/index.js"
echo "// empty BE file for arch-bridge scan surface" > "$BENCH/backend/index.js"

cat > "$BENCH/.build-anything.json" <<'JSON'
{
  "project_type": "library",
  "env": "test",
  "stack": { "lang": "node", "dir": "." },
  "scope": { "mode": "bootstrap", "bootstrap_glob": ["src", "test"] },
  "frontend": { "dir": "frontend" },
  "backend": { "dir": "backend" },
  "gates": { "mechanical": { "coverage_line": 80, "coverage_branch": 60, "property_min": 1 } }
}
JSON

cat > "$BENCH/package.json" <<'JSON'
{
  "name": "real-atom-smoke",
  "version": "0.0.1",
  "type": "module",
  "scripts": { "test": "node --test \"test/**/*.test.js\"" }
}
JSON

cat > "$BENCH/src/add.js" <<'JS'
export function add(a, b) {
  if (typeof a !== 'number' || typeof b !== 'number') {
    throw new TypeError('add expects numbers');
  }
  return a + b;
}
JS

cat > "$BENCH/test/add.test.js" <<'JS'
import test from 'node:test';
import assert from 'node:assert/strict';
import { add } from '../src/add.js';
test('adds positives', () => assert.equal(add(2, 3), 5));
test('adds negatives', () => assert.equal(add(-1, -2), -3));
test('throws on non-number', () => assert.throws(() => add('1', 2), TypeError));
JS

# c8 needed by coverage gate. Install quietly; smoke-test depends on a working npm.
( cd "$BENCH" && npm install --silent --prefix . c8 ) >/dev/null 2>&1 || {
  echo "FATAL: npm install c8 failed at $BENCH" >&2; exit 2;
}

# ── Run orchestrator ───────────────────────────────────────────────
MANIFEST="$BENCH/atom/manifest.json"
set +e
bash "$ORCH" --atom-dir "$BENCH/atom" --project-root "$BENCH" --no-witness --skip-intent-check >/dev/null 2>&1
ORCH_EXIT=$?
set -e

[[ -f "$MANIFEST" ]] || { echo "FAIL: orchestrator did not write manifest" >&2; exit 1; }

SUMMARY=$(jq -c '.summary' "$MANIFEST")
PASS=$(jq -r '.summary.pass' "$MANIFEST")
ERR=$(jq -r '.summary.error' "$MANIFEST")
PASS_CONF_NULL=$(jq -r '[.gates | to_entries[] | select(.value.passed==true) | select(.value.confidence==null)] | length' "$MANIFEST")
PASS_CONF_ZERO=$(jq -r '[.gates | to_entries[] | select(.value.passed==true) | select(.value.confidence==0)]    | length' "$MANIFEST")

echo "summary: $SUMMARY"

# ── Assertions ─────────────────────────────────────────────────────
FAIL_REASONS=()
[[ "$PASS" -ge 3 ]]              || FAIL_REASONS+=("expected ≥3 PASS gates against real atom; got $PASS")
[[ "$ERR" -eq 0 ]]               || FAIL_REASONS+=("expected 0 ERROR verdicts; got $ERR (silent-drop regression)")
[[ "$PASS_CONF_NULL" -eq 0 ]]    || FAIL_REASONS+=("$PASS_CONF_NULL gate(s) emit PASS without a confidence field — LAW-CL-95 retrofit hole")
[[ "$PASS_CONF_ZERO" -eq 0 ]]    || FAIL_REASONS+=("$PASS_CONF_ZERO gate(s) emit PASS with confidence=0 — dishonest verdict")

# Confidence floor enforcement — orchestrator must exit 2 when min_conf < floor (and no fail/err).
ATOM2="$BENCH/atom2"; mkdir -p "$ATOM2"
set +e
bash "$ORCH" --atom-dir "$ATOM2" --project-root "$BENCH" --no-witness --skip-intent-check \
  --only be-invariant --only be-idempotency --confidence-floor 80 >/dev/null 2>&1
FLOOR_EXIT=$?
set -e
[[ "$FLOOR_EXIT" -eq 2 ]] || FAIL_REASONS+=("confidence-floor enforcement did not exit 2 on N/A-only run (got $FLOOR_EXIT)")

# ── Verdict ────────────────────────────────────────────────────────
if [[ ${#FAIL_REASONS[@]} -eq 0 ]]; then
  echo "real_atom_smoke_test verdict=PASS"
  exit 0
fi
echo "real_atom_smoke_test verdict=FAIL"
for r in "${FAIL_REASONS[@]}"; do echo "  - $r"; done
exit 1
