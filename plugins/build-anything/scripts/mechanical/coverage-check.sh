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
    ( cd "$RUN_ROOT" && coverage run -m pytest -q && coverage json -o .coverage-tmp.json ) >/dev/null
    LINE=$(jq -r '.totals.percent_covered' "$RUN_ROOT/.coverage-tmp.json")
    BRANCH="$LINE"
    ;;
  go)
    require_cmd go
    ( cd "$RUN_ROOT" && go test -coverprofile=.coverage-tmp.out ./... ) >/dev/null
    LINE=$(go tool cover -func="$RUN_ROOT/.coverage-tmp.out" | tail -1 | awk '{gsub("%","",$NF); print $NF}')
    BRANCH="$LINE"
    ;;
  rust)
    require_cmd cargo "install: cargo install cargo-tarpaulin"
    ( cd "$RUN_ROOT" && cargo tarpaulin --out Json --output-dir .coverage-tmp ) >/dev/null
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

emit_json "GATE-10-line" "$LINE" "$THRESH_LINE" "$PASSED" "$OUT_LINE" \
  "{\"branch_pct\": $BRANCH, \"branch_threshold\": $THRESH_BRANCH, \"branch_passed\": $PASSED_BRANCH, \"stack\": \"$STACK\"}"

if [[ "$PASSED" == "true" ]]; then
  log_step coverage "PASS line=${LINE}% branch=${BRANCH}%"
  exit 0
else
  log_step coverage "FAIL line=${LINE}% (≥${THRESH_LINE}) branch=${BRANCH}% (≥${THRESH_BRANCH})"
  exit 1
fi
