#!/usr/bin/env bash
# e2e-call.sh — GATE-CALL (UBS v8.9)
#
# Runtime proof that a declared/detected call feature actually CONNECTS. The
# slack+notion audit (2026-06-03) shipped a call button that never worked; GATE-WIRE-STACK
# now requires realtime_media wired, and this gate proves the wire actually carries a
# call: two clients with fake media, A starts → B answers → both RTCPeerConnections
# reach connectionState='connected' + B gets a live remote track. Skill authors the
# probe (templates/probes/call-connect.spec.ts) so the build cannot fake it.
#
#   OUT = <atom>/gate-mechanical/e2e-call.json ; verdict ∈ {PASS, FAIL, N/A_PENDING_REVIEWER}
#
# Applicability (any ⇒ a call exists to test): call.enabled=true | declared call feature
#   | chat-app@scale+ | UI call-surface detected. None ⇒ N/A (no call surface).
# LAW-F6: applicable but undrivable (no peer_accessor reachable / no login/users /
#   no start_selector) ⇒ N/A_PENDING_REVIEWER (reviewer verifies the call by hand) —
#   never a silent PASS. LAW-CL-95: confidence + ambiguities[].
#
# bash 3.2 compatible. Applicability + drivability checks run BEFORE any boot so the
# meta-gate can exercise them without a live app + WebRTC stack.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../backend/_common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_e2e-boot.sh"

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
EVID="$ATOM_DIR/gate-mechanical"
OUT="$EVID/e2e-call.json"
mkdir -p "$EVID"
TEMPLATE="$SKILL_ROOT/templates/probes/call-connect.spec.ts"
GATE="GATE-CALL"; SCHEMA="ubs-v8.9-call"
TS() { date -u +%Y-%m-%dT%H:%M:%SZ; }

emit_na() {
  local r="$1" rj; rj=$(printf '%s' "$r" | jq -Rs .)
  cat > "$OUT" <<JSON
{ "gate":"$GATE","passed":null,"verdict":"N/A_PENDING_REVIEWER","reason":$rj,
  "confidence":0,"ambiguities":[$rj],"review_required":true,
  "schema_version":"$SCHEMA","ran_at":"$(TS)" }
JSON
  exit 0
}
emit_fail() {
  local r="$1" d="${2:-{}}" rj; rj=$(printf '%s' "$r" | jq -Rs .)
  cat > "$OUT" <<JSON
{ "gate":"$GATE","passed":false,"verdict":"FAIL","reason":$rj,"evidence":$d,
  "confidence":100,"ambiguities":[],"schema_version":"$SCHEMA","ran_at":"$(TS)" }
JSON
  exit 1
}
emit_pass() {
  cat > "$OUT" <<JSON
{ "gate":"$GATE","passed":true,"verdict":"PASS","evidence":$1,
  "confidence":100,"ambiguities":[],"schema_version":"$SCHEMA","ran_at":"$(TS)" }
JSON
  exit 0
}
log() { echo "[$(date -u +%H:%M:%S)] [e2e-call] $*" >&2; }

# ── Applicability: is there a call to test? (mirror of capability-wiring trigger) ──
PRODUCT=""; TIER=""
if [[ -f "$ATOM_DIR/intent/verdict.json" ]]; then
  PRODUCT=$(jq -r '.declared.product_type // empty' "$ATOM_DIR/intent/verdict.json" 2>/dev/null || true)
  TIER=$(jq -r '.declared.scale_tier // empty' "$ATOM_DIR/intent/verdict.json" 2>/dev/null || true)
fi
PRODUCT_LC=$(printf '%s' "$PRODUCT" | tr '[:upper:]' '[:lower:]')
FEATURES=""
[[ -f "$ATOM_DIR/intent/verdict.json" ]] && \
  FEATURES=$(jq -r '(.declared.feature_surface // [])[]? | if type=="object" then (.name // empty) else . end' "$ATOM_DIR/intent/verdict.json" 2>/dev/null || true)
FEATURES="$FEATURES
$(jq -r '(.feature_surface // [])[]? | if type=="object" then (.name // empty) else . end' "$CONFIG" 2>/dev/null || true)"

WHY=""
[[ "$(cfg "call.enabled" "")" == "true" ]] && WHY="call.enabled"
if [[ -z "$WHY" ]] && printf '%s' "$FEATURES" | grep -qiE 'huddle|voice[ /-]?call|video[ /-]?call|audio[ /-]?call|\bcalling\b|\bcalls\b|conferenc|video meeting|video chat|voice chat'; then
  WHY="declared-call-feature"
fi
if [[ -z "$WHY" && "$PRODUCT_LC" == "chat-app" ]]; then
  case "$TIER" in scale|hyperscale) WHY="chat-app@$TIER" ;; esac
fi
if [[ -z "$WHY" ]]; then
  bash "$SCRIPT_DIR/../spec/call-surface-detect.sh" --project-root "$PROJECT_ROOT" --atom-dir "$ATOM_DIR" >/dev/null 2>&1 || true
  if [[ -f "$ATOM_DIR/gate-spec/call-surface.json" ]]; then
    [[ "$(jq -r '.detected' "$ATOM_DIR/gate-spec/call-surface.json" 2>/dev/null || echo false)" == "true" ]] && WHY="ui-detected-call-surface"
  fi
fi
[[ -z "$WHY" ]] && emit_na "no call surface (no call.enabled, no declared call feature, not chat-app@scale+, no UI call surface detected)"
log "applicable via: $WHY"

# ── Drivability: need login + users + start_selector + a peer accessor ─────
LOGIN=$(jq -c '.realtime.login // .call.login // {}' "$CONFIG" 2>/dev/null || echo "{}")
USERS=$(jq -c '.realtime.users // .call.users // {}' "$CONFIG" 2>/dev/null || echo "{}")
START_SEL=$(cfg "call.start_selector" "")
ACCESSOR=$(cfg "call.peer_accessor" "window.__rtcPeer")
have_login=$(echo "$LOGIN" | jq 'has("email_selector") and has("password_selector") and has("submit_selector")')
have_users=$(echo "$USERS" | jq '(.a.email? != null) and (.b.email? != null)')
if [[ "$have_login" != "true" || "$have_users" != "true" || -z "$START_SEL" ]]; then
  emit_na "call surface present ($WHY) but undrivable — need call.start_selector + login{email_selector,password_selector,submit_selector} + users{a,b}; and the app MUST expose its RTCPeerConnection at $ACCESSOR under the E2E flag. Reviewer must verify the call manually."
fi
[[ -f "$TEMPLATE" ]] || { log "FATAL: probe template missing: $TEMPLATE"; exit 2; }

# ── Boot + run the WebRTC probe ────────────────────────────────────────────
trap e2e_cleanup_spawned EXIT
e2e_boot_stack "$EVID" || emit_fail "stack failed to boot (see $EVID/*-boot.log)"
APP_URL="$E2E_FRONTEND_URL"
RUN_CWD=$(cfg "e2e.test_cwd" "$PROJECT_ROOT"); [[ "$RUN_CWD" = /* ]] || RUN_CWD="$PROJECT_ROOT/$RUN_CWD"
PROBE_DIR="$RUN_CWD/.ba-call-probe"; mkdir -p "$PROBE_DIR"
CALL_CFG=$(jq -n \
  --arg app "$APP_URL" --argjson login "$LOGIN" --argjson users "$USERS" \
  --arg accessor "$ACCESSOR" --arg start "$START_SEL" \
  --arg accept "$(cfg "call.accept_selector" "")" \
  --argjson auto "$(cfg "call.auto_answer" "false")" \
  --arg nav "$(cfg "call.nav_url" "")" \
  --argjson budget "$(cfg "call.budget_ms" "15000")" \
  '{app_url:$app, login:$login, users:$users,
    call:{peer_accessor:$accessor, start_selector:$start,
          accept_selector:$accept, auto_answer:$auto,
          nav_url:$nav, budget_ms:$budget}}')
spec="$PROBE_DIR/call-connect.spec.ts"
cp "$TEMPLATE" "$spec"
log "running call probe → $spec (accessor=$ACCESSOR)"
set +e
CALL_PROBE_CONFIG="$CALL_CFG" \
  bash -c "cd '$RUN_CWD' && npx playwright test '$spec' --reporter=line" \
  > "$EVID/e2e-call.log" 2>&1
rc=$?
set -e
rm -rf "$PROBE_DIR" 2>/dev/null || true
DETAILS=$(jq -n --arg app "$APP_URL" --arg why "$WHY" --argjson rc "$rc" \
  --arg log "$EVID/e2e-call.log" '{app_url:$app, trigger:$why, exit_code:$rc, log_path:$log}')

if [[ "$rc" -ne 0 ]]; then
  emit_fail "WebRTC call did not connect — peers never reached connectionState='connected' or no live remote track (trigger=$WHY)" "$DETAILS"
fi
emit_pass "$DETAILS"
