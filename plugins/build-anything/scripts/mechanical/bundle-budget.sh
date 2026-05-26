#!/usr/bin/env bash
# bundle-budget.sh — GATE-14 (FE) bundle delta gate.
# Single-number contract: gzipped KB delta vs prior build.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step bundle "starting in $PROJECT_ROOT"

STACK=$(detect_stack "$PROJECT_ROOT")
[[ "$STACK" != "node" ]] && {
  log_step bundle "non-FE stack — N/A_PENDING_REVIEWER (gate doesn't apply, not vacuous PASS)"
  emit_na_pending "GATE-14-bundle" "$ATOM_DIR/gate-mechanical/bundle.json" "stack=$STACK is not a frontend; reviewer must confirm atom has no FE bundle to budget"
  exit 0
}

STACK_DIR=$(jq -r '.stack.dir // ""' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo "")
FE_DIR=$(jq -r '.frontend.dir // ""' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo "")
RUN_ROOT="$PROJECT_ROOT"
[[ -n "$FE_DIR" ]] && RUN_ROOT="$PROJECT_ROOT/$FE_DIR"
[[ -z "$FE_DIR" && -n "$STACK_DIR" ]] && RUN_ROOT="$PROJECT_ROOT/$STACK_DIR"

THRESH_KB=$(threshold "gates.performance.bundle_delta_kb" 5)
OUT="$ATOM_DIR/gate-mechanical/bundle.json"
BASELINE_FILE="$PROJECT_ROOT/.build-anything/bundle-baseline.json"

if ! [[ -f "$RUN_ROOT/package.json" ]]; then
  log_step bundle "no package.json at $RUN_ROOT — N/A_PENDING_REVIEWER"
  emit_na_pending "GATE-14-bundle" "$OUT" "no package.json at $RUN_ROOT; set frontend.dir or stack.dir in config OR confirm atom has no FE bundle"
  exit 0
fi

# build current
( cd "$RUN_ROOT" && npm run build ) >/dev/null 2>&1 || true

# measure current bundle (gz)
DIST_DIR=$(threshold "frontend.dist_dir" "dist")
if [[ ! -d "$RUN_ROOT/$DIST_DIR" ]]; then
  log_step bundle "dist dir $RUN_ROOT/$DIST_DIR missing — N/A_PENDING_REVIEWER (build script may not exist)"
  emit_na_pending "GATE-14-bundle" "$OUT" "build dir $DIST_DIR not produced at $RUN_ROOT; configure frontend.dist_dir OR add a build script OR confirm no FE bundle"
  exit 0
fi
CURRENT_KB=$( find "$RUN_ROOT/$DIST_DIR" -type f \( -name "*.js" -o -name "*.css" \) -exec gzip -c {} \; 2>/dev/null \
  | wc -c | awk '{printf "%.2f", $1/1024}' )

# baseline
if [[ -f "$BASELINE_FILE" ]]; then
  BASELINE_KB=$(jq -r '.total_kb' "$BASELINE_FILE")
else
  BASELINE_KB="$CURRENT_KB"  # first run — initialise
  echo "{\"total_kb\":$CURRENT_KB,\"recorded_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$BASELINE_FILE"
fi

DELTA=$(awk -v c="$CURRENT_KB" -v b="$BASELINE_KB" 'BEGIN{printf "%.2f", c-b}')
PASSED=$(awk -v d="$DELTA" -v t="$THRESH_KB" 'BEGIN{print (d<=t)?"true":"false"}')

read_lines SCOPE_LIST < <(changed_files | grep -E '\.(ts|tsx|js|jsx|css|scss)$' | grep -v -E '(test|spec)' || true)
SCOPE_FILES=${#SCOPE_LIST[@]}

emit_json "GATE-14-bundle" "$DELTA" "$THRESH_KB" "$PASSED" "$OUT" \
  "{\"current_kb\":$CURRENT_KB,\"baseline_kb\":$BASELINE_KB,\"dist_dir\":\"$DIST_DIR\",\"scope_files\":$SCOPE_FILES}"

if [[ "$PASSED" == "true" ]]; then
  log_step bundle "PASS delta=${DELTA}KB (≤${THRESH_KB}KB) current=${CURRENT_KB}KB baseline=${BASELINE_KB}KB"
  exit 0
else
  log_step bundle "FAIL delta=${DELTA}KB exceeds ${THRESH_KB}KB"
  exit 1
fi
