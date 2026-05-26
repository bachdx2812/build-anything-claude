#!/usr/bin/env bash
# cost-tracker.sh — F8 fix. AL-4 breaker becomes ACTUAL not theatrical.
# Wraps every reviewer / autoresearch invocation. Increments per-atom and
# per-hour ledgers. Aborts the parent process when caps are exceeded.
#
# Usage:
#   ./cost-tracker.sh --atom-dir <dir> --record <usd>          # increment ledger
#   ./cost-tracker.sh --atom-dir <dir> --check                  # exit 1 if cap exceeded
#   ./cost-tracker.sh --atom-dir <dir> --report                 # dump current spend
#
# Caps (from automation-ladder.md):
#   per atom: $5  → AL-4 self-heal HALT
#   per hour: $20 → global HALT (kill switch)

set -euo pipefail

ATOM_DIR=""; ACTION=""; USD="0"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --atom-dir) ATOM_DIR="$2"; shift 2 ;;
    --record)   ACTION="record"; USD="$2"; shift 2 ;;
    --check)    ACTION="check"; shift ;;
    --report)   ACTION="report"; shift ;;
    *) shift ;;
  esac
done
: "${ATOM_DIR:?--atom-dir required}"
: "${ACTION:?--record|--check|--report required}"

PROJECT_ROOT="$(cd "$ATOM_DIR/../.." 2>/dev/null && pwd || echo "$ATOM_DIR")"
ATOM_LEDGER="$ATOM_DIR/.cost-ledger.jsonl"
HOUR_LEDGER="$PROJECT_ROOT/.ba-cost-hour.jsonl"
ATOM_CAP=$(jq -r '.thresholds.atom_cost_usd_max // 5'   "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo 5)
HOUR_CAP=$(jq -r '.thresholds.hour_cost_usd_max // 20'  "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo 20)

mkdir -p "$ATOM_DIR"
touch "$ATOM_LEDGER" "$HOUR_LEDGER"

NOW_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_HOUR="$(date -u +%Y%m%d%H)"

sum_atom() { awk -F'"usd":' 'NF>1 {gsub(/[^0-9.]/,"",$2); s+=$2} END{printf "%.4f", s+0}' "$ATOM_LEDGER" 2>/dev/null || echo 0; }
sum_hour() { awk -v h="$NOW_HOUR" -F'"' '$0 ~ h {for(i=1;i<=NF;i++) if($i=="usd") {gsub(/[^0-9.]/,"",$(i+2)); s+=$(i+2)}} END{printf "%.4f", s+0}' "$HOUR_LEDGER" 2>/dev/null || echo 0; }

case "$ACTION" in
  record)
    echo "{\"ts\":\"$NOW_TS\",\"hour\":\"$NOW_HOUR\",\"usd\":$USD,\"atom\":\"$(basename "$ATOM_DIR")\"}" >> "$ATOM_LEDGER"
    echo "{\"ts\":\"$NOW_TS\",\"hour\":\"$NOW_HOUR\",\"usd\":$USD,\"atom\":\"$(basename "$ATOM_DIR")\"}" >> "$HOUR_LEDGER"
    ATOM_SUM=$(sum_atom)
    HOUR_SUM=$(sum_hour)
    echo "recorded usd=$USD  atom_total=$ATOM_SUM/$ATOM_CAP  hour_total=$HOUR_SUM/$HOUR_CAP"
    awk -v s="$ATOM_SUM" -v c="$ATOM_CAP" 'BEGIN{exit !(s>=c)}'  && { echo "AL-4 HALT: atom cap exceeded ($ATOM_SUM ≥ $ATOM_CAP)"  >&2; exit 4; }
    awk -v s="$HOUR_SUM" -v c="$HOUR_CAP" 'BEGIN{exit !(s>=c)}'  && { echo "AL-4 HALT: hour cap exceeded ($HOUR_SUM ≥ $HOUR_CAP)"  >&2; exit 4; }
    ;;
  check)
    ATOM_SUM=$(sum_atom)
    HOUR_SUM=$(sum_hour)
    awk -v s="$ATOM_SUM" -v c="$ATOM_CAP" 'BEGIN{exit !(s>=c)}'  && { echo "atom cap exceeded: $ATOM_SUM ≥ $ATOM_CAP" >&2; exit 4; }
    awk -v s="$HOUR_SUM" -v c="$HOUR_CAP" 'BEGIN{exit !(s>=c)}'  && { echo "hour cap exceeded: $HOUR_SUM ≥ $HOUR_CAP" >&2; exit 4; }
    echo "OK atom=$ATOM_SUM/$ATOM_CAP hour=$HOUR_SUM/$HOUR_CAP"
    ;;
  report)
    echo "{\"atom_spend_usd\":$(sum_atom),\"atom_cap_usd\":$ATOM_CAP,\"hour_spend_usd\":$(sum_hour),\"hour_cap_usd\":$HOUR_CAP,\"hour\":\"$NOW_HOUR\"}"
    ;;
esac
