#!/usr/bin/env bash
# mutation-test.sh — GATE-11 mutation testing.
# Scope: atom diff only + 1-hop deps (full-repo is unaffordable; per mechanical-gates.md).
# Single-number contract: mutation kill ratio % (0..100).

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step mutation "starting in $PROJECT_ROOT"

STACK=$(detect_stack "$PROJECT_ROOT")
STACK_DIR=$(jq -r '.stack.dir // ""' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo "")
RUN_ROOT="$PROJECT_ROOT"
[[ -n "$STACK_DIR" ]] && RUN_ROOT="$PROJECT_ROOT/$STACK_DIR"

THRESH=$(threshold "gates.mechanical.mutation_score" 60)
OUT="$ATOM_DIR/gate-mechanical/mutation.json"

# scope to changed source files only — reads `git diff` via _common
read_lines SCOPE < <(changed_files | grep -E '\.(ts|tsx|js|jsx|py|go|rs)$' | grep -v -E '(test|spec)' || true)
if [[ ${#SCOPE[@]} -eq 0 ]]; then
  log_step mutation "no scoped source files in atom diff — N/A_PENDING_REVIEWER (F6 fix)"
  emit_na_pending "GATE-11" "$OUT" "atom diff contained no source files; reviewer must verify atom is doc/config-only"
  exit 0
fi

# F1 fix — expand scope to include 1-hop dependents of changed files.
# Node: madge --depends; Python: importlab; Go: go list -deps; Rust: cargo tree --invert.
# Missing tool = log warning + keep diff-only scope (don't silently pass).
expand_deps_node() {
  command -v madge >/dev/null 2>&1 || return 0
  local f rel
  for f in "${SCOPE[@]}"; do
    rel="${f#$STACK_DIR/}"
    ( cd "$PROJECT_ROOT" && madge --depends "$rel" "$STACK_DIR" --json 2>/dev/null \
      | jq -r --arg dir "$STACK_DIR" '.[] | "\($dir)/\(.)"' 2>/dev/null ) || true
  done | sort -u
}
case "$STACK" in
  node)
    read_lines DEPS < <(expand_deps_node)
    if [[ ${#DEPS[@]} -gt 0 ]]; then
      SCOPE+=("${DEPS[@]}"); SCOPE=($(printf '%s\n' "${SCOPE[@]}" | sort -u))
      log_step mutation "F1: expanded with ${#DEPS[@]} 1-hop dep(s)"
    else
      log_step mutation "WARNING: F1 dep expansion unavailable (madge not found) — scope is diff-only"
    fi
    ;;
  *) log_step mutation "F1 dep expansion not yet wired for $STACK — see references/mechanical-gates.md" ;;
esac
log_step mutation "scope: ${#SCOPE[@]} file(s)"

case "$STACK" in
  node)
    STRYKER_BIN=""
    if command -v stryker >/dev/null 2>&1; then
      STRYKER_BIN="stryker"
    elif command -v npx >/dev/null 2>&1 && ( cd "$RUN_ROOT" && npx --no-install stryker --version >/dev/null 2>&1 ); then
      STRYKER_BIN="npx --no-install stryker"
    else
      log_step mutation "stryker not installed — N/A_PENDING_REVIEWER (LAW-15)"
      emit_na_pending "GATE-11" "$OUT" "stryker not installed; reviewer must install (npm i -g stryker-cli @stryker-mutator/core) OR justify"
      exit 0
    fi
    # Strip RUN_ROOT prefix from scope paths so they resolve relative to stryker cwd.
    REL_SCOPE=()
    for p in "${SCOPE[@]}"; do
      REL_SCOPE+=("${p#$STACK_DIR/}")
    done
    STRYKER_OUT_JSON="$RUN_ROOT/reports/mutation/.stryker-tmp.json"
    ( cd "$RUN_ROOT" && $STRYKER_BIN run --mutate "${REL_SCOPE[@]}" ) >/dev/null 2>&1 || true
    if [[ ! -f "$STRYKER_OUT_JSON" ]]; then
      log_step mutation "stryker output missing — N/A_PENDING_REVIEWER"
      emit_na_pending "GATE-11" "$OUT" "stryker did not produce JSON output at $STRYKER_OUT_JSON; reviewer must investigate (check stryker.conf.json#jsonReporter.fileName)"
      exit 0
    fi
    KILLED=$(jq -r '[.files[].mutants[] | select(.status=="Killed")] | length' "$STRYKER_OUT_JSON" 2>/dev/null || echo 0)
    SURVIVED=$(jq -r '[.files[].mutants[] | select(.status=="Survived")] | length' "$STRYKER_OUT_JSON" 2>/dev/null || echo 0)
    TIMEOUT_=$(jq -r '[.files[].mutants[] | select(.status=="Timeout")] | length' "$STRYKER_OUT_JSON" 2>/dev/null || echo 0)
    TOTAL=$(( KILLED + SURVIVED + TIMEOUT_ ))
    [[ "$TOTAL" -eq 0 ]] && TOTAL=1
    MUTATED_FILES=$(jq -r '.files | length' "$STRYKER_OUT_JSON" 2>/dev/null || echo 0)
    if [[ "$MUTATED_FILES" -lt "${#SCOPE[@]}" ]]; then
      log_step mutation "WARN: stryker mutated $MUTATED_FILES of ${#SCOPE[@]} scope files — check for unparseable paths"
    fi
    ;;
  python)
    if ! command -v mutmut >/dev/null 2>&1; then
      emit_na_pending "GATE-11" "$OUT" "mutmut not installed; reviewer must install (pip install mutmut) OR justify"
      exit 0
    fi
    ( cd "$RUN_ROOT" && mutmut run --paths-to-mutate "$(IFS=,; echo "${SCOPE[*]}")" ) || true
    KILLED=$(mutmut results 2>/dev/null | awk '/killed/ {print $2}' || echo 0)
    TOTAL=$(mutmut results 2>/dev/null | awk '/Total/ {print $2}' || echo 1)
    ;;
  go)
    if ! command -v gremlins >/dev/null 2>&1; then
      emit_na_pending "GATE-11" "$OUT" "gremlins not installed; reviewer must install (go install github.com/go-gremlins/gremlins/cmd/gremlins@latest) OR justify"
      exit 0
    fi
    ( cd "$RUN_ROOT" && gremlins unleash -o json "${SCOPE[@]}" > .gremlins-tmp.json ) || true
    KILLED=$(jq -r '[.mutants[] | select(.status=="KILLED")] | length' "$RUN_ROOT/.gremlins-tmp.json" 2>/dev/null || echo 0)
    TOTAL=$(jq -r '.mutants | length' "$RUN_ROOT/.gremlins-tmp.json" 2>/dev/null || echo 1)
    ;;
  rust)
    if ! command -v cargo >/dev/null 2>&1; then
      emit_na_pending "GATE-11" "$OUT" "cargo not installed; reviewer must install rust toolchain OR justify"
      exit 0
    fi
    ( cd "$RUN_ROOT" && timeout 600 cargo mutants --no-shuffle --json > .mutants-tmp.json ) || true
    KILLED=$(jq -r '[.outcomes[] | select(.outcome=="CaughtMutant")] | length' "$RUN_ROOT/.mutants-tmp.json" 2>/dev/null || echo 0)
    TOTAL=$(jq -r '.outcomes | length' "$RUN_ROOT/.mutants-tmp.json" 2>/dev/null || echo 1)
    ;;
  *)
    log_step mutation "unknown stack $STACK — N/A_PENDING_REVIEWER"
    emit_na_pending "GATE-11" "$OUT" "unknown stack=$STACK; configure .build-anything.json#stack.lang"
    exit 0
    ;;
esac

SCORE=$(awk -v k="$KILLED" -v t="$TOTAL" 'BEGIN{ if (t==0) print 0; else printf "%.2f", (k/t)*100 }')
PASSED=$(awk -v s="$SCORE" -v t="$THRESH" 'BEGIN{print (s>=t)?"true":"false"}')

emit_json "GATE-11" "$SCORE" "$THRESH" "$PASSED" "$OUT" \
  "{\"killed\": $KILLED, \"total\": $TOTAL, \"stack\": \"$STACK\", \"scope_files\": ${#SCOPE[@]}}"

if [[ "$PASSED" == "true" ]]; then
  log_step mutation "PASS ${SCORE}% (killed $KILLED / $TOTAL)"
  exit 0
else
  log_step mutation "FAIL ${SCORE}% (≥${THRESH}) — killed $KILLED / $TOTAL"
  exit 1
fi
