#!/usr/bin/env bash
# cloud-artifact-test.sh — meta-gate for GATE-CLOUD-ART (v8.8).
#
# Asserts the cloud-artifact-existence gate distinguishes a DECLARED infra
# artifact from one that actually EXISTS as a non-empty file on disk:
#   1. PASS — every required_artifact has a non-empty matching file.
#   2. FAIL — required_artifacts declared but k8s/ is EMPTY (the §12 shape:
#             report said "K8s configs ready" but no k8s/*.yaml exist).
#   3. N/A  — no cloud.required_artifacts declared (LAW-F6: never silent PASS).
#
# Why this exists: the audit caught "K8s configs ready" while k8s/ was empty.
# Without this regression a future edit could collapse the gate back to a
# declaration check and the audit's §6/§12 finding would silently return.
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE_SCRIPT="$SKILL_ROOT/scripts/cloud/artifact-existence-check.sh"

OUT_BASE="$(mktemp -d -t cloud-art-meta-XXXXXX)"
declare -a CASES_PASSED CASES_FAILED

log() { echo "[meta:cloud-art] $*" >&2; }

[[ -f "$GATE_SCRIPT" ]] || { log "FATAL: gate script missing: $GATE_SCRIPT"; exit 2; }

# setup <name> <config-json> → echoes case_dir (with config + empty atom dir)
setup() {
  local name="$1" cfg="$2"
  local case_dir="$OUT_BASE/$name"
  mkdir -p "$case_dir/atom/gate-cloud"
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
  local verdict_file="$atom_dir/gate-cloud/artifact-existence.json"
  if [[ ! -f "$verdict_file" ]]; then
    log "  -> FAIL: no verdict file"; CASES_FAILED+=("$name(no-verdict)"); return
  fi
  local actual_verdict
  actual_verdict=$(jq -r '.verdict' "$verdict_file" 2>/dev/null)
  if [[ "$actual_verdict" == "$expected_verdict" && "$actual_rc" == "$expected_rc" ]]; then
    log "  -> PASS"; CASES_PASSED+=("$name")
  else
    log "  -> FAIL: got verdict=$actual_verdict rc=$actual_rc"
    jq -c '{verdict,missing_artifacts,present_artifacts,reason}' "$verdict_file" 2>/dev/null | sed 's/^/       /' >&2 || true
    CASES_FAILED+=("$name(verdict=$actual_verdict,rc=$actual_rc)")
  fi
}

# Honest declaration shared by case 1 & 2 — the question is whether it's on disk.
K8S_CFG='{
  "cloud": {
    "artifact_kind": "k8s",
    "required_artifacts": [
      { "name": "k8s deploy", "glob": "k8s/*.yaml" },
      { "name": "hpa",        "glob": "k8s/hpa.yaml" }
    ]
  }
}'

# ── Case 1: artifacts present → PASS ───────────────────────────────────
CD=$(setup "1_artifacts_present" "$K8S_CFG")
mkdir -p "$CD/k8s"
printf '%s\n' 'apiVersion: apps/v1
kind: Deployment' > "$CD/k8s/deploy.yaml"
printf '%s\n' 'apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler' > "$CD/k8s/hpa.yaml"
run_case "1_artifacts_present" "$CD" "PASS" "0"

# ── Case 2: declared but k8s/ EMPTY → FAIL (the §12 shape) ─────────────
CD=$(setup "2_declared_empty_dir" "$K8S_CFG")
mkdir -p "$CD/k8s"   # dir exists, "configs ready" claimed — but no files inside
run_case "2_declared_empty_dir" "$CD" "FAIL" "1"

# ── Case 3: no cloud.required_artifacts → N/A (LAW-F6) ─────────────────
CD=$(setup "3_no_artifacts" '{"env":"test"}')
run_case "3_no_artifacts" "$CD" "N/A_PENDING_REVIEWER" "0"

# ── Aggregate ──────────────────────────────────────────────────────────
if [[ ${#CASES_FAILED[@]} -gt 0 ]]; then
  log "FAILED cases:"; for c in "${CASES_FAILED[@]}"; do log "  - $c"; done
  log "summary: pass=${#CASES_PASSED[@]} fail=${#CASES_FAILED[@]} verdict=FAIL"
  exit 1
fi
log "summary: pass=${#CASES_PASSED[@]} fail=0 verdict=PASS"
exit 0
