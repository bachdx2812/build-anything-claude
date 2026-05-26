#!/usr/bin/env bash
# deployment-runbook-test.sh — GATE-25 (v8.1).
# Verifies rollback + health-check are SCRIPTED (executable), not "documented in wiki".
# Boss can't say "we'll rollback if needed" if no script exists. Manual rollback = no rollback.
# Contract: 0 = both scripts exec OK; 1 = either missing or returns non-zero.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step deploy-runbook "starting"

RB_JSON=$(cfg "cloud.deploy.runbook" "{}")
if [[ "$RB_JSON" == "{}" || "$RB_JSON" == "null" ]]; then
  log_step deploy-runbook "no runbook configured — N/A_PENDING_REVIEWER"
  emit_na_pending "GATE-25" "deploy-runbook.json" "no cloud.deploy.runbook configured; reviewer must wire rollback_cmd + health_check_cmd OR mark atom as non-deployable"
  exit 0
fi

ROLLBACK=$(echo "$RB_JSON" | jq -r '.rollback_cmd // empty')
HEALTH=$(echo   "$RB_JSON" | jq -r '.health_check_cmd // empty')
DRY=$(echo      "$RB_JSON" | jq -r '.dry_run // true')   # default dry-run so we never actually rollback prod here

[[ -z "$ROLLBACK" ]] && { emit_na_pending "GATE-25" "deploy-runbook.json" "runbook.rollback_cmd missing"; exit 0; }
[[ -z "$HEALTH"   ]] && { emit_na_pending "GATE-25" "deploy-runbook.json" "runbook.health_check_cmd missing"; exit 0; }

FAIL=0
RESULTS="[]"

# Health-check — must actually run and return zero.
log_step deploy-runbook "health: $HEALTH"
HCLOG=$(mktemp)
set +e
( cd "$PROJECT_ROOT" && eval "$HEALTH" ) >"$HCLOG" 2>&1
HC_EXIT=$?
set -e
HC_SAMPLE=$(head -c 2000 "$HCLOG" | jq -Rs .)
rm -f "$HCLOG"
HC_OK=true; [[ "$HC_EXIT" -ne 0 ]] && { HC_OK=false; FAIL=$((FAIL+1)); }
RESULTS=$(jq -c --arg c "$HEALTH" --argjson e "$HC_EXIT" --argjson ok "$HC_OK" --arg s "$HC_SAMPLE" \
  '. + [{kind:"health",cmd:$c,exit:$e,passed:$ok,log:$s}]' <<< "$RESULTS")

# Rollback — by default dry-run (script just prints what it would do). LAW-10 forbids real prod rollback here.
log_step deploy-runbook "rollback (dry_run=$DRY): $ROLLBACK"
RBLOG=$(mktemp)
RBENV="BA_DRY_RUN=$DRY"
set +e
( cd "$PROJECT_ROOT" && env $RBENV bash -c "$ROLLBACK" ) >"$RBLOG" 2>&1
RB_EXIT=$?
set -e
RB_SAMPLE=$(head -c 2000 "$RBLOG" | jq -Rs .)
rm -f "$RBLOG"
RB_OK=true; [[ "$RB_EXIT" -ne 0 ]] && { RB_OK=false; FAIL=$((FAIL+1)); }
# Heuristic — if it returns 0 but log is empty, suspicious "echo nothing then exit 0" script.
LOG_LEN=$(echo -n "$RB_SAMPLE" | wc -c | tr -d ' ')
if [[ "$RB_OK" == "true" && "$LOG_LEN" -lt 4 ]]; then
  RB_OK=false; FAIL=$((FAIL+1))
  RB_SAMPLE=$(echo "empty log — suspected no-op rollback script" | jq -Rs .)
fi
RESULTS=$(jq -c --arg c "$ROLLBACK" --argjson e "$RB_EXIT" --argjson ok "$RB_OK" \
  --arg s "$RB_SAMPLE" --argjson dry "$DRY" \
  '. + [{kind:"rollback",cmd:$c,exit:$e,dry_run:$dry,passed:$ok,log:$s}]' <<< "$RESULTS")

PASSED=$([ "$FAIL" -eq 0 ] && echo true || echo false)
emit_evidence "GATE-25" "$PASSED" "deploy-runbook.json" \
  "{\"failed\":$FAIL,\"checks\":$RESULTS}"

if [[ "$PASSED" == "true" ]]; then log_step deploy-runbook "PASS"; exit 0
else log_step deploy-runbook "FAIL $FAIL runbook step(s) broken — rollback is theatrical, not real"; exit 1
fi
