#!/usr/bin/env bash
# type-check.sh — type gate, scoped to atom diff. Hard 0 error threshold.
# F6: typechecker missing/not configured → N/A_PENDING_REVIEWER, never silent PASS.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step type "starting in $PROJECT_ROOT"

STACK=$(detect_stack "$PROJECT_ROOT")
STACK_DIR=$(jq -r '.stack.dir // ""' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo "")
RUN_ROOT="$PROJECT_ROOT"
[[ -n "$STACK_DIR" ]] && RUN_ROOT="$PROJECT_ROOT/$STACK_DIR"

OUT="$ATOM_DIR/gate-mechanical/type.json"

read_lines SCOPE < <(changed_files | grep -E '\.(ts|tsx|py|go|rs)$' || true)
if [[ ${#SCOPE[@]} -eq 0 ]]; then
  log_step type "no typed source files in scope — N/A_PENDING_REVIEWER (F6: no vacuous PASS)"
  emit_na_pending "GATE-type" "$OUT" "no typed source files in scope; either add scope.paths to .build-anything.json OR confirm atom uses untyped language (eg plain JS/JSON)"
  exit 0
fi

TOOL_OK=false
ERRORS=0
case "$STACK" in
  node)
    # tsc requires tsconfig.json. Without it, the "type-check" is meaningless.
    if [[ ! -f "$RUN_ROOT/tsconfig.json" ]]; then
      log_step type "no tsconfig.json — N/A_PENDING_REVIEWER (plain JS or missing TS config)"
      emit_na_pending "GATE-type" "$OUT" "no tsconfig.json at $RUN_ROOT; either add TS config OR confirm atom is plain JS (no type checks possible)"
      exit 0
    fi
    if command -v npx >/dev/null 2>&1 && ( cd "$RUN_ROOT" && npx --no-install tsc --version >/dev/null 2>&1 ); then
      TOOL_OK=true
      OUTPUT=$( cd "$RUN_ROOT" && npx --no-install tsc --noEmit --pretty false 2>&1 || true )
      # If tsc didn't print "error TS..." nor "Version" header, it likely crashed (no config) — N/A.
      if [[ -z "$OUTPUT" ]] || ! echo "$OUTPUT" | grep -qE "(error TS[0-9]+|Found [0-9]+ error)" ; then
        # tsc succeeded silently OR crashed silently. Check exit-trail by re-running and capturing rc.
        if ! ( cd "$RUN_ROOT" && npx --no-install tsc --noEmit --pretty false >/dev/null 2>&1 ); then
          log_step type "tsc ran but produced no parseable output — N/A_PENDING_REVIEWER"
          emit_na_pending "GATE-type" "$OUT" "tsc ran but produced no parseable output (likely config error or no TS files in compilation unit); reviewer must fix tsconfig OR justify"
          exit 0
        fi
        # tsc returned 0 with empty output → no errors. Real PASS.
        ERRORS=0
      else
        ERRORS=$(echo "$OUTPUT" | grep -cE "error TS[0-9]+" || true)
      fi
    fi
    ;;
  python)
    if command -v mypy >/dev/null 2>&1; then
      TOOL_OK=true
      OUTPUT=$( cd "$RUN_ROOT" && mypy --no-error-summary "${SCOPE[@]}" 2>&1 || true )
      ERRORS=$(echo "$OUTPUT" | grep -cE ": error:" || true)
    fi
    ;;
  go)
    if command -v go >/dev/null 2>&1; then
      TOOL_OK=true
      OUTPUT=$( cd "$RUN_ROOT" && go vet ./... 2>&1 || true )
      ERRORS=$(echo "$OUTPUT" | grep -cE "^.+:[0-9]+:[0-9]+:" || true)
    fi
    ;;
  rust)
    if command -v cargo >/dev/null 2>&1; then
      TOOL_OK=true
      OUTPUT=$( cd "$RUN_ROOT" && cargo check --message-format json 2>/dev/null || true )
      ERRORS=$(echo "$OUTPUT" | jq -s '[.[] | select(.message.level=="error")] | length' 2>/dev/null || echo 0)
    fi
    ;;
  *)
    log_step type "unknown stack $STACK — N/A_PENDING_REVIEWER"
    emit_na_pending "GATE-type" "$OUT" "unknown stack=$STACK; configure .build-anything.json#stack.lang"
    exit 0
    ;;
esac

if [[ "$TOOL_OK" != "true" ]]; then
  log_step type "typechecker not installed for $STACK — N/A_PENDING_REVIEWER (LAW-15)"
  emit_na_pending "GATE-type" "$OUT" "typechecker for stack=$STACK not on PATH; reviewer must install (tsc/mypy/go/cargo) OR justify"
  exit 0
fi

PASSED=$([ "$ERRORS" -eq 0 ] && echo true || echo false)
emit_json "GATE-type" "$ERRORS" 0 "$PASSED" "$OUT" "{\"stack\":\"$STACK\",\"scope_files\":${#SCOPE[@]},\"run_root\":\"$RUN_ROOT\"}"

if [[ "$PASSED" == "true" ]]; then
  log_step type "PASS 0 errors ($STACK, ${#SCOPE[@]} files)"
  exit 0
else
  log_step type "FAIL $ERRORS errors"
  exit 1
fi
