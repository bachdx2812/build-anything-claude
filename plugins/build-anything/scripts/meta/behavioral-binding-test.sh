#!/usr/bin/env bash
# behavioral-binding-test.sh — meta-gate for GATE-BEHAVIORAL-MUSTHAVE (UBS v8.9).
#
# Asserts an interactive must_have feature cannot pass on static wiring alone — its
# mapped behavioral gate verdict governs. Plants a rt-propagate / e2e-call verdict in
# the atom and checks binding propagates it correctly.
#
# Cases:
#   1. chat-app + rt-propagate=FAIL            → binding FAIL (the slack case)
#   2. chat-app + rt-propagate=PASS            → binding PASS
#   3. chat-app + rt-propagate verdict absent  → binding N/A (unproven, never PASS)
#   4. todo-app (no behavioral-tagged must_have) → binding N/A (nothing to bind)
#   5. collab-docs + rt-propagate=FAIL         → binding FAIL (live collab editing)
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$SKILL_ROOT/scripts/spec/behavioral-binding-check.sh"
OUT_BASE="$(mktemp -d -t bbind-meta-XXXXXX)"
declare -a PASSED FAILED
log() { echo "[meta:behavioral-binding] $*" >&2; }
[[ -f "$GATE" ]] || { log "FATAL: gate missing: $GATE"; exit 2; }

# setup <name> <product_type> <rt_verdict|->
setup() {
  local name="$1" pt="$2" rtv="$3"
  local cd="$OUT_BASE/$name"; local atom="$cd/atom"
  mkdir -p "$atom/intent"
  printf '{"declared":{"product_type":"%s"},"next_action":"READY","confidence":100}' "$pt" > "$atom/intent/verdict.json"
  printf '{}' > "$cd/.build-anything.json"
  if [[ "$rtv" != "-" ]]; then
    mkdir -p "$atom/gate-mechanical"
    printf '{"gate":"GATE-RT-PROPAGATE","verdict":"%s"}' "$rtv" > "$atom/gate-mechanical/rt-propagate.json"
  fi
  echo "$cd"
}
run() {
  local name="$1" cd="$2" want_v="$3" want_rc="$4"
  set +e
  bash "$GATE" --atom-dir "$cd/atom" --project-root "$cd" >"$cd/out" 2>"$cd/err"
  local rc=$?
  set -e
  local f="$cd/atom/gate-spec/behavioral-binding.json"
  if [[ ! -f "$f" ]]; then log "  $name -> FAIL (no verdict; rc=$rc)"; FAILED+=("$name(no-verdict)"); return; fi
  local v; v=$(jq -r '.verdict' "$f" 2>/dev/null)
  if [[ "$v" == "$want_v" && "$rc" == "$want_rc" ]]; then
    log "  $name -> PASS (verdict=$v rc=$rc)"; PASSED+=("$name")
  else
    log "  $name -> FAIL (got $v/$rc want $want_v/$want_rc)"; FAILED+=("$name($v,$rc)")
  fi
}

run "1_chat_rt_fail"   "$(setup 1_chat_rt_fail   chat-app    FAIL)" "FAIL"                "1"
run "2_chat_rt_pass"   "$(setup 2_chat_rt_pass   chat-app    PASS)" "PASS"                "0"
run "3_chat_rt_absent" "$(setup 3_chat_rt_absent chat-app    -)"    "N/A_PENDING_REVIEWER" "0"
run "4_todo_nothing"   "$(setup 4_todo_nothing   todo-app    -)"    "N/A_PENDING_REVIEWER" "0"
run "5_collab_rt_fail" "$(setup 5_collab_rt_fail collab-docs FAIL)" "FAIL"                "1"

if [[ ${#FAILED[@]} -gt 0 ]]; then
  log "FAILED: ${FAILED[*]}"; log "summary: pass=${#PASSED[@]} fail=${#FAILED[@]} verdict=FAIL"; exit 1
fi
log "summary: pass=${#PASSED[@]} fail=0 verdict=PASS"
exit 0
