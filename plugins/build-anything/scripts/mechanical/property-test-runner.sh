#!/usr/bin/env bash
# property-test-runner.sh — GATE-16 property-based testing.
# Single-number contract: # pure functions covered by ≥1 property test.
# Seed captured per risk 13.4 (reproducibility).

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step property "starting in $PROJECT_ROOT"

STACK=$(detect_stack "$PROJECT_ROOT")
THRESH=$(threshold "gates.mechanical.property_min" 1)
OUT="$ATOM_DIR/gate-mechanical/property.json"
SEED="${BUILD_ANYTHING_PROPERTY_SEED:-$(date +%s)}"

case "$STACK" in
  node)
    require_cmd npx "install: npm i -D fast-check vitest"
    COUNT=$(grep -rE "fc\.(assert|property)" "$PROJECT_ROOT" --include="*.ts" --include="*.js" 2>/dev/null | wc -l | tr -d ' ')
    ( cd "$PROJECT_ROOT" && FAST_CHECK_NUM_RUNS=100 FAST_CHECK_SEED=$SEED npx --yes vitest run --reporter=basic ) >/dev/null
    ;;
  python)
    require_cmd pytest "install: pip install pytest hypothesis"
    COUNT=$(grep -rE "@given\(" "$PROJECT_ROOT" --include="*.py" 2>/dev/null | wc -l | tr -d ' ')
    ( cd "$PROJECT_ROOT" && pytest -q --hypothesis-seed=$SEED ) >/dev/null
    ;;
  go)
    require_cmd go
    COUNT=$(grep -rE "gopter\." "$PROJECT_ROOT" --include="*.go" 2>/dev/null | wc -l | tr -d ' ')
    ( cd "$PROJECT_ROOT" && go test -run "Prop|Property" ./... -v ) >/dev/null
    ;;
  rust)
    require_cmd cargo
    COUNT=$(grep -rE "proptest!" "$PROJECT_ROOT" --include="*.rs" 2>/dev/null | wc -l | tr -d ' ')
    ( cd "$PROJECT_ROOT" && PROPTEST_CASES=100 cargo test --quiet ) >/dev/null
    ;;
  *)
    log_fatal "unknown stack — no property adapter"
    ;;
esac

# If atom touches no pure functions, score 0 + threshold 0 is vacuously PASS.
# Detect "no pure fn" heuristically: changed_files filtered for source files.
read_lines SCOPE < <(changed_files | grep -E '\.(ts|tsx|js|jsx|py|go|rs)$' | grep -v -E '(test|spec)' || true)
EFFECTIVE_THRESH="$THRESH"
if [[ ${#SCOPE[@]} -eq 0 ]]; then EFFECTIVE_THRESH=0; fi

PASSED=$(awk -v s="$COUNT" -v t="$EFFECTIVE_THRESH" 'BEGIN{print (s>=t)?"true":"false"}')

emit_json "GATE-16" "$COUNT" "$EFFECTIVE_THRESH" "$PASSED" "$OUT" \
  "{\"seed\": \"$SEED\", \"stack\": \"$STACK\", \"scope_files\": ${#SCOPE[@]}}"

if [[ "$PASSED" == "true" ]]; then
  log_step property "PASS ${COUNT} property tests (≥${EFFECTIVE_THRESH}) seed=$SEED"
  exit 0
else
  log_step property "FAIL ${COUNT} property tests (≥${EFFECTIVE_THRESH}) — add property tests for pure functions in atom"
  exit 1
fi
