#!/usr/bin/env bash
# no-vacuous-pass-test.sh — meta-gate that runs the full orchestrator against
# an EMPTY atom (no source files, no scope, no config) and asserts NO gate
# emits passed=true. If any gate does, that gate has a vacuous-PASS bug.
#
# This is the inversion test for LAW-F6. It is the only known automated defence
# against the failure mode where the skill itself emits silent PASS verdicts —
# which is the same failure mode the skill exists to prevent in user code.
#
# Per REPORT.md Unresolved Q#6: every backend/cloud gate that had a "no config
# → PASS" branch was a vacuous-PASS bug. This test would have caught all of
# them mechanically.
#
# Usage:
#   bash scripts/meta/no-vacuous-pass-test.sh [--out <dir>]
#
# Exit codes:
#   0 — no vacuous PASS detected (all gates emit FAIL/N/A/ERROR/no-emit)
#   1 — one or more gates emitted PASS against empty atom (skill bug)
#   2 — bootstrap error (orchestrator could not run)
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ORCHESTRATOR="$SKILL_ROOT/scripts/orchestrator/run-all-gates.sh"

OUT_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT_DIR="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$(mktemp -d -t vacuous-pass-XXXXXX)"
fi
ATOM_DIR="$OUT_DIR/atom"
PROJECT_ROOT="$OUT_DIR"
mkdir -p "$ATOM_DIR" "$PROJECT_ROOT"

echo "[meta] empty atom at: $PROJECT_ROOT" >&2

# Minimal .build-anything.json so orchestrator doesn't fail on config-missing;
# scope intentionally empty so every scope-dependent gate hits "no scope" path.
cat > "$PROJECT_ROOT/.build-anything.json" <<'JSON'
{
  "env": "test",
  "scope": { "mode": "atom_on_existing", "paths": [], "bootstrap_glob": [] },
  "stack": { "lang": "node" },
  "backend": {},
  "cloud": {}
}
JSON

echo "[meta] running orchestrator against empty atom" >&2
set +e
bash "$ORCHESTRATOR" --atom-dir "$ATOM_DIR" --project-root "$PROJECT_ROOT" --no-witness --skip-intent-check >"$OUT_DIR/orchestrator.stdout" 2>"$OUT_DIR/orchestrator.stderr"
ORCH_RC=$?
set -e

if [[ ! -f "$ATOM_DIR/manifest.json" ]]; then
  echo "[meta] FATAL: orchestrator did not produce manifest.json (rc=$ORCH_RC)" >&2
  cat "$OUT_DIR/orchestrator.stderr" >&2 || true
  exit 2
fi

# Count any PASS verdicts. In an empty atom, NO gate may emit PASS.
PASS_GATES=$(jq -r '.gates | to_entries | map(select(.value.passed == true)) | length' "$ATOM_DIR/manifest.json")
PASS_LIST=$(jq -c '.gates | to_entries | map(select(.value.passed == true)) | map({gate: .key, evidence: .value})' "$ATOM_DIR/manifest.json")

REPORT="$OUT_DIR/meta-no-vacuous-pass.json"
jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson n "$PASS_GATES" \
  --argjson violators "$PASS_LIST" \
  --slurpfile manifest "$ATOM_DIR/manifest.json" \
  '{
    meta_gate: "no-vacuous-pass-test",
    schema_version: "ubs-v8.3-meta",
    timestamp: $ts,
    empty_atom_summary: $manifest[0].summary,
    vacuous_pass_count: $n,
    violators: $violators,
    passed: ($n == 0),
    verdict: (if $n == 0 then "PASS" else "FAIL" end),
    interpretation: (if $n == 0
      then "no gate emitted PASS against empty atom — LAW-F6 invariant holds"
      else "one or more gates emitted PASS against empty atom — vacuous-PASS bug"
    end)
  }' > "$REPORT"

echo "[meta] report: $REPORT" >&2
jq -r '"vacuous_pass_count=" + (.vacuous_pass_count|tostring) + " verdict=" + .verdict' "$REPORT" >&2

if [[ "$PASS_GATES" -gt 0 ]]; then
  echo "[meta] VIOLATORS:" >&2
  jq -r '.violators[] | "  - " + .gate' "$REPORT" >&2
  exit 1
fi
exit 0
