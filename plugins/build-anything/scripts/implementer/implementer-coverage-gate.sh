#!/usr/bin/env bash
# implementer-coverage-gate.sh — Stage 4 GATE-IMPL post-dispatch verifier.
#
# Verifies that the BMAD-method multi-persona implementer dispatch (or the
# single-persona fallback) actually produced the expected artefacts:
#
#   multi-persona mode:
#     - {atom_dir}/implementer/concern-split.json exists with mode "multi-persona"
#     - For every concern with dispatch:true → {atom_dir}/implementer/<concern>-status.json
#       MUST exist with verdict ∈ {PASS, PENDING}
#     - files_changed[] of each persona ⊆ that persona's allowlist_subset[]
#     - tests-status.json.core_flows_covered[] ⊇ intent/verdict.json.core_flows[]
#
#   single-persona mode:
#     - {atom_dir}/implementer/single-status.json exists
#     - files_changed[] ⊆ atom allowlist
#
#   Either mode:
#     - No overlap between persona allowlist_subsets
#     - Union of files_changed[] ⊆ original atom allowlist
#
# Exit: 0 PASS, 1 FAIL, 2 preflight.

set -uo pipefail

ATOM_DIR=""
PROJECT_ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --atom-dir)     ATOM_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done
: "${ATOM_DIR:?--atom-dir required}"
: "${PROJECT_ROOT:?--project-root required}"

OUT="$ATOM_DIR/gate-impl/coverage.json"
mkdir -p "$(dirname "$OUT")"

log() { echo "[$(date -u +%H:%M:%S)] [gate-impl] $*" >&2; }

emit() {
  local verdict="$1" passed="$2" confidence="$3" reason="$4" details="$5"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-IMPL",
  "verdict": "$verdict",
  "passed": $passed,
  "confidence": $confidence,
  "reason": $(printf '%s' "$reason" | jq -Rs .),
  "ambiguities": [],
  "details": $details,
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
}

SPLIT="$ATOM_DIR/implementer/concern-split.json"
if [[ ! -f "$SPLIT" ]]; then
  # Pre-Stage-4 state: this atom never ran the BMAD-method dispatcher. NOT a
  # silent-drop ERROR — reviewer must decide whether Stage 4 was expected.
  # LAW-F6: never vacuous PASS; surface as N/A_PENDING_REVIEWER, rc=0.
  log "N/A: concern-split.json missing — Stage 4 dispatcher not yet run for this atom"
  emit "N/A_PENDING_REVIEWER" "null" "0" \
    "implementer/concern-split.json absent — atom has not reached Stage 4 BMAD-method dispatch; reviewer must confirm whether dispatch was expected" \
    '{"reason":"pre-stage4"}'
  exit 0
fi

MODE=$(jq -r '.mode' "$SPLIT")
log "mode=$MODE"

VIOLATIONS='[]'
add_violation() {
  VIOLATIONS=$(jq --arg v "$1" '. + [$v]' <<< "$VIOLATIONS")
}

# Pull intent core_flows for tests-coverage check.
INTENT="$ATOM_DIR/intent/verdict.json"
CORE_FLOWS='[]'
if [[ -f "$INTENT" ]]; then
  CORE_FLOWS=$(jq -c '.declared.core_flows // []' "$INTENT" 2>/dev/null || echo '[]')
fi

# Helper: assert array subset (parent ⊇ child). Returns 0 if subset.
is_subset() {
  local parent="$1" child="$2"
  # child - parent should be empty
  local diff
  diff=$(jq -n --argjson p "$parent" --argjson c "$child" '$c - $p')
  [[ "$diff" == "[]" ]]
}

if [[ "$MODE" == "multi-persona" ]]; then
  # Iterate dispatched concerns
  for concern in backend frontend tests; do
    DISPATCH=$(jq -r ".concerns.${concern}.dispatch" "$SPLIT")
    if [[ "$DISPATCH" != "true" ]]; then continue; fi

    STATUS="$ATOM_DIR/implementer/${concern}-status.json"
    if [[ ! -f "$STATUS" ]]; then
      add_violation "missing-status:${concern}"
      log "  ${concern}: status report missing"
      continue
    fi

    VERDICT=$(jq -r '.verdict' "$STATUS")
    if [[ "$VERDICT" != "PASS" && "$VERDICT" != "PENDING" ]]; then
      add_violation "bad-verdict:${concern}=${VERDICT}"
      log "  ${concern}: verdict=$VERDICT (expected PASS or PENDING)"
    fi

    # files_changed ⊆ allowlist_subset?
    ALLOWED=$(jq -c '.concerns.'"$concern"'.globs' "$SPLIT")
    CHANGED=$(jq -c '.files_changed // []' "$STATUS")
    # Glob-match check: for each changed file, at least one allowed glob must match.
    OUTSIDE=$(jq -n --argjson c "$CHANGED" --argjson a "$ALLOWED" '
      def globre($g): "^" + ($g
        | gsub("\\*\\*"; "DOUBLESTAR")
        | gsub("\\*"; "[^/]*")
        | gsub("DOUBLESTAR"; ".*")
      ) + "$";
      ($c | map(. as $f | if ($a | any(. as $g | $f | test(globre($g)))) then empty else $f end))
    ')
    if [[ "$OUTSIDE" != "[]" ]]; then
      add_violation "files-outside-allowlist:${concern}=$(echo "$OUTSIDE" | jq -c .)"
      log "  ${concern}: files outside allowlist: $OUTSIDE"
    fi
  done

  # Tests persona must cover core_flows (only if tests dispatched)
  TS_DISPATCH=$(jq -r '.concerns.tests.dispatch' "$SPLIT")
  if [[ "$TS_DISPATCH" == "true" && "$CORE_FLOWS" != "[]" ]]; then
    TS_STATUS="$ATOM_DIR/implementer/tests-status.json"
    if [[ -f "$TS_STATUS" ]]; then
      COVERED=$(jq -c '.core_flows_covered // []' "$TS_STATUS")
      MISSING=$(jq -n --argjson cf "$CORE_FLOWS" --argjson cov "$COVERED" '$cf - $cov')
      if [[ "$MISSING" != "[]" ]]; then
        add_violation "core_flows-uncovered:$(echo "$MISSING" | jq -c .)"
        log "  core_flows uncovered: $MISSING"
      fi
    fi
  fi

  # Allowlist-subset disjointness (no file in two personas)
  BE_GLOBS=$(jq -c '.concerns.backend.globs' "$SPLIT")
  FE_GLOBS=$(jq -c '.concerns.frontend.globs' "$SPLIT")
  TS_GLOBS=$(jq -c '.concerns.tests.globs' "$SPLIT")
  OVERLAP=$(jq -n --argjson be "$BE_GLOBS" --argjson fe "$FE_GLOBS" --argjson ts "$TS_GLOBS" '
    [ ($be - ($be - $fe)), ($be - ($be - $ts)), ($fe - ($fe - $ts)) ] | flatten | unique
  ')
  if [[ "$OVERLAP" != "[]" ]]; then
    add_violation "allowlist-overlap:$(echo "$OVERLAP" | jq -c .)"
    log "  persona allowlists overlap: $OVERLAP"
  fi

else
  # single-persona mode
  SINGLE_STATUS="$ATOM_DIR/implementer/single-status.json"
  if [[ ! -f "$SINGLE_STATUS" ]]; then
    add_violation "missing-status:single"
    log "  single-status.json missing"
  else
    VERDICT=$(jq -r '.verdict' "$SINGLE_STATUS")
    if [[ "$VERDICT" != "PASS" && "$VERDICT" != "PENDING" ]]; then
      add_violation "bad-verdict:single=${VERDICT}"
    fi
  fi
fi

# ── Machine-coverage corroboration (v9.0 LAW-COV-EXEC) ────────────
# The persona status files above are AGENT SELF-REPORT — `core_flows_covered[]`
# and verdict:"PASS" are authored by the implementer persona itself. They prove
# INTENT, not EXECUTION. A backend that never boots can still ship a status file
# claiming PASS (the FB-clone "100% FE+BE on a dead backend" failure mode).
# So when tests were dispatched against declared core_flows, this gate's PASS MUST
# be corroborated by a machine-produced coverage artifact (GATE-10), which runs
# earlier in the orchestrator and writes gate-mechanical/coverage.json. Absent /
# N/A / 0-instrumented coverage ⇒ we cannot certify → N/A_PENDING_REVIEWER, never
# a silent PASS on self-report alone.
COV_PROBLEM=""
REQUIRE_COV=0
if [[ "$MODE" == "multi-persona" ]]; then
  TS_DISPATCH_COV=$(jq -r '.concerns.tests.dispatch' "$SPLIT")
  [[ "$TS_DISPATCH_COV" == "true" && "$CORE_FLOWS" != "[]" ]] && REQUIRE_COV=1
fi
if [[ "$REQUIRE_COV" -eq 1 ]]; then
  COV10="$ATOM_DIR/gate-mechanical/coverage.json"
  if [[ ! -f "$COV10" ]]; then
    COV_PROBLEM="machine-coverage-absent(GATE-10 not run for this atom)"
  else
    COV_PASSED=$(jq -r '.passed' "$COV10" 2>/dev/null || echo "null")
    COV_VERDICT=$(jq -r '.verdict // empty' "$COV10" 2>/dev/null || echo "")
    COV_INSTR=$(jq -r '.extra.total_lines_instrumented // empty' "$COV10" 2>/dev/null || echo "")
    if [[ "$COV_PASSED" != "true" ]]; then
      COV_PROBLEM="machine-coverage-not-pass(passed=$COV_PASSED verdict=${COV_VERDICT:-none})"
    elif [[ -n "$COV_INSTR" && "$COV_INSTR" != "null" && "$COV_INSTR" -eq 0 ]]; then
      COV_PROBLEM="machine-coverage-vacuous(0 instrumented lines)"
    fi
  fi
fi

# ── Final verdict ────────────────────────────────────────────────
VIOLATION_COUNT=$(jq 'length' <<< "$VIOLATIONS")
DETAILS=$(jq -n --arg mode "$MODE" --argjson violations "$VIOLATIONS" --argjson core_flows "$CORE_FLOWS" \
  --arg cov_problem "$COV_PROBLEM" --argjson require_cov "$REQUIRE_COV" \
  '{mode: $mode, violations: $violations, core_flows_declared: $core_flows, machine_coverage_required: ($require_cov==1), machine_coverage_problem: (if $cov_problem=="" then null else $cov_problem end)}')

# Hard structural violations FAIL regardless (as before).
if [[ "$VIOLATION_COUNT" -gt 0 ]]; then
  log "FAIL: $VIOLATION_COUNT violation(s)"
  emit "FAIL" "false" "100" "Stage 4 implementer coverage gate found $VIOLATION_COUNT violation(s)" "$DETAILS"
  exit 1
fi

# No structural violations, but self-report uncorroborated by machine coverage ⇒
# cannot certify. LAW-F6/LAW-COV-EXEC: N/A_PENDING_REVIEWER, never vacuous PASS.
if [[ -n "$COV_PROBLEM" ]]; then
  log "N/A: persona self-report clean but uncorroborated — $COV_PROBLEM"
  emit "N/A_PENDING_REVIEWER" "null" "0" \
    "Stage 4 persona status reports are clean but coverage is unproven by machine evidence ($COV_PROBLEM); self-report alone cannot certify coverage (LAW-COV-EXEC) — reviewer must confirm tests actually executed against a running backend" \
    "$DETAILS"
  exit 0
fi

log "PASS: personas reported, no allowlist violations, core_flows covered, machine coverage corroborated"
emit "PASS" "true" "100" "Stage 4 BMAD-method implementer coverage complete (machine-coverage corroborated)" "$DETAILS"
exit 0
