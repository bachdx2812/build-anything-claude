#!/usr/bin/env bash
# lint-check.sh — lint gate, scoped to atom diff. Hard 0 error threshold.
# F6: if linter not installed/configured → N/A_PENDING_REVIEWER, never silent PASS.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step lint "starting in $PROJECT_ROOT"

STACK=$(detect_stack "$PROJECT_ROOT")
STACK_DIR=$(jq -r '.stack.dir // ""' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo "")
RUN_ROOT="$PROJECT_ROOT"
[[ -n "$STACK_DIR" ]] && RUN_ROOT="$PROJECT_ROOT/$STACK_DIR"

OUT="$ATOM_DIR/gate-mechanical/lint.json"

read_lines SCOPE < <(changed_files | grep -E '\.(ts|tsx|js|jsx|py|go|rs)$' || true)
if [[ ${#SCOPE[@]} -eq 0 ]]; then
  log_step lint "no source files in scope — N/A_PENDING_REVIEWER (F6: no vacuous PASS)"
  emit_na_pending "GATE-lint" "$OUT" "no source files in scope; either add scope.paths/bootstrap_glob to .build-anything.json OR confirm atom is doc/config-only"
  exit 0
fi

RAW=""
TOOL_OK=false
case "$STACK" in
  node)
    if command -v npx >/dev/null 2>&1 && ( cd "$RUN_ROOT" && npx --no-install eslint --version >/dev/null 2>&1 ); then
      TOOL_OK=true
      RAW=$( cd "$RUN_ROOT" && npx --no-install eslint --format json "${SCOPE[@]}" 2>/dev/null || true )
    fi
    ;;
  python)
    if command -v ruff >/dev/null 2>&1; then
      TOOL_OK=true
      RAW=$( cd "$RUN_ROOT" && ruff check --output-format json "${SCOPE[@]}" 2>/dev/null || true )
    fi
    ;;
  go)
    if command -v golangci-lint >/dev/null 2>&1; then
      TOOL_OK=true
      RAW=$( cd "$RUN_ROOT" && golangci-lint run --out-format json "${SCOPE[@]}" 2>/dev/null || true )
    fi
    ;;
  rust)
    if command -v cargo >/dev/null 2>&1; then
      TOOL_OK=true
      RAW=$( cd "$RUN_ROOT" && cargo clippy --message-format json -- -D warnings 2>/dev/null || true )
    fi
    ;;
  *)
    log_step lint "unknown stack $STACK — N/A_PENDING_REVIEWER"
    emit_na_pending "GATE-lint" "$OUT" "unknown stack=$STACK; configure .build-anything.json#stack.lang"
    exit 0
    ;;
esac

if [[ "$TOOL_OK" != "true" ]]; then
  log_step lint "linter not installed for $STACK — N/A_PENDING_REVIEWER (LAW-15)"
  emit_na_pending "GATE-lint" "$OUT" "linter for stack=$STACK not on PATH; reviewer must install (eslint/ruff/golangci-lint/clippy) OR justify"
  exit 0
fi

# Validate output is well-formed JSON; otherwise linter likely missing config / crashed.
if [[ -z "$RAW" ]] || ! echo "$RAW" | jq empty >/dev/null 2>&1; then
  log_step lint "linter ran but output not valid JSON (missing config? crashed?) — N/A_PENDING_REVIEWER"
  emit_na_pending "GATE-lint" "$OUT" "linter for $STACK produced no valid JSON output (config missing or runtime error); reviewer must add lint config OR justify"
  exit 0
fi

case "$STACK" in
  node)   ERRORS=$(echo "$RAW" | jq -r '[.[].errorCount] | add // 0' 2>/dev/null || echo 0) ;;
  python) ERRORS=$(echo "$RAW" | jq -r 'length' 2>/dev/null || echo 0) ;;
  go)     ERRORS=$(echo "$RAW" | jq -r '.Issues | length // 0' 2>/dev/null || echo 0) ;;
  rust)   ERRORS=$(echo "$RAW" | jq -s '[.[] | select(.message.level=="error")] | length' 2>/dev/null || echo 0) ;;
esac

PASSED=$([ "$ERRORS" -eq 0 ] && echo true || echo false)
emit_json "GATE-lint" "$ERRORS" 0 "$PASSED" "$OUT" "{\"stack\":\"$STACK\",\"scope_files\":${#SCOPE[@]},\"run_root\":\"$RUN_ROOT\"}"

if [[ "$PASSED" == "true" ]]; then
  log_step lint "PASS 0 errors ($STACK, ${#SCOPE[@]} files)"
  exit 0
else
  log_step lint "FAIL $ERRORS errors"
  exit 1
fi
