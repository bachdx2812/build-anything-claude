#!/usr/bin/env bash
# observability-check.sh — GATE-15 observability gate.
# Single-number contract: count of changed source files MISSING required instrumentation.
# Threshold: hard 0 — every code path needs structured log + metric + (if request-bound) trace.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step observability "starting"

OUT="$ATOM_DIR/gate-mechanical/observability.json"

read_lines SCOPE < <(changed_files | grep -E '\.(ts|tsx|js|jsx|py|go|rs)$' | grep -v -E '(test|spec)' || true)
if [[ ${#SCOPE[@]} -eq 0 ]]; then
  log_step observability "no source files in scope — N/A_PENDING_REVIEWER (F6: no vacuous PASS)"
  emit_na_pending "GATE-15" "$OUT" "no source files in scope; either add scope.paths/bootstrap_glob to .build-anything.json OR confirm atom has no source files"
  exit 0
fi

# regex patterns per stack (heuristic but consistent)
LOG_PAT='(logger\.|log\.(info|warn|error|debug)|console\.error|structlog|slog\.|tracing::)'
METRIC_PAT='(metrics\.|counter|histogram|prometheus|otel|gauge|recordValue)'
TRACE_PAT='(span|trace|tracer\.|getTracer|otel\.trace)'

MISSING=0
DETAILS="[]"
for f in "${SCOPE[@]}"; do
  FULL="$PROJECT_ROOT/$f"
  [[ ! -f "$FULL" ]] && continue
  HAS_LOG=$( { grep -E "$LOG_PAT"    "$FULL" 2>/dev/null || true; } | wc -l | tr -d ' ')
  HAS_METRIC=$( { grep -E "$METRIC_PAT" "$FULL" 2>/dev/null || true; } | wc -l | tr -d ' ')
  REQ_BOUND=$( { grep -E "(route|router|handler|controller|endpoint|@app\.(get|post|put|delete)|fastapi|express)" "$FULL" 2>/dev/null || true; } | wc -l | tr -d ' ')
  HAS_TRACE=$( { grep -E "$TRACE_PAT"   "$FULL" 2>/dev/null || true; } | wc -l | tr -d ' ')

  FAIL=0; REASONS=""
  [[ "$HAS_LOG" -eq 0 ]]    && { FAIL=1; REASONS="${REASONS}no-log; "; }
  [[ "$HAS_METRIC" -eq 0 ]] && { FAIL=1; REASONS="${REASONS}no-metric; "; }
  [[ "$REQ_BOUND" -gt 0 && "$HAS_TRACE" -eq 0 ]] && { FAIL=1; REASONS="${REASONS}req-bound-no-trace; "; }

  if [[ $FAIL -eq 1 ]]; then
    MISSING=$((MISSING+1))
    DETAILS=$(jq -c --arg p "$f" --arg r "$REASONS" '. + [{"path":$p,"reasons":$r}]' <<< "$DETAILS")
  fi
done

PASSED=$([ "$MISSING" -eq 0 ] && echo true || echo false)
emit_json "GATE-15" "$MISSING" 0 "$PASSED" "$OUT" "{\"missing_files\":$DETAILS,\"scope\":${#SCOPE[@]}}"

if [[ "$PASSED" == "true" ]]; then
  log_step observability "PASS all $((${#SCOPE[@]})) files instrumented"
  exit 0
else
  log_step observability "FAIL $MISSING file(s) missing instrumentation"
  exit 1
fi
