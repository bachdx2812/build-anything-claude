#!/usr/bin/env bash
# declare-intent.sh — Stage 0.1 INTENT DECLARATION runner.
#
# Contract:
#   - Reads the raw user prompt from --prompt <file>.
#   - Maintains intent.json with: declared, confidence (0-100), ambiguities[], iter.
#   - Emits next-action verdict:
#       READY        → confidence ≥ 95, agent may continue to Stage 0.5
#       NEEDS_USER   → ambiguities[] populated, agent MUST ask user (AskUserQuestion or harness eq.)
#       HALT         → iter ≥ max_iter AND still < 95 → halt build, escalate to human
#
# This script does NOT itself extract intent. It (a) scaffolds state, (b) runs a
# heuristic ambiguity probe to seed the question list, (c) records the per-iter
# transcript. The actual semantic intent extraction is performed by the agent
# (LLM) reading sub-skills/intent/SKILL.md, which mutates intent.json between
# invocations of this script.
#
# Why this split: the confidence loop requires LLM reasoning + user interaction,
# which bash cannot perform. Bash owns the file format, the iteration counter,
# and the LAW-F6 vacuous-PASS guard.
#
# Usage:
#   declare-intent.sh --prompt <file> --atom-dir <dir> --project-root <dir> \
#                     [--max-iter 5] [--threshold 95]
#
# Outputs:
#   {atom_dir}/intent/intent.json          — current state (mutated each iter)
#   {atom_dir}/intent/iter-N.json          — frozen snapshot per iteration
#   {atom_dir}/intent/raw-prompt.md        — verbatim copy of user prompt
#   {atom_dir}/intent/transcript.md        — append-only Q&A log
#   {atom_dir}/intent/verdict.json         — final verdict consumable by orchestrator
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../mechanical/_common.sh"

PROMPT_FILE=""
ATOM_DIR=""
PROJECT_ROOT=""
MAX_ITER=5
THRESHOLD=95

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt)       PROMPT_FILE="$2"; shift 2 ;;
    --atom-dir)     ATOM_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --max-iter)     MAX_ITER="$2"; shift 2 ;;
    --threshold)    THRESHOLD="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
: "${ATOM_DIR:?--atom-dir required}"
: "${PROJECT_ROOT:=$(pwd)}"

INTENT_DIR="$ATOM_DIR/intent"
mkdir -p "$INTENT_DIR"

STATE="$INTENT_DIR/intent.json"
VERDICT="$INTENT_DIR/verdict.json"
TRANSCRIPT="$INTENT_DIR/transcript.md"

# ── Bootstrap state on first run ────────────────────────────────────
if [[ ! -f "$STATE" ]]; then
  : "${PROMPT_FILE:?--prompt required on first run}"
  cp "$PROMPT_FILE" "$INTENT_DIR/raw-prompt.md"
  cat > "$STATE" <<'JSON'
{
  "iter": 0,
  "confidence": 0,
  "declared": {
    "product_type": null,
    "primary_user": null,
    "core_flows": [],
    "success_criteria": [],
    "out_of_scope": [],
    "constraints": [],
    "scale_tier": null,
    "cost": {
      "monthly_usd_ceiling": null,
      "currency": "USD"
    },
    "team": {
      "size": null,
      "ops_maturity": null
    }
  },
  "ambiguities": [],
  "history": []
}
JSON
  printf "# Intent declaration transcript\n\n" > "$TRANSCRIPT"
fi

ITER=$(jq -r '.iter' "$STATE")
CONFIDENCE=$(jq -r '.confidence' "$STATE")
ITER=$((ITER + 1))

log_step intent "iter=$ITER confidence=$CONFIDENCE threshold=$THRESHOLD"

# ── Heuristic ambiguity probe (deterministic floor) ─────────────────
# The agent supplements this with LLM analysis. These checks only catch the
# most obvious gaps so the agent has something to ask about even if it gets
# the LLM step wrong.

PROBE_AMBIG=()
DECL_PRODUCT=$(jq -r '.declared.product_type // empty' "$STATE")
DECL_USER=$(jq -r '.declared.primary_user // empty' "$STATE")
DECL_FLOWS=$(jq -r '.declared.core_flows | length' "$STATE")
DECL_SUCCESS=$(jq -r '.declared.success_criteria | length' "$STATE")
DECL_TIER=$(jq -r '.declared.scale_tier // empty' "$STATE")
DECL_COST=$(jq -r '.declared.cost.monthly_usd_ceiling // empty' "$STATE")
DECL_TEAM_SIZE=$(jq -r '.declared.team.size // empty' "$STATE")
DECL_TEAM_OPS=$(jq -r '.declared.team.ops_maturity // empty' "$STATE")

if [[ -z "$DECL_PRODUCT" ]]; then
  PROBE_AMBIG+=('{"field":"product_type","question":"What is the product type? (e.g. youtube-clone, todo-app, internal-tool — match feature-catalog.json if possible)","required":true}')
fi
if [[ -z "$DECL_USER" ]]; then
  PROBE_AMBIG+=('{"field":"primary_user","question":"Who is the primary user? (role, expertise level, context of use)","required":true}')
fi
if [[ "$DECL_FLOWS" -lt 1 ]]; then
  PROBE_AMBIG+=('{"field":"core_flows","question":"List 2-5 core user flows the build must support (e.g. \"register → upload video → watch own video\")","required":true}')
fi
if [[ "$DECL_SUCCESS" -lt 1 ]]; then
  PROBE_AMBIG+=('{"field":"success_criteria","question":"How will we know the build is done? List 2-5 mechanically-checkable success criteria.","required":true}')
fi
# v8.5 — scale-tier + cost-envelope + team-fitness probes.
# These drive Stage 1.D GATE-STACK and Stage 1.B Architect persona's
# production-design.md. Without them the build defaults to MVP-mindset
# stacks even for product types where "MVP" means "dies on launch day".
if [[ -z "$DECL_TIER" ]]; then
  PROBE_AMBIG+=('{"field":"scale_tier","question":"What scale tier? Choose ONE: mvp (≤1K DAU, demo / launch), growth (1K-100K DAU, post-PMF), scale (100K-10M DAU, multi-region), hyperscale (>10M DAU, global). This drives stack + architecture requirements; picking wrong = over- or under-engineered.","required":true}')
fi
if [[ -z "$DECL_COST" ]]; then
  PROBE_AMBIG+=('{"field":"cost.monthly_usd_ceiling","question":"Monthly cost ceiling in USD? Integer. The stack-fitness gate refuses stacks whose estimated infrastructure cost exceeds this. Be honest — declaring $100 for a youtube-clone forces SQLite+local-disk, which then fails GATE-STACK as toy.","required":true}')
fi
if [[ -z "$DECL_TEAM_SIZE" ]]; then
  PROBE_AMBIG+=('{"field":"team.size","question":"Engineering team size (integer; just devs who will operate this). The team-fitness check refuses architectures whose ops surface exceeds team capacity — e.g. solo engineer + Kubernetes + 5 microservices = HALT.","required":true}')
fi
if [[ -z "$DECL_TEAM_OPS" ]]; then
  PROBE_AMBIG+=('{"field":"team.ops_maturity","question":"Ops maturity: solo (1 eng, no on-call), small (2-5, business hours), medium (6-20, 24/7 on-call), enterprise (>20, dedicated SRE). Drives observability + deployment topology requirements.","required":true}')
fi

# Merge probe into state's ambiguities — but do NOT clobber LLM-added ones.
# Existing ambiguities are kept; probe entries are appended only if not already
# present (deduped by field name).
PROBE_JSON="[$(IFS=,; echo "${PROBE_AMBIG[*]:-}")]"
jq --argjson probe "$PROBE_JSON" '
  .ambiguities as $existing
  | [$probe[] | select(.field as $f | ($existing | map(.field) | index($f) | not))] as $new
  | .ambiguities = ($existing + $new)
' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"

# ── Score (basic floor) ─────────────────────────────────────────────
# Agent OVERWRITES this with its own confidence score; we only seed a floor so
# a brand-new intent.json with all fields null does not accidentally read as
# confidence=100. The agent reasoning is authoritative.
REMAINING_AMBIG=$(jq -r '.ambiguities | length' "$STATE")
if [[ "$CONFIDENCE" -eq 0 ]]; then
  FLOOR_CONF=$((100 - REMAINING_AMBIG * 25))
  [[ $FLOOR_CONF -lt 0 ]] && FLOOR_CONF=0
  jq --argjson c "$FLOOR_CONF" '.confidence = $c' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
  CONFIDENCE=$FLOOR_CONF
fi

jq --argjson i "$ITER" '.iter = $i' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"

# ── Snapshot ────────────────────────────────────────────────────────
cp "$STATE" "$INTENT_DIR/iter-$ITER.json"

# ── Verdict logic (LAW-F6 + LAW-CL-95) ──────────────────────────────
NEXT_ACTION="NEEDS_USER"
PASSED="null"
NA_REASON=""

if [[ "$CONFIDENCE" -ge "$THRESHOLD" ]]; then
  NEXT_ACTION="READY"
  PASSED="true"
elif [[ "$ITER" -ge "$MAX_ITER" ]]; then
  NEXT_ACTION="HALT"
  PASSED="false"
  NA_REASON="confidence still $CONFIDENCE after $ITER iterations (threshold $THRESHOLD)"
fi

# Vacuous-PASS guard: if PASS but core fields still null, force HALT.
# v8.5 — scale_tier + cost + team are also gate-blocking. Without them every
# downstream gate makes assumptions the spec author never validated.
if [[ "$NEXT_ACTION" == "READY" ]]; then
  PT=$(jq -r '.declared.product_type // empty' "$STATE")
  PU=$(jq -r '.declared.primary_user // empty' "$STATE")
  FL=$(jq -r '.declared.core_flows | length' "$STATE")
  SC=$(jq -r '.declared.success_criteria | length' "$STATE")
  TIER=$(jq -r '.declared.scale_tier // empty' "$STATE")
  COST=$(jq -r '.declared.cost.monthly_usd_ceiling // empty' "$STATE")
  TSIZE=$(jq -r '.declared.team.size // empty' "$STATE")
  TOPS=$(jq -r '.declared.team.ops_maturity // empty' "$STATE")
  if [[ -z "$PT" || -z "$PU" || "$FL" -lt 1 || "$SC" -lt 1 ]]; then
    NEXT_ACTION="HALT"
    PASSED="false"
    NA_REASON="LAW-F6 GUARD: confidence ≥ threshold but core fields still empty — score is vacuous"
  elif [[ -z "$TIER" || -z "$COST" || -z "$TSIZE" || -z "$TOPS" ]]; then
    NEXT_ACTION="HALT"
    PASSED="false"
    NA_REASON="LAW-F6 GUARD v8.5: scale_tier/cost.monthly_usd_ceiling/team.size/team.ops_maturity missing — downstream gates would silently default to MVP-mindset"
  fi
fi

# ── Emit verdict.json ───────────────────────────────────────────────
jq -n \
  --arg gate "GATE-INTENT" \
  --argjson iter "$ITER" \
  --argjson conf "$CONFIDENCE" \
  --argjson thresh "$THRESHOLD" \
  --argjson maxiter "$MAX_ITER" \
  --argjson amb "$REMAINING_AMBIG" \
  --arg action "$NEXT_ACTION" \
  --argjson passed "$PASSED" \
  --arg reason "$NA_REASON" \
  --slurpfile state "$STATE" \
  '{
    gate: $gate,
    schema_version: "ubs-v8.5-intent",
    iter: $iter,
    max_iter: $maxiter,
    confidence: $conf,
    threshold: $thresh,
    ambiguities_remaining: $amb,
    next_action: $action,
    passed: $passed,
    na_pending_reason: (if $reason == "" then null else $reason end),
    declared: $state[0].declared,
    open_questions: $state[0].ambiguities
  }' > "$VERDICT"

log_step intent "verdict=$NEXT_ACTION conf=$CONFIDENCE ambig=$REMAINING_AMBIG"
echo "$NEXT_ACTION"
