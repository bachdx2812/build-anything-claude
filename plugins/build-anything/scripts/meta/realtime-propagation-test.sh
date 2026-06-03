#!/usr/bin/env bash
# realtime-propagation-test.sh — meta-gate for GATE-RT-PROPAGATE (UBS v8.9).
#
# Asserts the eligibility/trigger logic that runs BEFORE any stack boot (the
# gameable static surface). The live 2-client browser run needs a real app and is
# exercised by the gate in a real build, not here.
#
# Cases:
#   1. realtime-class product (chat-app), realtime.enabled unset → FAIL
#      (LAW-RT-PROPAGATE: a chat app may not silently skip multi-client proof).
#   2. realtime.enabled=true but journeys[] empty → FAIL (LAW-F6 vacuous).
#   3. enabled + journeys but realtime.login/users not declared → N/A (undrivable).
#   4. non-realtime product (todo-app), enabled unset → N/A (no realtime surface).
#   5. enabled + login + users present but a journey lacks observe_selector → N/A.
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$SKILL_ROOT/scripts/mechanical/e2e-multiclient.sh"

OUT_BASE="$(mktemp -d -t rt-prop-meta-XXXXXX)"
declare -a PASSED FAILED
log() { echo "[meta:rt-propagate] $*" >&2; }

[[ -f "$GATE" ]] || { log "FATAL: gate missing: $GATE"; exit 2; }

# setup <name> <product_type> <config-json> → echoes case_dir
setup() {
  local name="$1" pt="$2" cfg="$3"
  local cd="$OUT_BASE/$name"; local atom="$cd/atom"
  mkdir -p "$atom/intent"
  cat > "$atom/intent/verdict.json" <<EOF
{ "declared": { "product_type": "$pt" }, "next_action": "READY", "confidence": 100 }
EOF
  printf '%s' "$cfg" > "$cd/.build-anything.json"
  echo "$cd"
}

run_case() {
  local name="$1" cd="$2" want_verdict="$3" want_rc="$4"
  local atom="$cd/atom"
  set +e
  bash "$GATE" --atom-dir "$atom" --project-root "$cd" >"$cd/out" 2>"$cd/err"
  local rc=$?
  set -e
  local vf="$atom/gate-mechanical/rt-propagate.json"
  if [[ ! -f "$vf" ]]; then log "  $name -> FAIL (no verdict file; rc=$rc)"; FAILED+=("$name(no-verdict)"); return; fi
  local v; v=$(jq -r '.verdict' "$vf" 2>/dev/null)
  if [[ "$v" == "$want_verdict" && "$rc" == "$want_rc" ]]; then
    log "  $name -> PASS (verdict=$v rc=$rc)"; PASSED+=("$name")
  else
    log "  $name -> FAIL (got verdict=$v rc=$rc, want $want_verdict/$want_rc)"
    FAILED+=("$name(verdict=$v,rc=$rc)")
  fi
}

# 1: chat-app, realtime not enabled → FAIL
CD=$(setup "1_chat_not_enabled" "chat-app" '{"product_type":"chat-app"}')
run_case "1_chat_not_enabled" "$CD" "FAIL" "1"

# 2: enabled, zero journeys → FAIL
CD=$(setup "2_enabled_no_journeys" "chat-app" '{"product_type":"chat-app","realtime":{"enabled":true,"journeys":[]}}')
run_case "2_enabled_no_journeys" "$CD" "FAIL" "1"

# 3: enabled + journeys but no login/users → N/A
CD=$(setup "3_no_login_users" "chat-app" '{"product_type":"chat-app","realtime":{"enabled":true,"journeys":[{"name":"send","send_selector":"#msg","observe_selector":".messages"}]}}')
run_case "3_no_login_users" "$CD" "N/A_PENDING_REVIEWER" "0"

# 4: non-realtime product, not enabled → N/A
CD=$(setup "4_todo_na" "todo-app" '{"product_type":"todo-app"}')
run_case "4_todo_na" "$CD" "N/A_PENDING_REVIEWER" "0"

# 5: enabled + login + users present, journey missing observe_selector → N/A
CD=$(setup "5_missing_selector" "chat-app" '{"product_type":"chat-app","realtime":{"enabled":true,"login":{"email_selector":"#e","password_selector":"#p","submit_selector":"#go"},"users":{"a":{"email":"a@x.io","password":"pw"},"b":{"email":"b@x.io","password":"pw"}},"journeys":[{"name":"send","send_selector":"#msg"}]}}')
run_case "5_missing_selector" "$CD" "N/A_PENDING_REVIEWER" "0"

if [[ ${#FAILED[@]} -gt 0 ]]; then
  log "FAILED: ${FAILED[*]}"; log "summary: pass=${#PASSED[@]} fail=${#FAILED[@]} verdict=FAIL"; exit 1
fi
log "summary: pass=${#PASSED[@]} fail=0 verdict=PASS"
exit 0
