#!/usr/bin/env bash
# intent-default-proceed-test.sh — meta-gate for LAW-INTENT-DEFAULT (UBS v9.0).
#
# Locks the fix for the FB-clone field report: "build facebook" triggered a 7-probe
# + 10-20-item feature interview ("took all day"). v9.0 adds curated archetype
# default-and-proceed: a known-archetype prompt pre-fills declared.* and records an
# `agent-default-archetype` history entry that satisfies the feature-surface
# confirmation guard WITHOUT an interactive round → READY in one pass, zero questions.
# Reconciles the standing rule "never stop mid-flow to confirm" with LAW-CL-95.
#
# Cases:
#   1. "build facebook" (default)        → READY, 0 ambiguities, declared pre-filled,
#                                           history has agent-default-archetype.
#   2. "build facebook" --interactive    → NEEDS_USER (auto-fill disabled; full interview).
#   3. "build a quux frobnicator widget" → NEEDS_USER (no archetype → full probe).
#   4. archetype defaults must NOT be vacuous: pre-filled feature_surface ≥ floor AND
#      includes the realtime-class feature that drives downstream gates.
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$SKILL_ROOT/scripts/intent/declare-intent.sh"

OUT_BASE="$(mktemp -d -t intent-default-meta-XXXXXX)"
declare -a PASSED FAILED
log() { echo "[meta:intent-default] $*" >&2; }

[[ -f "$GATE" ]] || { log "FATAL: gate missing: $GATE"; exit 2; }

# run_intent <name> <prompt> <extra-flags> → echoes atom dir
run_intent() {
  local name="$1" prompt="$2" flags="${3:-}"
  local cd="$OUT_BASE/$name"; mkdir -p "$cd"
  printf '%s' "$prompt" > "$cd/prompt.md"
  # shellcheck disable=SC2086
  bash "$GATE" --prompt "$cd/prompt.md" --atom-dir "$cd/atom" --project-root "$cd" $flags >"$cd/out" 2>"$cd/err" || true
  echo "$cd/atom"
}

pass() { log "  $1 -> PASS"; PASSED+=("$1"); }
fail() { log "  $1 -> FAIL ($2)"; FAILED+=("$1($2)"); }

# 1: known archetype, default mode → READY in one pass, no questions
A=$(run_intent "1_facebook_default" "build facebook")
V="$A/intent/verdict.json"; S="$A/intent/intent.json"
na=$(jq -r '.next_action' "$V" 2>/dev/null)
amb=$(jq -r '.ambiguities_remaining' "$V" 2>/dev/null)
pt=$(jq -r '.declared.product_type // "null"' "$V" 2>/dev/null)
prov=$(jq -r '[.history[] | select(.source=="agent-default-archetype")] | length' "$S" 2>/dev/null)
if [[ "$na" == "READY" && "$amb" == "0" && "$pt" != "null" && "$prov" -ge 1 ]]; then
  pass "1_facebook_default"
else
  fail "1_facebook_default" "next=$na amb=$amb pt=$pt prov=$prov"
fi

# 2: same prompt + --interactive → archetype auto-fill disabled → NEEDS_USER
A=$(run_intent "2_facebook_interactive" "build facebook" "--interactive")
na=$(jq -r '.next_action' "$A/intent/verdict.json" 2>/dev/null)
pt=$(jq -r '.declared.product_type // "null"' "$A/intent/verdict.json" 2>/dev/null)
if [[ "$na" == "NEEDS_USER" && "$pt" == "null" ]]; then
  pass "2_facebook_interactive"
else
  fail "2_facebook_interactive" "next=$na pt=$pt (expected NEEDS_USER + null)"
fi

# 3: unknown product → no archetype → full probe → NEEDS_USER
A=$(run_intent "3_unknown_product" "build a quux frobnicator widget")
na=$(jq -r '.next_action' "$A/intent/verdict.json" 2>/dev/null)
if [[ "$na" == "NEEDS_USER" ]]; then
  pass "3_unknown_product"
else
  fail "3_unknown_product" "next=$na (expected NEEDS_USER)"
fi

# 4: archetype defaults are substantive (not vacuous) — fs ≥ floor + realtime feature present
A=$(run_intent "4_defaults_substantive" "build facebook")
fs=$(jq -r '.declared.feature_surface | length' "$A/intent/verdict.json" 2>/dev/null)
rt=$(jq -r '[.declared.feature_surface[].name] | any(test("messag|chat"))' "$A/intent/verdict.json" 2>/dev/null)
if [[ "$fs" -ge 5 && "$rt" == "true" ]]; then
  pass "4_defaults_substantive"
else
  fail "4_defaults_substantive" "fs=$fs realtime_feature=$rt"
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
  log "FAILED: ${FAILED[*]}"; log "summary: pass=${#PASSED[@]} fail=${#FAILED[@]} verdict=FAIL"; exit 1
fi
log "summary: pass=${#PASSED[@]} fail=0 verdict=PASS"
exit 0
