#!/usr/bin/env bash
# multi-atom-loop.sh — Epic iterator (v8.5.2)
#
# Reads {epic_dir}/atom-plan/plan.json (SM persona output, validated by
# GATE-SM) and dispatches one /build-anything invocation per story in
# topological order. Each story's atom_brief becomes the next atom's
# input prompt.
#
# This script is a HARNESS, not the dispatcher itself. The orchestrator
# (Claude Code Skill tool, or boss-side Comet) consumes the printed
# execution plan + per-story directives.
#
# Output: {epic_dir}/atom-plan/run-log.json (running tally of seal
# status per story). Each downstream `/build-anything` invocation
# writes back into this log via --epic-dir and --story-id.
#
# Modes:
#   --print-plan  : emit execution order + atom_briefs to stdout (for
#                   the orchestrator to consume); no side effects
#   --record-seal : update run-log.json with {story_id, status, atom_dir,
#                   merkle_root, sealed_at}
#   --next        : print the next pending story whose depends_on are
#                   all sealed; exit 1 if none
#   --status      : print summary (sealed N of M)
#
# Exit codes: 0 OK, 1 no-eligible-story (next mode) OR plan invalid,
#             2 preflight error.

set -uo pipefail

EPIC_DIR=""
PROJECT_ROOT=""
MODE=""
STORY_ID=""
STATUS=""
ATOM_DIR=""
MERKLE_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --epic-dir)     EPIC_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --print-plan)   MODE="print-plan"; shift ;;
    --record-seal)  MODE="record-seal"; shift ;;
    --next)         MODE="next"; shift ;;
    --status)       MODE="status"; shift ;;
    --story-id)     STORY_ID="$2"; shift 2 ;;
    --status-value) STATUS="$2"; shift 2 ;;
    --atom-dir)     ATOM_DIR="$2"; shift 2 ;;
    --merkle-root)  MERKLE_ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${EPIC_DIR:?--epic-dir required}"
: "${MODE:?one of --print-plan|--record-seal|--next|--status required}"

PLAN="$EPIC_DIR/atom-plan/plan.json"
LOG="$EPIC_DIR/atom-plan/run-log.json"

log() { echo "[$(date -u +%H:%M:%S)] [multi-atom] $*" >&2; }

if [[ ! -f "$PLAN" ]]; then
  log "ERROR: plan.json not found at $PLAN"
  exit 2
fi
if ! jq -e . "$PLAN" >/dev/null 2>&1; then
  log "ERROR: plan.json is not valid JSON"
  exit 1
fi

# ── Initialise run-log.json if absent ─────────────────────────────
if [[ ! -f "$LOG" ]]; then
  jq '{epic: .epic, started_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")), stories: [.stories[] | {id, status: "pending", atom_dir: null, merkle_root: null, sealed_at: null}]}' \
    "$PLAN" > "$LOG"
fi

case "$MODE" in
  print-plan)
    # Emit the execution plan as JSON Lines: one row per story, in order.
    # Downstream orchestrator reads this and invokes /build-anything per row.
    jq -c '.execution_order[] as $sid | (.stories[] | select(.id == $sid)) | {id, atom_brief, depends_on, allowlist_hint, core_flows}' "$PLAN"
    ;;

  record-seal)
    : "${STORY_ID:?--story-id required for record-seal}"
    : "${STATUS:?--status-value required (sealed|failed|in_progress)}"
    tmp=$(mktemp)
    jq --arg sid "$STORY_ID" \
       --arg st "$STATUS" \
       --arg ad "${ATOM_DIR:-}" \
       --arg mr "${MERKLE_ROOT:-}" \
       --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.stories |= map(
          if .id == $sid then
            . + {status: $st, atom_dir: (if $ad == "" then .atom_dir else $ad end), merkle_root: (if $mr == "" then .merkle_root else $mr end), sealed_at: (if $st == "sealed" then $now else .sealed_at end)}
          else . end
        )' "$LOG" > "$tmp" && mv "$tmp" "$LOG"
    log "recorded $STORY_ID → $STATUS"
    ;;

  next)
    # Find first pending story whose all depends_on are sealed
    next_sid=""
    while IFS= read -r sid; do
      [[ -z "$sid" ]] && continue
      cur_status=$(jq -r --arg s "$sid" '.stories[] | select(.id == $s) | .status' "$LOG")
      [[ "$cur_status" != "pending" ]] && continue
      deps=$(jq -r --arg s "$sid" '.stories[] | select(.id == $s) | (.depends_on // [])[]' "$PLAN")
      all_sealed=true
      while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        dep_status=$(jq -r --arg d "$dep" '.stories[] | select(.id == $d) | .status' "$LOG")
        if [[ "$dep_status" != "sealed" ]]; then
          all_sealed=false
          break
        fi
      done <<< "$deps"
      if [[ "$all_sealed" == "true" ]]; then
        next_sid="$sid"
        break
      fi
    done < <(jq -r '.execution_order[]' "$PLAN")

    if [[ -z "$next_sid" ]]; then
      log "no eligible pending story (all sealed OR blocked by failed deps)"
      exit 1
    fi
    # Emit the full atom_brief + metadata for the next story
    jq -c --arg sid "$next_sid" '.stories[] | select(.id == $sid) | {id, atom_brief, depends_on, allowlist_hint, core_flows}' "$PLAN"
    ;;

  status)
    total=$(jq '.stories | length' "$LOG")
    sealed=$(jq '[.stories[] | select(.status == "sealed")] | length' "$LOG")
    failed=$(jq '[.stories[] | select(.status == "failed")] | length' "$LOG")
    in_prog=$(jq '[.stories[] | select(.status == "in_progress")] | length' "$LOG")
    pending=$(jq '[.stories[] | select(.status == "pending")] | length' "$LOG")
    jq -n \
      --argjson total "$total" \
      --argjson sealed "$sealed" \
      --argjson failed "$failed" \
      --argjson in_progress "$in_prog" \
      --argjson pending "$pending" \
      '{total: $total, sealed: $sealed, failed: $failed, in_progress: $in_progress, pending: $pending, percent_complete: ($sealed * 100 / $total | floor)}'
    ;;
esac
