#!/usr/bin/env bash
# reverify-test.sh — meta-gate for GATE-REVERIFY (v8.8 Stage 6).
#
# Asserts the independent-re-verification gate actually catches the audit's core
# disease (§1 / §16.7): "the build passes its OWN self-checks." The manifest is
# self-produced — GATE-REVERIFY must INDEPENDENTLY RE-RUN a sample of gates the
# manifest recorded as PASS and FAIL when a sworn-PASS gate does not reproduce.
#
#   1. PASS  — manifest says GATE-X passed:true; independent re-run reproduces
#              (rerun_cmd `true`, rc 0) → PASS.
#   2. FAIL  — manifest says GATE-X passed:true BUT independent re-run FAILS
#              (rerun_cmd `false`, rc!=0) → FAIL + self_attestation_breach:true.
#              This is the core catch — without it a build can cook its ledger.
#   3. N/A   — no reverify config (LAW-F6: never a silent PASS on empty input).
#   4. FAIL  — hyperscale + reverify.full!=true + sample covers GATE-A but not
#              GATE-B (also passed:true) → FAIL "sample incomplete".
#
# Why this exists: GATE-REVERIFY is the only gate whose evidence is produced by
# re-execution rather than by trusting the build's self-attestation. If a future
# edit collapsed it into "read manifest, trust it," the audit's central finding
# would silently return. This regression guards that.
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE_SCRIPT="$SKILL_ROOT/scripts/orchestrator/reverify-sample.sh"

OUT_BASE="$(mktemp -d -t reverify-meta-XXXXXX)"
declare -a CASES_PASSED CASES_FAILED

log() { echo "[meta:reverify] $*" >&2; }

[[ -f "$GATE_SCRIPT" ]] || { log "FATAL: gate script missing: $GATE_SCRIPT"; exit 2; }

# setup <name> <scale_tier|""> <manifest-gates-json> <config-json> → echoes case_dir
#   manifest-gates-json: the object placed at manifest.json#.gates (or "" for no manifest)
setup() {
  local name="$1" tier="$2" manifest_gates="$3" cfg="$4"
  local case_dir="$OUT_BASE/$name"
  local atom_dir="$case_dir/atom"
  mkdir -p "$atom_dir/intent"
  if [[ -n "$tier" ]]; then
    cat > "$atom_dir/intent/verdict.json" <<EOF
{ "declared": { "scale_tier": "$tier" }, "next_action": "READY", "confidence": 100 }
EOF
  else
    cat > "$atom_dir/intent/verdict.json" <<EOF
{ "declared": {}, "next_action": "READY", "confidence": 100 }
EOF
  fi
  if [[ -n "$manifest_gates" ]]; then
    cat > "$atom_dir/manifest.json" <<EOF
{ "atom": "$name", "summary": { "gates_total": 1 }, "gates": $manifest_gates }
EOF
  fi
  printf '%s' "$cfg" > "$case_dir/.build-anything.json"
  echo "$case_dir"
}

run_case() {
  local name="$1" case_dir="$2" expected_verdict="$3" expected_rc="$4" expected_breach="${5:-}"
  local atom_dir="$case_dir/atom"
  log "case=$name expect=verdict:$expected_verdict rc:$expected_rc breach:${expected_breach:-<any>}"
  set +e
  bash "$GATE_SCRIPT" --atom-dir "$atom_dir" --project-root "$case_dir" \
    >"$case_dir/stdout" 2>"$case_dir/stderr"
  local actual_rc=$?
  set -e
  local verdict_file="$atom_dir/gate-reverify/reverify.json"
  if [[ ! -f "$verdict_file" ]]; then
    log "  -> FAIL: no verdict file"; CASES_FAILED+=("$name(no-verdict)"); return
  fi
  local actual_verdict actual_breach
  actual_verdict=$(jq -r '.verdict' "$verdict_file" 2>/dev/null)
  # NB: use `if has(...)` not `// "n/a"` — jq's // falls through on false too,
  # which would mask a legitimate self_attestation_breach:false reading.
  actual_breach=$(jq -r 'if has("self_attestation_breach") then .self_attestation_breach else "n/a" end' "$verdict_file" 2>/dev/null)

  local ok=1
  [[ "$actual_verdict" == "$expected_verdict" ]] || ok=0
  [[ "$actual_rc" == "$expected_rc" ]] || ok=0
  if [[ -n "$expected_breach" && "$actual_breach" != "$expected_breach" ]]; then ok=0; fi

  if [[ "$ok" -eq 1 ]]; then
    log "  -> PASS"; CASES_PASSED+=("$name")
  else
    log "  -> FAIL: got verdict=$actual_verdict rc=$actual_rc breach=$actual_breach"
    jq -c '{verdict,self_attestation_breach,findings,reproduced,reason}' "$verdict_file" 2>/dev/null | sed 's/^/       /' >&2 || true
    CASES_FAILED+=("$name(verdict=$actual_verdict,rc=$actual_rc,breach=$actual_breach)")
  fi
}

# ── Case 1: manifest PASS reproduces on independent re-run → PASS ──────
CD=$(setup "1_reproduces" "growth" \
  '{"GATE-X":{"passed":true,"verdict":"PASS"}}' \
  '{"reverify":{"gates":[{"gate_id":"GATE-X","rerun_cmd":"true"}]}}')
run_case "1_reproduces" "$CD" "PASS" "0" "false"

# ── Case 2: manifest PASS but independent re-run FAILS → FAIL + breach ──
# The §1/§16.7 catch: build's own ledger says PASS, independent re-run disagrees.
CD=$(setup "2_breach" "growth" \
  '{"GATE-X":{"passed":true,"verdict":"PASS"}}' \
  '{"reverify":{"gates":[{"gate_id":"GATE-X","rerun_cmd":"false"}]}}')
run_case "2_breach" "$CD" "FAIL" "1" "true"

# ── Case 3a: no reverify config at all → N/A (LAW-F6) ──────────────────
CD=$(setup "3a_no_config" "growth" \
  '{"GATE-X":{"passed":true,"verdict":"PASS"}}' \
  '{"stack":{"database":"postgres"}}')
run_case "3a_no_config" "$CD" "N/A_PENDING_REVIEWER" "0"

# ── Case 3b: reverify declared but no manifest.json → N/A ──────────────
# Nothing recorded yet to independently re-verify against.
CD=$(setup "3b_no_manifest" "growth" "" \
  '{"reverify":{"gates":[{"gate_id":"GATE-X","rerun_cmd":"true"}]}}')
run_case "3b_no_manifest" "$CD" "N/A_PENDING_REVIEWER" "0"

# ── Case 4: hyperscale + partial sample (GATE-B uncovered) → FAIL ──────
# full!=true and the sample only re-verifies GATE-A while the manifest swears
# both GATE-A and GATE-B PASS → attestation hole → FAIL "sample incomplete".
CD=$(setup "4_hyperscale_incomplete" "hyperscale" \
  '{"GATE-A":{"passed":true,"verdict":"PASS"},"GATE-B":{"passed":true,"verdict":"PASS"}}' \
  '{"reverify":{"full":false,"gates":[{"gate_id":"GATE-A","rerun_cmd":"true"}]}}')
run_case "4_hyperscale_incomplete" "$CD" "FAIL" "1"

# ── Aggregate ──────────────────────────────────────────────────────────
if [[ ${#CASES_FAILED[@]} -gt 0 ]]; then
  log "FAILED cases:"; for c in "${CASES_FAILED[@]}"; do log "  - $c"; done
  log "summary: pass=${#CASES_PASSED[@]} fail=${#CASES_FAILED[@]} verdict=FAIL"
  exit 1
fi
log "summary: pass=${#CASES_PASSED[@]} fail=0 verdict=PASS"
exit 0
