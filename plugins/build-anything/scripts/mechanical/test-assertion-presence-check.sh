#!/usr/bin/env bash
# test-assertion-presence-check.sh — Stage 5 GATE-ASSERT (v8.8)
#
# Catches the audit's §16.4 class: "coverage gaming." A test file can drive
# 80% line coverage while asserting NOTHING —
#     test('x', () => { const r = f() })
# — the function runs, the line counter ticks, but no behavior is checked.
# Today only mutation testing catches this; mutation is slow and often skipped.
# This STATIC gate FAILs any test file that DEFINES tests but contains ZERO
# assertion keywords, so the cheap signal lands before the expensive one.
#
# Resolve test files:
#   `.build-anything.json#assert_scan.test_globs[]` (filename patterns) if present;
#   else changed_files() filtered to test/spec files (names matching
#   *.test.* / *.spec.* / *_test.go / test_*.py / *_spec.rb / *Test.{java,kt}).
#   Empty → N/A_PENDING_REVIEWER (LAW-F6 — never silent PASS).
#
# A file "DEFINES tests" if it matches: test(|it(|describe(|func Test|def test_|
#   @Test|#[test]|it " .
# Assertion keywords: expect(|assert|.should|toBe|toEqual|toContain|toHaveText|
#   require.|t.Error|t.Fatal|XCTAssert|EXPECT_|ASSERT_ .
#
# A resolved test file that DEFINES tests but has ZERO assertion keywords →
#   finding. Any finding → FAIL. Files that don't define tests are skipped
#   (a shared fixtures/helpers file is not itself a vacuous test).
# LAW-CL-95: confidence + ambiguities[].

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_common.sh"

ATOM_DIR=""; PROJECT_ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --atom-dir)     ATOM_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done
: "${ATOM_DIR:?--atom-dir required}"
: "${PROJECT_ROOT:=$(pwd)}"
export ATOM_DIR PROJECT_ROOT
CONFIG="$PROJECT_ROOT/.build-anything.json"
OUT="$ATOM_DIR/gate-mechanical/assertion-presence.json"
mkdir -p "$(dirname "$OUT")"

log() { echo "[$(date -u +%H:%M:%S)] [assert] $*" >&2; }

emit_na() {
  local reason="$1" rj; rj=$(printf '%s' "$reason" | jq -Rs .)
  cat > "$OUT" <<JSON
{ "gate": "GATE-ASSERT", "passed": null, "verdict": "N/A_PENDING_REVIEWER",
  "reason": $rj, "confidence": 0, "ambiguities": [$rj], "review_required": true,
  "schema_version": "ubs-v8.8-assert", "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)" }
JSON
  exit 0
}
emit_fail() {
  local findings="$1"
  cat > "$OUT" <<JSON
{ "gate": "GATE-ASSERT", "passed": false, "verdict": "FAIL",
  "reason": "test file defines tests but asserts nothing (zero-assertion / coverage-gaming)",
  "findings": $findings, "confidence": 100, "ambiguities": [],
  "schema_version": "ubs-v8.8-assert", "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)" }
JSON
  exit 1
}
emit_pass() {
  local scanned="$1"
  cat > "$OUT" <<JSON
{ "gate": "GATE-ASSERT", "passed": true, "verdict": "PASS",
  "test_files_scanned": $scanned, "confidence": 100, "ambiguities": [],
  "schema_version": "ubs-v8.8-assert", "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)" }
JSON
  exit 0
}

# ── Patterns ──────────────────────────────────────────────────────────
# A file DEFINES tests (test bodies that should assert something).
DEFINES_RE='test\(|it\(|describe\(|func Test|def test_|@Test|#\[test\]|it "'
# Assertion keywords across the common stacks.
ASSERT_RE='expect\(|assert|\.should|toBe|toEqual|toContain|toHaveText|require\.|t\.Error|t\.Fatal|XCTAssert|EXPECT_|ASSERT_'

# Filename heuristic for test/spec files (used when filtering changed_files()).
is_test_file() {
  case "$1" in
    *.test.*|*.spec.*|*_test.go|*_spec.rb) return 0 ;;
    *Test.java|*Test.kt)                   return 0 ;;
  esac
  # test_*.py — basename prefix, any directory.
  case "${1##*/}" in test_*.py) return 0 ;; esac
  return 1
}

# ── Resolve test files ────────────────────────────────────────────────
# Priority:
#   1. assert_scan.test_globs[] — filename patterns. Declared explicitly, so we
#      walk PROJECT_ROOT and select every file whose BASENAME matches a pattern
#      (a glob in config means "find these files on disk", independent of git).
#   2. else changed_files() filtered to test/spec names by is_test_file().
TESTFILES=""
GLOBS=""
[[ -f "$CONFIG" ]] && GLOBS=$(jq -r '.assert_scan.test_globs[]? // empty' "$CONFIG" 2>/dev/null || true)

if [[ -n "$GLOBS" ]]; then
  # Walk the tree once; match each file's basename against the declared patterns.
  # find -name handles the glob; skip VCS / dependency dirs to stay relevant.
  while IFS= read -r pat; do
    [[ -z "$pat" ]] && continue
    while IFS= read -r abs; do
      [[ -z "$abs" ]] && continue
      TESTFILES+="${abs#$PROJECT_ROOT/}"$'\n'
    done < <(find "$PROJECT_ROOT" \
               \( -name .git -o -name node_modules -o -name vendor -o -name .build-anything \) -prune \
               -o -type f -name "$pat" -print 2>/dev/null || true)
  done <<< "$GLOBS"
else
  # No declared globs — fall back to changed_files() filtered by name heuristic.
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    is_test_file "$rel" && TESTFILES+="$rel"$'\n'
  done < <(changed_files || true)
fi

# Trim trailing blank line + dedupe (a file may match >1 pattern).
TESTFILES="${TESTFILES%$'\n'}"
[[ -n "$TESTFILES" ]] && TESTFILES=$(printf '%s\n' "$TESTFILES" | awk 'NF && !seen[$0]++')
[[ -z "$TESTFILES" ]] && emit_na "no assert_scan.test_globs[] match and no changed test/spec files — nothing to scan (declare test filename patterns in assert_scan.test_globs[])"

FINDINGS=()
SCANNED=0
while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  abs="$PROJECT_ROOT/$rel"
  [[ -f "$abs" ]] || continue
  SCANNED=$((SCANNED+1))

  # Only files that actually define tests are subject to the assertion law.
  grep -qE "$DEFINES_RE" "$abs" 2>/dev/null || continue

  if ! grep -qE "$ASSERT_RE" "$abs" 2>/dev/null; then
    FINDINGS+=("$rel: defines tests but has no assertions (zero-assertion / coverage-gaming)")
  fi
done <<< "$TESTFILES"

if [[ ${#FINDINGS[@]} -gt 0 ]]; then
  FJSON=$(printf '%s\n' "${FINDINGS[@]}" | jq -R . | jq -s 'map(select(length>0))')
  log "FAIL: ${#FINDINGS[@]} zero-assertion test file(s) across $SCANNED scanned"
  emit_fail "$FJSON"
fi

log "PASS: $SCANNED test file(s) scanned, all defining tests carry assertions"
emit_pass "$SCANNED"
