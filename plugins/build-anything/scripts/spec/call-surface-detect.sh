#!/usr/bin/env bash
# call-surface-detect.sh — UI call-surface detector (UBS v8.9, GATE-CALL trigger c).
#
# slack+notion audit 2026-06-03: a 'call' button was added that the user never
# requested and that never worked. Trigger (a) declared-call and (b) chat@scale+
# miss that case at low tier. This detector scans the BUILT frontend for a call
# surface; when found, GATE-CALL becomes mandatory (capability-wiring requires
# realtime_media, e2e-call must prove connection) — so a dead call button FAILs.
#
# Anti-false-positive: requires ≥2 DISTINCT signal KINDS (route + symbol + label).
# A lone "API call" / "recall" / "callback" string is one weak signal at most and
# never fires. Word-boundary anchored.
#
# Escape hatch (LAW-F6): config `call.ui_autodetect:false` REQUIRES a `call.ui_autodetect_reason`;
# with a reason → disabled + reviewer note; without one → the disable is ignored
# (never a silent bypass) and the ambiguity is surfaced.
#
# Detector contract (NOT a pass/fail gate — it informs capability-wiring + e2e-call):
#   writes <atom>/gate-spec/call-surface.json, ALWAYS exits 0 (2 only on arg error).
#   Callers read `.detected` (bool).
#
# bash 3.2 compatible.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../backend/_common.sh"

ATOM_DIR=""; PROJECT_ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --atom-dir)     ATOM_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done
: "${PROJECT_ROOT:=$(pwd)}"
: "${ATOM_DIR:=$PROJECT_ROOT/.ba-atom}"
export PROJECT_ROOT ATOM_DIR
OUT="$ATOM_DIR/gate-spec/call-surface.json"
mkdir -p "$(dirname "$OUT")"

emit() {
  local detected="$1" disabled="$2" count="$3" signals="$4" reason="$5"
  local rj; rj=$(printf '%s' "$reason" | jq -Rs .)
  cat > "$OUT" <<JSON
{ "detector": "call-surface", "detected": $detected, "disabled": $disabled,
  "signal_count": $count, "signals": $signals, "reason": $rj,
  "schema_version": "ubs-v8.9-call-surface", "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)" }
JSON
  exit 0
}

# ── Escape hatch ───────────────────────────────────────────────────────
AUTODETECT=$(cfg "call.ui_autodetect" "true")
REASON=$(cfg "call.ui_autodetect_reason" "")
if [[ "$AUTODETECT" == "false" ]]; then
  if [[ -n "$REASON" ]]; then
    emit "false" "true" 0 "[]" "ui_autodetect disabled by config with reason: $REASON"
  fi
  # disabled without a reason → LAW-F6: do NOT silently bypass; keep detecting.
fi

# ── Signal scan ────────────────────────────────────────────────────────
INC=(--include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx'
     --include='*.mjs' --include='*.vue' --include='*.svelte' --include='*.html'
     --include='*.astro' --include='*.css')
EXC=(--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist
     --exclude-dir=build --exclude-dir=.next --exclude-dir=coverage
     --exclude-dir=tests --exclude-dir=test --exclude-dir=e2e
     --exclude-dir=__tests__ --exclude-dir=.ba-rt-probe)

# Route segment: "/call", "/huddle", "/rooms/123/video-call" …  (not /callback, /recall)
ROUTE_RE='/(call|huddle|meeting|video-?call|voice-?call|conference)\b'
# Component / handler / WebRTC symbols. Bare "Call" excluded (Recall, CallToAction).
SYMBOL_RE='\b(VideoCall|VoiceCall|StartCall|JoinCall|PlaceCall|CallButton|CallModal|CallScreen|CallView|CallPanel|HuddleButton|Huddle|useCall|initiateCall|startCall|joinCall|placeCall|incomingCall|RTCPeerConnection|getUserMedia|getDisplayMedia)\b'
# Visible action label. Requires an action verb + call/huddle (not "API call").
LABEL_RE='(start|join|place|begin|make|answer|accept|end) (a |an |the )?(call|huddle|video call|voice call|video chat|voice chat)'

SIGNALS=()
if grep -rqE "${INC[@]}" "${EXC[@]}" -- "$ROUTE_RE" "$PROJECT_ROOT" 2>/dev/null; then SIGNALS+=("route"); fi
if grep -rqE "${INC[@]}" "${EXC[@]}" -- "$SYMBOL_RE" "$PROJECT_ROOT" 2>/dev/null; then SIGNALS+=("symbol"); fi
if grep -rqiE "${INC[@]}" "${EXC[@]}" -- "$LABEL_RE" "$PROJECT_ROOT" 2>/dev/null; then SIGNALS+=("label"); fi

COUNT=${#SIGNALS[@]}
SIG_JSON=$(printf '%s\n' "${SIGNALS[@]:-}" | jq -R . | jq -s 'map(select(length>0))')

if [[ "$COUNT" -ge 2 ]]; then
  emit "true" "false" "$COUNT" "$SIG_JSON" "call surface detected: $COUNT signal kinds (${SIGNALS[*]}) — GATE-CALL mandatory"
fi
emit "false" "false" "$COUNT" "$SIG_JSON" "no call surface (need >=2 signal kinds; found $COUNT: ${SIGNALS[*]:-none})"
