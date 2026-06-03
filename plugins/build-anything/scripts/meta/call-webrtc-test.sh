#!/usr/bin/env bash
# call-webrtc-test.sh — meta-gate for GATE-CALL (UBS v8.9).
#
# Reproduces the slack+notion audit failure (a dead call button) and asserts the
# v8.9 cure across the two static surfaces that ARE meta-testable (the live WebRTC
# connect/track assertion needs a real app + fake media and runs in a real build):
#
#   capability-wiring (GATE-WIRE-STACK) — realtime_media trigger:
#     A. declared call feature, NO webrtc dep            → FAIL (declared-not-wired)
#     B. declared call feature, simple-peer + RTCPeerConnection → PASS (wired)
#     C. call UI surface (route+symbol), NO webrtc       → FAIL (trigger-c dead button)
#     D. lone "API call"/"recall"/"callback" wording     → PASS (no trigger; FP guard)
#   e2e-call (GATE-CALL) — applicability:
#     E. no call surface                                  → N/A
#     F. call UI detected but undrivable (no selectors)   → N/A
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WIRE="$SKILL_ROOT/scripts/spec/capability-wiring-check.sh"
CALLG="$SKILL_ROOT/scripts/mechanical/e2e-call.sh"

OUT_BASE="$(mktemp -d -t call-meta-XXXXXX)"
declare -a PASSED FAILED
log() { echo "[meta:call] $*" >&2; }
[[ -f "$WIRE" && -f "$CALLG" ]] || { log "FATAL: gate scripts missing"; exit 2; }

# setup <name> <verdict-json> <pkg-deps-json> <intent-json> [src-files...]
# writes case dir; remaining args are "relpath::content" source files.
setup() {
  local name="$1" deps="$2" intent="$3"; shift 3
  local cd="$OUT_BASE/$name"; local atom="$cd/atom"
  mkdir -p "$atom/intent" "$atom/gate-spec" "$cd/src"
  printf '%s' "$intent" > "$atom/intent/verdict.json"
  printf '{"name":"x","dependencies":%s}' "$deps" > "$cd/package.json"
  printf '{}' > "$cd/.build-anything.json"
  local f
  for f in "$@"; do
    printf '%s' "${f#*::}" > "$cd/src/${f%%::*}"
  done
  echo "$cd"
}

run() {
  local name="$1" gate="$2" vfile="$3" want_v="$4" want_rc="$5" cd="$6"
  set +e
  bash "$gate" --atom-dir "$cd/atom" --project-root "$cd" >"$cd/out" 2>"$cd/err"
  local rc=$?
  set -e
  local f="$cd/atom/$vfile"
  if [[ ! -f "$f" ]]; then log "  $name -> FAIL (no verdict file; rc=$rc)"; FAILED+=("$name(no-verdict)"); return; fi
  local v; v=$(jq -r '.verdict' "$f" 2>/dev/null)
  if [[ "$v" == "$want_v" && "$rc" == "$want_rc" ]]; then
    log "  $name -> PASS (verdict=$v rc=$rc)"; PASSED+=("$name")
  else
    log "  $name -> FAIL (got $v/$rc want $want_v/$want_rc)"; FAILED+=("$name($v,$rc)")
  fi
}

DECL_CALL='{"declared":{"product_type":"todo-app","scale_tier":"mvp","feature_surface":[{"name":"video call"}]},"next_action":"READY","confidence":100}'
PLAIN_TODO='{"declared":{"product_type":"todo-app","scale_tier":"mvp"},"next_action":"READY","confidence":100}'

# A: declared call, no webrtc → WIRE-STACK FAIL
CD=$(setup "A_declared_unwired" '{"express":"^4"}' "$DECL_CALL" 'a.js::console.log(1)')
run "A_declared_unwired" "$WIRE" "gate-spec/capability-wiring.json" "FAIL" "1" "$CD"

# B: declared call, simple-peer + RTCPeerConnection → WIRE-STACK PASS
CD=$(setup "B_declared_wired" '{"express":"^4","simple-peer":"^9"}' "$DECL_CALL" \
  'call.js::import SimplePeer from "simple-peer"; const pc = new RTCPeerConnection(); pc.createOffer();')
run "B_declared_wired" "$WIRE" "gate-spec/capability-wiring.json" "PASS" "0" "$CD"

# C: call UI surface (route+symbol), no webrtc → WIRE-STACK FAIL (trigger-c dead button)
CD=$(setup "C_ui_deadbutton" '{"express":"^4"}' "$PLAIN_TODO" \
  'routes.jsx::export const routes=["/dashboard","/rooms/:id/call"];' \
  'CallButton.jsx::export function CallButton(){ return null }')
run "C_ui_deadbutton" "$WIRE" "gate-spec/capability-wiring.json" "FAIL" "1" "$CD"

# D: lone "API call"/recall/callback wording → no trigger → WIRE-STACK PASS (FP guard)
CD=$(setup "D_false_positive" '{"express":"^4"}' "$PLAIN_TODO" \
  'api.js::fetch("/api"); // make an API call' \
  'util.js::function recall(){}; const cb = callback;')
run "D_false_positive" "$WIRE" "gate-spec/capability-wiring.json" "PASS" "0" "$CD"

# E: no call surface → e2e-call N/A
CD=$(setup "E_no_call_na" '{"express":"^4"}' "$PLAIN_TODO" 'a.js::console.log(1)')
run "E_no_call_na" "$CALLG" "gate-mechanical/e2e-call.json" "N/A_PENDING_REVIEWER" "0" "$CD"

# F: call UI detected but undrivable → e2e-call N/A
CD=$(setup "F_undrivable_na" '{"express":"^4"}' "$PLAIN_TODO" \
  'routes.jsx::export const routes=["/call"];' \
  'VideoCall.jsx::export function VideoCall(){ return null }')
run "F_undrivable_na" "$CALLG" "gate-mechanical/e2e-call.json" "N/A_PENDING_REVIEWER" "0" "$CD"

if [[ ${#FAILED[@]} -gt 0 ]]; then
  log "FAILED: ${FAILED[*]}"; log "summary: pass=${#PASSED[@]} fail=${#FAILED[@]} verdict=FAIL"; exit 1
fi
log "summary: pass=${#PASSED[@]} fail=0 verdict=PASS"
exit 0
