#!/usr/bin/env bash
# slo-availability-test.sh — GATE-26 (v8.1).
# Verifies the atom has an error budget, a synthetic probe, and (optional) chaos confirms RTO.
# Without SLO, "available" is opinion. Boss can't measure burn rate from a feeling.
# Contract: 0 = SLO declared + probe green + RTO under budget; 1 = any violation.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step slo "starting"

SLO_JSON=$(cfg "cloud.slo" "{}")
if [[ "$SLO_JSON" == "{}" || "$SLO_JSON" == "null" ]]; then
  log_step slo "no SLO configured — N/A_PENDING_REVIEWER"
  emit_na_pending "GATE-26" "slo-availability.json" "no cloud.slo configured; reviewer must declare target/window/probe OR mark atom non-prod"
  exit 0
fi

TARGET=$(echo "$SLO_JSON" | jq -r '.target_pct // empty')           # e.g. 99.9
WINDOW=$(echo "$SLO_JSON" | jq -r '.window_days // 30')
PROBE_URL=$(echo "$SLO_JSON" | jq -r '.probe_url // empty')
PROBE_EXPECT=$(echo "$SLO_JSON" | jq -r '.probe_expect_status // 200')
N_PROBES=$(echo "$SLO_JSON" | jq -r '.probe_samples // 20')
RTO_S=$(echo "$SLO_JSON" | jq -r '.rto_seconds // empty')           # recovery time objective
CHAOS_CMD=$(echo "$SLO_JSON" | jq -r '.chaos_cmd // empty')         # optional — kills a pod / kills the process

[[ -z "$TARGET"    ]] && { emit_na_pending "GATE-26" "slo-availability.json" "slo.target_pct missing"; exit 0; }
[[ -z "$PROBE_URL" ]] && { emit_na_pending "GATE-26" "slo-availability.json" "slo.probe_url missing"; exit 0; }

FAIL=0; REASON=""

# 1. Synthetic probe — N samples sequential, count 2xx.
log_step slo "probe $N_PROBES samples → $PROBE_URL (expect $PROBE_EXPECT)"
OK=0; LAT_TOTAL=0
for i in $(seq 1 "$N_PROBES"); do
  RESP=$(curl -sS -o /dev/null -w '%{http_code} %{time_total}' "$PROBE_URL" 2>/dev/null || echo "000 0")
  CODE=$(echo "$RESP" | awk '{print $1}')
  LAT=$(echo "$RESP" | awk '{print $2}')
  LAT_TOTAL=$(awk -v a="$LAT_TOTAL" -v b="$LAT" 'BEGIN{printf "%.4f", a+b}')
  [[ "$CODE" == "$PROBE_EXPECT" ]] && OK=$((OK+1))
done
SUCCESS_PCT=$(awk -v ok="$OK" -v n="$N_PROBES" 'BEGIN{printf "%.4f", (ok/n)*100}')
AVG_LAT=$(awk -v t="$LAT_TOTAL" -v n="$N_PROBES" 'BEGIN{printf "%.4f", t/n}')
PROBE_OK=$(awk -v s="$SUCCESS_PCT" -v t="$TARGET" 'BEGIN{exit !(s>=t)}' && echo true || echo false)
[[ "$PROBE_OK" != "true" ]] && { FAIL=$((FAIL+1)); REASON="${REASON}probe success $SUCCESS_PCT% < target $TARGET%; "; }

# 2. RTO chaos probe — optional. Run chaos_cmd, then time how long until probe is green again.
RTO_OK="skipped"; RECOVERY_S="null"
if [[ -n "$CHAOS_CMD" && -n "$RTO_S" ]]; then
  log_step slo "chaos: $CHAOS_CMD"
  set +e
  ( cd "$PROJECT_ROOT" && eval "$CHAOS_CMD" ) >/dev/null 2>&1
  CHAOS_EXIT=$?
  set -e
  if [[ "$CHAOS_EXIT" -ne 0 ]]; then
    RTO_OK=false; FAIL=$((FAIL+1)); REASON="${REASON}chaos_cmd exit $CHAOS_EXIT; "
  else
    START=$(date +%s)
    DEADLINE=$((START + RTO_S))
    RECOVERED=false
    while [[ $(date +%s) -lt "$DEADLINE" ]]; do
      C=$(curl -sS -o /dev/null -w '%{http_code}' "$PROBE_URL" 2>/dev/null || echo 000)
      if [[ "$C" == "$PROBE_EXPECT" ]]; then RECOVERED=true; break; fi
      sleep 1
    done
    NOW=$(date +%s); RECOVERY_S=$((NOW - START))
    if [[ "$RECOVERED" == "true" ]]; then RTO_OK=true
    else RTO_OK=false; FAIL=$((FAIL+1)); REASON="${REASON}did not recover within RTO ${RTO_S}s; "; fi
  fi
fi

PASSED=$([ "$FAIL" -eq 0 ] && echo true || echo false)
emit_evidence "GATE-26" "$PASSED" "slo-availability.json" \
  "{\"target_pct\":$TARGET,\"window_days\":$WINDOW,\"samples\":$N_PROBES,\"success_pct\":$SUCCESS_PCT,\"avg_latency_s\":$AVG_LAT,\"rto_seconds_target\":${RTO_S:-null},\"rto_recovered\":\"$RTO_OK\",\"recovery_seconds\":$RECOVERY_S,\"reason\":\"$REASON\"}"

if [[ "$PASSED" == "true" ]]; then log_step slo "PASS $SUCCESS_PCT%/$TARGET% avg_lat=${AVG_LAT}s rto=$RTO_OK"; exit 0
else log_step slo "FAIL $REASON"; exit 1
fi
