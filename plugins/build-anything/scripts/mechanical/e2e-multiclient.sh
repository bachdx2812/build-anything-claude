#!/usr/bin/env bash
# e2e-multiclient.sh — GATE-RT-PROPAGATE (UBS v8.9)
#
# The hole this closes (slack+notion audit 2026-06-03): e2e-playwright.sh boots ONE
# browser context, so a "send message" journey passes on the SENDER's own optimistic
# UI echo — it never proves the message reached a SECOND client. Chat that is not
# actually realtime sails through. capability-wiring marks realtime_transport WIRED on
# a mere socket.io dep (import ≠ working loop). This gate runs a skill-authored 2-client
# probe: client A emits a unique marker, client B must observe it live (no reload),
# within budget. HTTP-poll-only / no-push = FAIL.
#
# Contract (single-integer stdout via exit code + JSON verdict file):
#   OUT = <atom>/gate-mechanical/rt-propagate.json
#   verdict ∈ {PASS, FAIL, N/A_PENDING_REVIEWER}
#
# LAW-RT-PROPAGATE: a realtime-class product (chat-app / collab-docs / messaging) with
#   realtime.enabled != true → FAIL (declared-but-skipped — same stance as GATE-25-E2E).
# LAW-F6: enabled but 0 journeys → FAIL (no vacuous pass); login/users/selectors not
#   declared → N/A_PENDING_REVIEWER (cannot drive the probe — reviewer must verify).
# LAW-CL-95: confidence + ambiguities[] on every verdict.
#
# bash 3.2 compatible. Trigger/eligibility checks all run BEFORE any stack boot so the
# meta-gate can exercise them without a live application.

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
OUT="$EVID/rt-propagate.json"
mkdir -p "$EVID"
TEMPLATE="$SKILL_ROOT/templates/probes/realtime-propagate.spec.ts"

GATE="GATE-RT-PROPAGATE"; SCHEMA="ubs-v8.9-rt-propagate"
TS() { date -u +%Y-%m-%dT%H:%M:%SZ; }

emit_na() {
  local reason="$1" rj; rj=$(printf '%s' "$reason" | jq -Rs .)
  cat > "$OUT" <<JSON
{ "gate": "$GATE", "passed": null, "verdict": "N/A_PENDING_REVIEWER",
  "reason": $rj, "confidence": 0, "ambiguities": [$rj], "review_required": true,
  "schema_version": "$SCHEMA", "ran_at": "$(TS)" }
JSON
  exit 0
}
emit_fail() {
  local reason="$1" details="${2:-{}}" rj; rj=$(printf '%s' "$reason" | jq -Rs .)
  cat > "$OUT" <<JSON
{ "gate": "$GATE", "passed": false, "verdict": "FAIL",
  "reason": $rj, "evidence": $details, "confidence": 100, "ambiguities": [],
  "schema_version": "$SCHEMA", "ran_at": "$(TS)" }
JSON
  exit 1
}
emit_pass() {
  local details="$1"
  cat > "$OUT" <<JSON
{ "gate": "$GATE", "passed": true, "verdict": "PASS",
  "evidence": $details, "confidence": 100, "ambiguities": [],
  "schema_version": "$SCHEMA", "ran_at": "$(TS)" }
JSON
  exit 0
}

log() { echo "[$(date -u +%H:%M:%S)] [rt-propagate] $*" >&2; }

# ── Resolve product archetype (for realtime-class eligibility) ─────────────
PRODUCT=""
[[ -f "$ATOM_DIR/intent/verdict.json" ]] && \
  PRODUCT=$(jq -r '.declared.product_type // empty' "$ATOM_DIR/intent/verdict.json" 2>/dev/null || true)
[[ -z "$PRODUCT" ]] && PRODUCT=$(cfg "product_type" "")
PRODUCT_LC=$(printf '%s' "$PRODUCT" | tr '[:upper:]' '[:lower:]')

is_realtime_class=0
case "$PRODUCT_LC" in
  *chat*|*messag*|*collab*|*notion*|*slack*|*discord*|*realtime*|*real-time*) is_realtime_class=1 ;;
esac
# Explicit realtime.enabled also marks the build as realtime-class.
RT_ENABLED=$(cfg "realtime.enabled" "false")
[[ "$RT_ENABLED" == "true" ]] && is_realtime_class=1

# ── LAW-RT-PROPAGATE: realtime product must not skip the gate ──────────────
if [[ "$RT_ENABLED" != "true" ]]; then
  if [[ "$is_realtime_class" -eq 1 ]]; then
    emit_fail "realtime-class product (product_type=$PRODUCT) but realtime.enabled != true — LAW-RT-PROPAGATE forbids skipping multi-client proof"
  fi
  emit_na "no realtime surface (product_type=$PRODUCT, realtime.enabled unset)"
fi

# ── LAW-F6: enabled but no journeys = vacuous → FAIL ───────────────────────
JOURNEYS=$(jq -c '.realtime.journeys // []' "$CONFIG" 2>/dev/null || echo "[]")
JN=$(echo "$JOURNEYS" | jq 'length')
if [[ "$JN" -eq 0 ]]; then
  emit_fail "realtime.enabled=true but realtime.journeys[] is empty — declare A→B propagation journeys (LAW-F6: no vacuous PASS)"
fi

# ── Probe drivability: login + users + per-journey selectors required ──────
LOGIN=$(jq -c '.realtime.login // {}' "$CONFIG" 2>/dev/null || echo "{}")
USERS=$(jq -c '.realtime.users // {}' "$CONFIG" 2>/dev/null || echo "{}")
have_login=$(echo "$LOGIN" | jq 'has("email_selector") and has("password_selector") and has("submit_selector")')
have_users=$(echo "$USERS" | jq '(.a.email? != null) and (.b.email? != null)')
if [[ "$have_login" != "true" || "$have_users" != "true" ]]; then
  emit_na "realtime.login{email_selector,password_selector,submit_selector} + realtime.users{a,b} not fully declared — cannot drive 2-client probe; reviewer must verify realtime manually"
fi
for i in $(seq 0 $((JN - 1))); do
  ssel=$(echo "$JOURNEYS" | jq -r ".[$i].send_selector // empty")
  osel=$(echo "$JOURNEYS" | jq -r ".[$i].observe_selector // empty")
  if [[ -z "$ssel" || -z "$osel" ]]; then
    jn=$(echo "$JOURNEYS" | jq -r ".[$i].name // \"#$i\"")
    emit_na "journey '$jn' missing send_selector/observe_selector — cannot probe propagation (declare both)"
  fi
done

[[ -f "$TEMPLATE" ]] || { log "FATAL: probe template missing: $TEMPLATE"; exit 2; }

# ── Boot stack, then run the probe per journey ─────────────────────────────
trap e2e_cleanup_spawned EXIT
e2e_boot_stack "$EVID" || emit_fail "stack failed to boot (see $EVID/*-boot.log)"
APP_URL="$E2E_FRONTEND_URL"
RUN_CWD=$(cfg "e2e.test_cwd" "$PROJECT_ROOT")
[[ "$RUN_CWD" = /* ]] || RUN_CWD="$PROJECT_ROOT/$RUN_CWD"
PROBE_DIR="$RUN_CWD/.ba-rt-probe"; mkdir -p "$PROBE_DIR"
SEQ=$(date +%s)
RESULTS='[]'; FAILED=()

for i in $(seq 0 $((JN - 1))); do
  jname=$(echo "$JOURNEYS" | jq -r ".[$i].name // \"journey-$i\"")
  jslug=$(printf '%s' "$jname" | tr '[:upper:] ' '[:lower:]-')
  marker="rt-${jslug}-${SEQ}-$$-$i"
  probe_cfg=$(jq -n \
    --arg app "$APP_URL" --argjson login "$LOGIN" --argjson users "$USERS" \
    --argjson journey "$(echo "$JOURNEYS" | jq ".[$i]")" --arg marker "$marker" \
    '{app_url:$app, login:$login, users:$users, journey:$journey, marker:$marker}')
  spec="$PROBE_DIR/rt-${jslug}-${i}.spec.ts"
  cp "$TEMPLATE" "$spec"
  log "journey '$jname' → probe $spec (marker=$marker)"
  set +e
  RT_PROBE_CONFIG="$probe_cfg" \
    bash -c "cd '$RUN_CWD' && npx playwright test '$spec' --reporter=line" \
    > "$EVID/rt-${jslug}-${i}.log" 2>&1
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then FAILED+=("$jname"); fi
  RESULTS=$(echo "$RESULTS" | jq --arg n "$jname" --argjson rc "$rc" '. + [{journey:$n, exit_code:$rc}]')
done

rm -rf "$PROBE_DIR" 2>/dev/null || true
DETAILS=$(jq -n --argjson r "$RESULTS" --arg app "$APP_URL" '{app_url:$app, journeys:$r}')

if [[ ${#FAILED[@]} -gt 0 ]]; then
  fj=$(printf '%s\n' "${FAILED[@]}" | jq -R . | jq -s .)
  emit_fail "realtime propagation failed — client B did not receive A's marker within budget for: $(printf '%s ' "${FAILED[@]}")" \
    "$(echo "$DETAILS" | jq --argjson f "$fj" '. + {failed_journeys:$f}')"
fi

emit_pass "$DETAILS"
