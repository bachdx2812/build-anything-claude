#!/usr/bin/env bash
# run-all-meta-gates.sh — single regression spine for the skill itself.
# Runs every meta-gate in scripts/meta/*.sh (except this file) and aggregates
# verdicts. Any failure = skill regression; bootstrap error = harness rot.
#
# Why this exists: meta-gates are the only mechanical defence against the skill
# silently regressing on its own LAW-F6 / LAW-CL-95 invariants. They are useless
# if no one runs them. This script makes "run all meta-gates" one command so
# CI / pre-commit / pre-ship can wire it in without knowing the inventory.
#
# Usage:   bash scripts/meta/run-all-meta-gates.sh [--verbose]
# Exit:    0 = all meta-gates PASS
#          1 = one or more meta-gates FAIL (skill regression)
#          2 = bootstrap error in a meta-gate (harness broken)

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SELF="$(basename "$0")"

VERBOSE=0
[[ "${1:-}" == "--verbose" ]] && VERBOSE=1

# Discover sibling *.sh meta-gates, excluding self. Sort for deterministic order.
# Bash 3.2-compatible (macOS default) — no mapfile / readarray.
META_GATES=()
while IFS= read -r f; do
  META_GATES+=("$f")
done < <(find "$SCRIPT_DIR" -maxdepth 1 -type f -name '*.sh' ! -name "$SELF" | sort)

if [[ ${#META_GATES[@]} -eq 0 ]]; then
  echo "FATAL: no meta-gate scripts found in $SCRIPT_DIR" >&2
  exit 2
fi

PASS_COUNT=0
FAIL_COUNT=0
ERROR_COUNT=0
FAILED_GATES=()
ERRORED_GATES=()

echo "[meta-runner] discovered ${#META_GATES[@]} meta-gate(s):"
for g in "${META_GATES[@]}"; do echo "  - $(basename "$g")"; done
echo ""

for gate in "${META_GATES[@]}"; do
  name=$(basename "$gate" .sh)
  echo "[meta-runner] running: $name"
  if [[ "$VERBOSE" -eq 1 ]]; then
    bash "$gate"
    rc=$?
  else
    OUT=$(bash "$gate" 2>&1)
    rc=$?
  fi
  case "$rc" in
    0)
      PASS_COUNT=$((PASS_COUNT + 1))
      echo "  -> PASS"
      ;;
    1)
      FAIL_COUNT=$((FAIL_COUNT + 1))
      FAILED_GATES+=("$name")
      echo "  -> FAIL"
      [[ "$VERBOSE" -eq 0 ]] && echo "$OUT" | sed 's/^/      /'
      ;;
    *)
      ERROR_COUNT=$((ERROR_COUNT + 1))
      ERRORED_GATES+=("$name(rc=$rc)")
      echo "  -> ERROR (rc=$rc)"
      [[ "$VERBOSE" -eq 0 ]] && echo "$OUT" | sed 's/^/      /'
      ;;
  esac
  echo ""
done

echo "================================================================"
echo "meta-runner summary: pass=$PASS_COUNT fail=$FAIL_COUNT error=$ERROR_COUNT total=${#META_GATES[@]}"

if [[ "$ERROR_COUNT" -gt 0 ]]; then
  echo "ERRORED gates (harness rot — fix the meta-gate itself):"
  for g in "${ERRORED_GATES[@]}"; do echo "  - $g"; done
fi
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  echo "FAILED gates (skill regression — fix the skill):"
  for g in "${FAILED_GATES[@]}"; do echo "  - $g"; done
fi

if [[ "$ERROR_COUNT" -gt 0 ]]; then
  echo "meta-runner verdict=ERROR"
  exit 2
fi
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  echo "meta-runner verdict=FAIL"
  exit 1
fi
echo "meta-runner verdict=PASS"
exit 0
