#!/usr/bin/env bash
# lighthouse-check.sh — GATE-14 (FE) Lighthouse perf + a11y gate.
# 3-run median to mitigate flakiness (per Phase 05 risk).

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step lighthouse "starting"

THRESH_PERF=$(threshold "gates.performance.lighthouse_perf_mobile" 90)
THRESH_A11Y=$(threshold "gates.performance.lighthouse_a11y" 95)
OUT="$ATOM_DIR/gate-mechanical/lighthouse.json"

# URLs to test from .build-anything.json#frontend.test_urls[]
URLS_RAW=$( jq -r '.frontend.test_urls[]?' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || true )
if [[ -z "$URLS_RAW" ]]; then
  log_step lighthouse "no test_urls — N/A_PENDING_REVIEWER (F6: no vacuous PASS)"
  emit_na_pending "GATE-14-lighthouse" "$OUT" "no frontend.test_urls configured; reviewer must add URLs OR confirm atom has no FE surface"
  exit 0
fi

require_cmd lighthouse "install: npm i -g lighthouse"

PERF_MEDIAN=100; A11Y_MEDIAN=100
WORST_URL=""
URLS_TESTED=0
while read -r URL; do
  [[ -z "$URL" ]] && continue
  PERF_RUNS=(); A11Y_RUNS=()
  for i in 1 2 3; do
    JSON=$(lighthouse "$URL" --quiet --chrome-flags="--headless" --output=json --output-path=stdout 2>/dev/null || echo "{}")
    PERF_RUNS+=( "$(echo "$JSON" | jq -r '.categories.performance.score*100' 2>/dev/null || echo 0)" )
    A11Y_RUNS+=( "$(echo "$JSON" | jq -r '.categories.accessibility.score*100' 2>/dev/null || echo 0)" )
  done
  # median (sort + middle)
  PERF=$(printf "%s\n" "${PERF_RUNS[@]}" | sort -n | awk 'NR==2{print}')
  A11Y=$(printf "%s\n" "${A11Y_RUNS[@]}" | sort -n | awk 'NR==2{print}')
  log_step lighthouse "url=$URL perf=$PERF a11y=$A11Y"
  if (( $(awk -v p="$PERF" -v m="$PERF_MEDIAN" 'BEGIN{print (p<m)?1:0}') )); then PERF_MEDIAN="$PERF"; WORST_URL="$URL"; fi
  if (( $(awk -v a="$A11Y" -v m="$A11Y_MEDIAN" 'BEGIN{print (a<m)?1:0}') )); then A11Y_MEDIAN="$A11Y"; fi
  URLS_TESTED=$((URLS_TESTED + 1))
done <<< "$URLS_RAW"

PASSED_PERF=$(awk -v s="$PERF_MEDIAN" -v t="$THRESH_PERF" 'BEGIN{print (s>=t)?"true":"false"}')
PASSED_A11Y=$(awk -v s="$A11Y_MEDIAN" -v t="$THRESH_A11Y" 'BEGIN{print (s>=t)?"true":"false"}')
PASSED="false"; [[ "$PASSED_PERF" == "true" && "$PASSED_A11Y" == "true" ]] && PASSED="true"

# v8.3 — urls_tested is the lighthouse equivalent of scope_files: prevents
# "perf=92" headline from masking the fact that only 1 of 5 declared URLs was reached.
emit_json "GATE-14-lighthouse" "$PERF_MEDIAN" "$THRESH_PERF" "$PASSED" "$OUT" \
  "{\"a11y\":$A11Y_MEDIAN,\"a11y_threshold\":$THRESH_A11Y,\"a11y_passed\":$PASSED_A11Y,\"worst_url\":\"$WORST_URL\",\"urls_tested\":$URLS_TESTED}"

if [[ "$PASSED" == "true" ]]; then
  log_step lighthouse "PASS perf=$PERF_MEDIAN a11y=$A11Y_MEDIAN"
  exit 0
else
  log_step lighthouse "FAIL perf=$PERF_MEDIAN (≥$THRESH_PERF) a11y=$A11Y_MEDIAN (≥$THRESH_A11Y)"
  exit 1
fi
