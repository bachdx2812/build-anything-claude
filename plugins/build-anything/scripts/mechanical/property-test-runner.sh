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

# LAW-F6 — empty scope is NEVER PASS. Emit N/A_PENDING_REVIEWER BEFORE running
# any stack-specific test runner (which would crash on missing package.json etc).
read_lines SCOPE < <(changed_files | grep -E '\.(ts|tsx|js|jsx|py|go|rs)$' | grep -v -E '(test|spec)' || true)
if [[ ${#SCOPE[@]} -eq 0 ]]; then
  emit_na_pending "GATE-16" "$OUT" "no source files in scope — property gate cannot run; reviewer must populate scope.paths or scope.bootstrap_glob"
  log_step property "N/A no source files in scope (LAW-F6 — no vacuous PASS)"
  exit 0
fi

case "$STACK" in
  node)
    require_cmd npx "install: npm i -D fast-check vitest"
    # `|| true` keeps pipefail from killing the script when grep finds zero matches.
    COUNT=$( { grep -rE "fc\.(assert|property)" "$PROJECT_ROOT" --include="*.ts" --include="*.js" 2>/dev/null || true; } | wc -l | tr -d ' ')
    # Prefer the project's own `npm test` (covers node:test, jest, vitest, mocha…). Fall back to vitest if absent.
    if [[ -f "$PROJECT_ROOT/package.json" ]] && jq -e '.scripts.test' "$PROJECT_ROOT/package.json" >/dev/null 2>&1; then
      ( cd "$PROJECT_ROOT" && FAST_CHECK_NUM_RUNS=100 FAST_CHECK_SEED=$SEED npm test --silent ) >/dev/null
    else
      ( cd "$PROJECT_ROOT" && FAST_CHECK_NUM_RUNS=100 FAST_CHECK_SEED=$SEED npx --yes vitest run --reporter=basic ) >/dev/null
    fi
    ;;
  python)
    require_cmd pytest "install: pip install pytest hypothesis"
    COUNT=$( { grep -rE "@given\(" "$PROJECT_ROOT" --include="*.py" 2>/dev/null || true; } | wc -l | tr -d ' ')
    ( cd "$PROJECT_ROOT" && pytest -q --hypothesis-seed=$SEED ) >/dev/null
    ;;
  go)
    require_cmd go
    COUNT=$( { grep -rE "gopter\." "$PROJECT_ROOT" --include="*.go" 2>/dev/null || true; } | wc -l | tr -d ' ')
    ( cd "$PROJECT_ROOT" && go test -run "Prop|Property" ./... -v ) >/dev/null
    ;;
  rust)
    require_cmd cargo
    COUNT=$( { grep -rE "proptest!" "$PROJECT_ROOT" --include="*.rs" 2>/dev/null || true; } | wc -l | tr -d ' ')
    ( cd "$PROJECT_ROOT" && PROPTEST_CASES=100 cargo test --quiet ) >/dev/null
    ;;
  *)
    log_fatal "unknown stack — no property adapter"
    ;;
esac

PASSED=$(awk -v s="$COUNT" -v t="$THRESH" 'BEGIN{print (s>=t)?"true":"false"}')

emit_json "GATE-16" "$COUNT" "$THRESH" "$PASSED" "$OUT" \
  "{\"seed\": \"$SEED\", \"stack\": \"$STACK\", \"scope_files\": ${#SCOPE[@]}}"

if [[ "$PASSED" == "true" ]]; then
  log_step property "PASS ${COUNT} property tests (≥${THRESH}) seed=$SEED scope_files=${#SCOPE[@]}"
  exit 0
else
  log_step property "FAIL ${COUNT} property tests (≥${THRESH}) — add property tests for pure functions in atom"
  exit 1
fi
