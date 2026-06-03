#!/usr/bin/env bash
# behavioral-binding-check.sh — GATE-BEHAVIORAL-MUSTHAVE (UBS v8.9)
#
# The keystone for "UI present but feature dead" (slack+notion audit). v8.8
# GATE-PFC-WIRE accepts an interactive must-have feature on route + handler + test-file
# existence — which a dead UI plus a tautology test satisfies. For the DEFINING
# interactive features (realtime messaging, presence, live collab edit, calls) static
# wiring is necessary but NOT sufficient: the feature must PASS its behavioral gate.
#
# Catalog tags an interactive must_have with `behavioral:<key>`; this gate maps the
# key to a behavioral gate verdict and requires PASS:
#   rt_propagate     → gate-mechanical/rt-propagate.json   (GATE-RT-PROPAGATE)
#   presence_observe → gate-mechanical/rt-propagate.json
#   call_connect     → gate-mechanical/e2e-call.json       (GATE-CALL)
#
#   OUT = <atom>/gate-spec/behavioral-binding.json ; verdict ∈ {PASS, FAIL, N/A_PENDING_REVIEWER}
#
# Verdict rules (per tagged feature): behavioral PASS → ok; FAIL → binding FAIL;
#   N/A or verdict-file-missing → unproven → binding N/A (propagate, never upgrade to
#   PASS — LAW-F6). Aggregate: any FAIL ⇒ FAIL; else any unproven ⇒ N/A; else PASS.
# No behavioral-tagged must_have for the archetype ⇒ N/A (nothing to bind).
# LAW-CL-95: confidence + ambiguities[].

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CATALOG="$SCRIPT_DIR/feature-catalog.json"

ATOM_DIR=""; PROJECT_ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --atom-dir)     ATOM_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --catalog)      CATALOG="$2"; shift 2 ;;
    *) shift ;;
  esac
done
: "${ATOM_DIR:?--atom-dir required}"
: "${PROJECT_ROOT:=$(pwd)}"
OUT="$ATOM_DIR/gate-spec/behavioral-binding.json"
mkdir -p "$(dirname "$OUT")"
log() { echo "[$(date -u +%H:%M:%S)] [behavioral-binding] $*" >&2; }
TS() { date -u +%Y-%m-%dT%H:%M:%SZ; }
GATE="GATE-BEHAVIORAL-MUSTHAVE"; SCHEMA="ubs-v8.9-behavioral-binding"

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
  local r="$1" failed="$2" unproven="$3" rj; rj=$(printf '%s' "$r" | jq -Rs .)
  cat > "$OUT" <<JSON
{ "gate":"$GATE","passed":false,"verdict":"FAIL","reason":$rj,
  "failed_features":$failed,"unproven_features":$unproven,
  "confidence":100,"ambiguities":[],"schema_version":"$SCHEMA","ran_at":"$(TS)" }
JSON
  exit 1
}
emit_pass() {
  cat > "$OUT" <<JSON
{ "gate":"$GATE","passed":true,"verdict":"PASS","bound_features":$1,
  "confidence":100,"ambiguities":[],"schema_version":"$SCHEMA","ran_at":"$(TS)" }
JSON
  exit 0
}

[[ -f "$CATALOG" ]] || emit_na "feature catalog missing at $CATALOG"

# ── Resolve product_type → catalog key (mirror of GATE-WIRE-STACK) ────────
PRODUCT=""
[[ -f "$ATOM_DIR/intent/verdict.json" ]] && \
  PRODUCT=$(jq -r '.declared.product_type // empty' "$ATOM_DIR/intent/verdict.json" 2>/dev/null || true)
[[ -z "$PRODUCT" && -f "$ATOM_DIR/gate-spec/product-feature-coverage.json" ]] && \
  PRODUCT=$(jq -r '.product_type // empty' "$ATOM_DIR/gate-spec/product-feature-coverage.json" 2>/dev/null || true)
[[ -z "$PRODUCT" || "$PRODUCT" == "null" ]] && emit_na "no product_type resolved — cannot pick archetype must_have set"

resolve_catalog_key() {
  local t lc stripped k; lc=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if jq -e --arg t "$lc" '.[$t].must_have' "$CATALOG" >/dev/null 2>&1; then echo "$lc"; return; fi
  stripped=$(printf '%s' "$lc" | sed -E 's/-(mvp|lite|basic|prototype|poc|demo|toy|simple|minimal|v[0-9]+)$//')
  if [[ "$stripped" != "$lc" ]] && jq -e --arg t "$stripped" '.[$t].must_have' "$CATALOG" >/dev/null 2>&1; then echo "$stripped"; return; fi
  while IFS= read -r k; do
    [[ "$k" == _* ]] && continue
    if [[ "$lc" == "$k"* || "$k" == "$lc"* ]]; then echo "$k"; return; fi
  done < <(jq -r 'keys[]' "$CATALOG")
  return 1
}
KEY=$(resolve_catalog_key "$PRODUCT" || true)
[[ -z "$KEY" ]] && emit_na "no catalog archetype matched product_type=$PRODUCT — no behavioral floor to bind"

# ── Gather behavioral-tagged must_have features ────────────────────────────
TAGGED=$(jq -c --arg k "$KEY" '[.[$k].must_have[]? | select(.behavioral) | {name, behavioral}]' "$CATALOG" 2>/dev/null || echo "[]")
TN=$(echo "$TAGGED" | jq 'length')
[[ "$TN" -eq 0 ]] && emit_na "archetype '$KEY' has no behavioral-tagged must_have — nothing to bind"

# tag → verdict-file map
verdict_file_for() {
  case "$1" in
    rt_propagate|presence_observe) echo "gate-mechanical/rt-propagate.json" ;;
    call_connect)                  echo "gate-mechanical/e2e-call.json" ;;
    *)                             echo "" ;;
  esac
}

FAILED=(); UNPROVEN=(); BOUND=()
for i in $(seq 0 $((TN - 1))); do
  fname=$(echo "$TAGGED" | jq -r ".[$i].name")
  tag=$(echo "$TAGGED" | jq -r ".[$i].behavioral")
  rel=$(verdict_file_for "$tag")
  if [[ -z "$rel" ]]; then
    UNPROVEN+=("$fname (unknown behavioral tag '$tag' — add mapping)")
    continue
  fi
  vf="$ATOM_DIR/$rel"
  if [[ ! -f "$vf" ]]; then
    UNPROVEN+=("$fname → $tag gate did not run ($rel absent)")
    continue
  fi
  v=$(jq -r '.verdict' "$vf" 2>/dev/null || echo "")
  case "$v" in
    PASS)  BOUND+=("$fname ($tag PASS)") ;;
    FAIL)  FAILED+=("$fname → $tag FAIL") ;;
    *)     UNPROVEN+=("$fname → $tag $v") ;;
  esac
done

FAILED_JSON=$(printf '%s\n' "${FAILED[@]:-}" | jq -R . | jq -s 'map(select(length>0))')
UNPROVEN_JSON=$(printf '%s\n' "${UNPROVEN[@]:-}" | jq -R . | jq -s 'map(select(length>0))')
BOUND_JSON=$(printf '%s\n' "${BOUND[@]:-}" | jq -R . | jq -s 'map(select(length>0))')

if [[ ${#FAILED[@]} -gt 0 ]]; then
  log "FAIL: ${#FAILED[@]} interactive must_have feature(s) failed behavioral proof"
  emit_fail "interactive must_have feature(s) wired statically but FAILED behavioral proof — static route/handler/test is insufficient for: $(printf '%s; ' "${FAILED[@]}")" "$FAILED_JSON" "$UNPROVEN_JSON"
fi
if [[ ${#UNPROVEN[@]} -gt 0 ]]; then
  emit_na "behavioral proof unproven (gate N/A or did not run) for: $(printf '%s; ' "${UNPROVEN[@]}") — reviewer must verify these interactive features actually work"
fi
log "PASS: ${#BOUND[@]} behavioral-tagged must_have feature(s) proven"
emit_pass "$BOUND_JSON"
