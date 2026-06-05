#!/usr/bin/env bash
# coverage-check.sh — GATE-10 mechanical coverage gate.
# Scope: atom diff + 1-hop dependents (per references/mechanical-gates.md).
# Single-number contract: line% (primary). Branch% as extra.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step coverage "starting in $PROJECT_ROOT"

STACK=$(detect_stack "$PROJECT_ROOT")
STACK_DIR=$(jq -r '.stack.dir // ""' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo "")
RUN_ROOT="$PROJECT_ROOT"
[[ -n "$STACK_DIR" ]] && RUN_ROOT="$PROJECT_ROOT/$STACK_DIR"

THRESH_LINE=$(threshold "gates.mechanical.coverage_line" 80)
THRESH_BRANCH=$(threshold "gates.mechanical.coverage_branch" 80)
OUT_LINE="$ATOM_DIR/gate-mechanical/coverage.json"

case "$STACK" in
  node)
    if ! [[ -f "$RUN_ROOT/package.json" ]]; then
      log_step coverage "no package.json at $RUN_ROOT — N/A_PENDING_REVIEWER (set stack.dir in config)"
      emit_na_pending "GATE-10" "$OUT_LINE" "no package.json at $RUN_ROOT; set stack.dir to the dir containing package.json OR confirm atom has no test runner"
      exit 0
    fi
    require_cmd npx "install: npm i -D c8"
    ( cd "$RUN_ROOT" && npx --yes c8 --reporter=json-summary --reports-dir=.coverage-tmp npm test ) >/dev/null || true
    if [[ ! -f "$RUN_ROOT/.coverage-tmp/coverage-summary.json" ]]; then
      log_step coverage "coverage summary not produced — N/A_PENDING_REVIEWER (tests likely failed before coverage emit)"
      emit_na_pending "GATE-10" "$OUT_LINE" "c8 did not produce coverage-summary.json; reviewer must investigate test failure OR install c8"
      exit 0
    fi
    LINE=$(jq -r '.total.lines.pct' "$RUN_ROOT/.coverage-tmp/coverage-summary.json")
    BRANCH=$(jq -r '.total.branches.pct' "$RUN_ROOT/.coverage-tmp/coverage-summary.json")
    TOTAL_LINES=$(jq -r '.total.lines.total' "$RUN_ROOT/.coverage-tmp/coverage-summary.json")
    if ! [[ "$LINE" =~ ^[0-9.]+$ ]] || [[ "$TOTAL_LINES" -eq 0 ]]; then
      log_step coverage "coverage summary not numeric or 0 lines instrumented — N/A_PENDING_REVIEWER (tests likely did not execute)"
      emit_na_pending "GATE-10" "$OUT_LINE" "coverage summary has Unknown/0 (tests did not execute or no source loaded); reviewer must fix test discovery OR justify"
      exit 0
    fi
    ;;
  python)
    require_cmd coverage "install: pip install coverage"
    # v9.0 LAW-COV-EXEC — capture failure instead of aborting; a non-produced
    # report or 0 instrumented statements means tests did not execute → N/A,
    # never the 100%-of-nothing vacuous PASS the node branch already guards against.
    ( cd "$RUN_ROOT" && coverage run -m pytest -q && coverage json -o .coverage-tmp.json ) >/dev/null 2>&1 || true
    if [[ ! -f "$RUN_ROOT/.coverage-tmp.json" ]]; then
      log_step coverage "python coverage json not produced — N/A_PENDING_REVIEWER (pytest collected 0 tests or errored)"
      emit_na_pending "GATE-10" "$OUT_LINE" "coverage json not produced; pytest likely collected 0 tests or errored before emit — reviewer must fix test discovery OR justify"
      exit 0
    fi
    LINE=$(jq -r '.totals.percent_covered' "$RUN_ROOT/.coverage-tmp.json")
    TOTAL_LINES=$(jq -r '.totals.num_statements // 0' "$RUN_ROOT/.coverage-tmp.json")
    if ! [[ "$LINE" =~ ^[0-9.]+$ ]] || [[ "${TOTAL_LINES:-0}" -eq 0 ]]; then
      log_step coverage "python coverage 0 statements instrumented — N/A_PENDING_REVIEWER (tests did not execute)"
      emit_na_pending "GATE-10" "$OUT_LINE" "python coverage has 0 instrumented statements (no tests executed); reviewer must fix test discovery OR justify"
      exit 0
    fi
    BRANCH="$LINE"
    ;;
  go)
    require_cmd go
    ( cd "$RUN_ROOT" && go test -coverprofile=.coverage-tmp.out ./... ) >/dev/null 2>&1 || true
    if [[ ! -s "$RUN_ROOT/.coverage-tmp.out" ]]; then
      log_step coverage "go produced no coverage profile — N/A_PENDING_REVIEWER (no tests or build failed)"
      emit_na_pending "GATE-10" "$OUT_LINE" "go produced no coverage profile (no tests ran or build failed); reviewer must fix OR justify"
      exit 0
    fi
    LINE=$(go tool cover -func="$RUN_ROOT/.coverage-tmp.out" 2>/dev/null | tail -1 | awk '{gsub("%","",$NF); print $NF}')
    if ! [[ "$LINE" =~ ^[0-9.]+$ ]]; then
      log_step coverage "go coverage not numeric (0 statements covered) — N/A_PENDING_REVIEWER"
      emit_na_pending "GATE-10" "$OUT_LINE" "go coverage non-numeric (no statements executed); reviewer must fix OR justify"
      exit 0
    fi
    BRANCH="$LINE"
    ;;
  rust)
    require_cmd cargo "install: cargo install cargo-tarpaulin"
    ( cd "$RUN_ROOT" && cargo tarpaulin --out Json --output-dir .coverage-tmp ) >/dev/null 2>&1 || true
    if [[ ! -f "$RUN_ROOT/.coverage-tmp/tarpaulin-report.json" ]]; then
      log_step coverage "tarpaulin produced no report — N/A_PENDING_REVIEWER (no tests or build failed)"
      emit_na_pending "GATE-10" "$OUT_LINE" "tarpaulin produced no report (no tests ran or build failed); reviewer must fix OR justify"
      exit 0
    fi
    RUST_FILES=$(jq -r '.files | length' "$RUN_ROOT/.coverage-tmp/tarpaulin-report.json" 2>/dev/null || echo 0)
    if [[ "${RUST_FILES:-0}" -eq 0 ]]; then
      log_step coverage "tarpaulin measured 0 files — N/A_PENDING_REVIEWER (no tests executed)"
      emit_na_pending "GATE-10" "$OUT_LINE" "tarpaulin measured 0 files (no tests executed); reviewer must fix OR justify"
      exit 0
    fi
    LINE=$(jq -r '.files | map(.coverage) | add / length' "$RUN_ROOT/.coverage-tmp/tarpaulin-report.json")
    BRANCH="$LINE"
    ;;
  *)
    log_step coverage "unknown stack $STACK — N/A_PENDING_REVIEWER"
    emit_na_pending "GATE-10" "$OUT_LINE" "unknown stack=$STACK; configure .build-anything.json#stack.lang"
    exit 0
    ;;
esac

PASSED_LINE=$(awk -v s="$LINE" -v t="$THRESH_LINE" 'BEGIN{print (s>=t)?"true":"false"}')
PASSED_BRANCH=$(awk -v s="$BRANCH" -v t="$THRESH_BRANCH" 'BEGIN{print (s>=t)?"true":"false"}')
PASSED="false"; [[ "$PASSED_LINE" == "true" && "$PASSED_BRANCH" == "true" ]] && PASSED="true"

# v8.3 — emit scope_files so headline is interpretable.
# "Coverage 81%" without scope context is misleading (could be 81% on 2 of 8 files).
read_lines SCOPE_LIST < <(changed_files | grep -E '\.(ts|tsx|js|jsx|py|go|rs)$' | grep -v -E '(test|spec)' || true)
SCOPE_FILES=${#SCOPE_LIST[@]}

emit_json "GATE-10-line" "$LINE" "$THRESH_LINE" "$PASSED" "$OUT_LINE" \
  "{\"branch_pct\": $BRANCH, \"branch_threshold\": $THRESH_BRANCH, \"branch_passed\": $PASSED_BRANCH, \"stack\": \"$STACK\", \"scope_files\": $SCOPE_FILES, \"total_lines_instrumented\": ${TOTAL_LINES:-null}}"

if [[ "$PASSED" == "true" ]]; then
  log_step coverage "PASS line=${LINE}% branch=${BRANCH}% scope_files=$SCOPE_FILES"
  exit 0
else
  log_step coverage "FAIL line=${LINE}% (≥${THRESH_LINE}) branch=${BRANCH}% (≥${THRESH_BRANCH}) scope_files=$SCOPE_FILES"
  exit 1
fi
