#!/usr/bin/env bash
# intent-preflight-test.sh — meta-gate that asserts the orchestrator enforces
# GATE-INTENT preflight (Stage 0.1) per LAW-CL-95 + the v8.3 contract.
#
# Three scenarios:
#   1. No intent/verdict.json + no --skip-intent-check ⇒ orchestrator exits 2.
#   2. intent/verdict.json with next_action=NEEDS_USER ⇒ orchestrator exits 2.
#   3. intent/verdict.json with next_action=READY ⇒ orchestrator proceeds (exit 0/1
#      based on gates; the preflight itself must not block).
#
# Why this exists: v8.3 doc claims Stage 0.1 is MANDATORY FIRST STAGE. Without
# this meta-gate, a code-only regression that removes the preflight check could
# ship silently — exactly the doc-vs-code lie LAW-CL-95 is meant to prevent.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCH="$SCRIPT_DIR/../orchestrator/run-all-gates.sh"
[[ -f "$ORCH" ]] || { echo "FATAL: orchestrator missing at $ORCH" >&2; exit 2; }

BENCH=$(mktemp -d /tmp/intent-preflight-XXXXXX)
trap 'rm -rf "$BENCH"' EXIT
mkdir -p "$BENCH/atom"

cat > "$BENCH/.build-anything.json" <<'JSON'
{
  "env": "test",
  "scope": { "mode": "atom_on_existing", "paths": [], "bootstrap_glob": [] },
  "stack": { "lang": "node" }
}
JSON

FAIL_REASONS=()

# ── Scenario 1: no intent/verdict.json ─────────────────────────────────
bash "$ORCH" --atom-dir "$BENCH/atom" --project-root "$BENCH" --no-witness >/dev/null 2>&1
RC1=$?
[[ "$RC1" -eq 2 ]] || FAIL_REASONS+=("scenario1: missing verdict.json should exit 2, got $RC1")

# ── Scenario 2: verdict.json with next_action=NEEDS_USER ───────────────
mkdir -p "$BENCH/atom/intent"
cat > "$BENCH/atom/intent/verdict.json" <<'JSON'
{ "gate": "GATE-INTENT", "next_action": "NEEDS_USER", "confidence": 50, "iter": 1 }
JSON
bash "$ORCH" --atom-dir "$BENCH/atom" --project-root "$BENCH" --no-witness >/dev/null 2>&1
RC2=$?
[[ "$RC2" -eq 2 ]] || FAIL_REASONS+=("scenario2: NEEDS_USER should exit 2, got $RC2")

# ── Scenario 3: verdict.json with next_action=READY ────────────────────
cat > "$BENCH/atom/intent/verdict.json" <<'JSON'
{ "gate": "GATE-INTENT", "next_action": "READY", "confidence": 97, "iter": 2 }
JSON
bash "$ORCH" --atom-dir "$BENCH/atom" --project-root "$BENCH" --no-witness >/dev/null 2>&1
RC3=$?
# Empty-atom case: orchestrator should NOT exit 2 due to preflight; whatever
# gates produce (FAIL/N/A) is fine here. Reject only the preflight exit 2 signal.
# Distinguish via stderr probe.
bash "$ORCH" --atom-dir "$BENCH/atom" --project-root "$BENCH" --no-witness 2>"$BENCH/s3.err" >/dev/null
if grep -q "GATE-INTENT preflight" "$BENCH/s3.err" && grep -q "EXIT 2" "$BENCH/s3.err"; then
  FAIL_REASONS+=("scenario3: READY should pass preflight, but orchestrator stderr shows preflight EXIT 2")
fi

# ── Scenario 4: --skip-intent-check bypasses everything ────────────────
rm -f "$BENCH/atom/intent/verdict.json"
bash "$ORCH" --atom-dir "$BENCH/atom" --project-root "$BENCH" --no-witness --skip-intent-check 2>"$BENCH/s4.err" >/dev/null
if grep -q "GATE-INTENT preflight" "$BENCH/s4.err" && grep -q "EXIT 2" "$BENCH/s4.err"; then
  FAIL_REASONS+=("scenario4: --skip-intent-check should bypass preflight, but stderr shows preflight EXIT 2")
fi

if [[ ${#FAIL_REASONS[@]} -eq 0 ]]; then
  echo "intent_preflight_test verdict=PASS"
  exit 0
fi
echo "intent_preflight_test verdict=FAIL"
for r in "${FAIL_REASONS[@]}"; do echo "  - $r"; done
exit 1
