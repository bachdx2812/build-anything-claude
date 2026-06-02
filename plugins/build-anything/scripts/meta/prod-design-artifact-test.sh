#!/usr/bin/env bash
# prod-design-artifact-test.sh — meta-gate for GATE-PROD-DESIGN-ART (v8.8 Stage 1.D).
#
# Asserts the prod-design-artifact gate correctly distinguishes a CLAIM (prose)
# from a backing ARTIFACT (a real non-empty file in the repo):
#   1. PASS  — SLO targets + Deployment topology both cite artifacts that exist
#              non-empty (monitoring rule + deploy manifest present).
#   2. FAIL  — SLO targets cites monitoring/rules.yaml but that file does NOT
#              exist (cited-but-missing: the vacuous-prose shape).
#   3. FAIL  — Deployment topology present with prose but NO `artifact:` line
#              (required section, no citation).
#   4. N/A   — production-design.md absent (architect persona not run yet); the
#              gate must NOT FAIL a build that has no production-design layer.
#
# Why this exists: GATE-PROD-DESIGN (text) passes a design whose SLO section
# merely asserts "prometheus alerts fire" while no rule file exists.
# GATE-PROD-DESIGN-ART is the v8.8 wiring-verification fix. Without this
# regression a future edit could collapse the artifact check back to prose and
# the audit's core finding (declared/claimed ≠ wired) would silently return.
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE_SCRIPT="$SKILL_ROOT/scripts/spec/prod-design-artifact-check.sh"

OUT_BASE="$(mktemp -d -t prod-design-art-meta-XXXXXX)"
declare -a CASES_PASSED CASES_FAILED

log() { echo "[meta:prod-design-art] $*" >&2; }

[[ -f "$GATE_SCRIPT" ]] || { log "FATAL: gate script missing: $GATE_SCRIPT"; exit 2; }

# new_case <name>  → makes case_dir + atom/gate-spec, echoes case_dir.
new_case() {
  local name="$1"
  local case_dir="$OUT_BASE/$name"
  mkdir -p "$case_dir/atom/gate-spec"
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
  local verdict_file="$atom_dir/gate-spec/prod-design-artifact.json"
  if [[ ! -f "$verdict_file" ]]; then
    log "  -> FAIL: no verdict file"; CASES_FAILED+=("$name(no-verdict)"); return
  fi
  local actual_verdict
  actual_verdict=$(jq -r '.verdict' "$verdict_file" 2>/dev/null)
  if [[ "$actual_verdict" == "$expected_verdict" && "$actual_rc" == "$expected_rc" ]]; then
    log "  -> PASS"; CASES_PASSED+=("$name")
  else
    log "  -> FAIL: got verdict=$actual_verdict rc=$actual_rc"
    jq -c '{verdict,findings,cited_artifacts,reason}' "$verdict_file" 2>/dev/null | sed 's/^/       /' >&2 || true
    CASES_FAILED+=("$name(verdict=$actual_verdict,rc=$actual_rc)")
  fi
}

# ── Case 1: both required sections cite EXISTING non-empty artifacts → PASS ──
CD=$(new_case "1_cited_and_present")
cat > "$CD/atom/production-design.md" <<'MD'
## SLO targets
 p95 < 200ms 99.9%
artifact: monitoring/rules.yaml

## Deployment topology
3-region k8s
artifact: k8s/deploy.yaml
MD
mkdir -p "$CD/monitoring" "$CD/k8s"
printf '%s\n' 'groups: [{name: slo, rules: [{alert: HighLatency}]}]' > "$CD/monitoring/rules.yaml"
printf '%s\n' 'apiVersion: apps/v1
kind: Deployment' > "$CD/k8s/deploy.yaml"
run_case "1_cited_and_present" "$CD" "PASS" "0"

# ── Case 2: SLO cites monitoring/rules.yaml but file is MISSING → FAIL ──
CD=$(new_case "2_cited_but_missing")
cat > "$CD/atom/production-design.md" <<'MD'
## SLO targets
 p95 < 200ms 99.9%
artifact: monitoring/rules.yaml

## Deployment topology
3-region k8s
artifact: k8s/deploy.yaml
MD
# Only the deploy manifest exists; the monitoring rule is deliberately absent.
mkdir -p "$CD/k8s"
printf '%s\n' 'apiVersion: apps/v1
kind: Deployment' > "$CD/k8s/deploy.yaml"
run_case "2_cited_but_missing" "$CD" "FAIL" "1"

# ── Case 3: Deployment topology prose but NO artifact: citation → FAIL ──
CD=$(new_case "3_required_no_citation")
cat > "$CD/atom/production-design.md" <<'MD'
## SLO targets
 p95 < 200ms 99.9%
artifact: monitoring/rules.yaml

## Deployment topology
3-region k8s, blue/green rollout, autoscaling 3-12 pods.
MD
mkdir -p "$CD/monitoring"
printf '%s\n' 'groups: [{name: slo}]' > "$CD/monitoring/rules.yaml"
run_case "3_required_no_citation" "$CD" "FAIL" "1"

# ── Case 4: no production-design.md at all → N/A, not FAIL ──────────────
CD=$(new_case "4_no_production_design")
run_case "4_no_production_design" "$CD" "N/A_PENDING_REVIEWER" "0"

# ── Aggregate ──────────────────────────────────────────────────────────
if [[ ${#CASES_FAILED[@]} -gt 0 ]]; then
  log "FAILED cases:"; for c in "${CASES_FAILED[@]}"; do log "  - $c"; done
  log "summary: pass=${#CASES_PASSED[@]} fail=${#CASES_FAILED[@]} verdict=FAIL"
  exit 1
fi
log "summary: pass=${#CASES_PASSED[@]} fail=0 verdict=PASS"
exit 0
