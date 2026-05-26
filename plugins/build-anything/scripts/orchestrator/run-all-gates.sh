#!/usr/bin/env bash
# run-all-gates.sh — UBS v8.1 main orchestrator entry point.
# Dispatches every gate script (mechanical/security/backend/cloud), aggregates
# results into atom_dir/manifest.json, computes SHA-256, writes witness.json.
#
# Usage:
#   run-all-gates.sh --atom-dir <dir> --project-root <dir> [--skip <gate>] [--only <gate>] [--no-witness]
#
# Single-number contract per gate is preserved (each child still writes its own
# {gate, score, threshold, passed} JSON). This script ONLY composes.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MECH_DIR="$SCRIPT_DIR/../mechanical"
SEC_DIR="$SCRIPT_DIR/../security"
BACK_DIR="$SCRIPT_DIR/../backend"
CLOUD_DIR="$SCRIPT_DIR/../cloud"
SPEC_DIR="$SCRIPT_DIR/../spec"
UIUX_DIR="$SCRIPT_DIR/../gate-ui-ux"
source "$MECH_DIR/_common.sh"

ATOM_DIR=""
PROJECT_ROOT=""
SKIP=()
ONLY=()
NO_WITNESS=0
# LAW-CL-95 — confidence floor. If set and final manifest.summary.min_confidence
# is below this value, orchestrator exits non-zero AFTER writing manifest+witness
# (so reviewers still see the evidence; the exit code is the machine signal).
# Default 0 = no enforcement (back-compat). Recommended: fast=80, default=95, strict=99.
CONFIDENCE_FLOOR=0
# Stage 0.1 INTENT DECLARATION preflight — orchestrator refuses to run gates
# unless atom/intent/verdict.json exists with next_action=READY. This enforces
# the v8.3 contract that the spec (Stage 1+) is built on confirmed intent, not
# guessing. --skip-intent-check bypasses ONLY for meta-gates / legacy smoke
# tests; production / boss-facing runs MUST keep the preflight on.
SKIP_INTENT_CHECK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --atom-dir)         ATOM_DIR="$2"; shift 2 ;;
    --project-root)     PROJECT_ROOT="$2"; shift 2 ;;
    --skip)             SKIP+=("$2"); shift 2 ;;
    --only)             ONLY+=("$2"); shift 2 ;;
    --no-witness)       NO_WITNESS=1; shift ;;
    --confidence-floor) CONFIDENCE_FLOOR="$2"; shift 2 ;;
    --skip-intent-check) SKIP_INTENT_CHECK=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
: "${ATOM_DIR:?--atom-dir required}"
: "${PROJECT_ROOT:=$(pwd)}"
ATOM_DIR=$(cd "$PROJECT_ROOT" && cd "$ATOM_DIR" && pwd)
PROJECT_ROOT=$(cd "$PROJECT_ROOT" && pwd)
export ATOM_DIR PROJECT_ROOT

log_step orchestrator "atom=$ATOM_DIR project=$PROJECT_ROOT"

# ── Stage 0.1 GATE-INTENT preflight (LAW-CL-95) ────────────────────────
# Without confirmed intent, the rest of the pipeline verifies a spec built on
# guessing — exactly the failure mode v8.3 was created to prevent.
if [[ "$SKIP_INTENT_CHECK" -eq 0 ]]; then
  INTENT_VERDICT="$ATOM_DIR/intent/verdict.json"
  if [[ ! -f "$INTENT_VERDICT" ]]; then
    log_step orchestrator "EXIT 2 GATE-INTENT preflight: $INTENT_VERDICT missing — run scripts/intent/declare-intent.sh first"
    exit 2
  fi
  INTENT_ACTION=$(jq -r '.next_action // "MISSING"' "$INTENT_VERDICT" 2>/dev/null || echo "PARSE_ERROR")
  INTENT_CONF=$(jq -r '.confidence // 0' "$INTENT_VERDICT" 2>/dev/null || echo "0")
  if [[ "$INTENT_ACTION" != "READY" ]]; then
    log_step orchestrator "EXIT 2 GATE-INTENT preflight: next_action=$INTENT_ACTION (expected READY); confidence=$INTENT_CONF"
    exit 2
  fi
  log_step orchestrator "GATE-INTENT preflight OK action=READY confidence=$INTENT_CONF"
fi

# ── --no-witness production guard (LAW-17) ──────────────────────────────
# --no-witness is a smoke-test / CI-local affordance. In production / boss-
# facing runs it must not silently bypass LAW-17. Allow only when caller
# explicitly opts in via env or .build-anything.json non-prod env field.
if [[ "$NO_WITNESS" -eq 1 ]]; then
  ALLOW=0
  [[ "${BUILD_ANYTHING_ALLOW_NO_WITNESS:-0}" == "1" ]] && ALLOW=1
  ENV_FIELD=$(jq -r '.env // "prod"' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo "prod")
  [[ "$ENV_FIELD" == "local" || "$ENV_FIELD" == "dev" || "$ENV_FIELD" == "test" || "$ENV_FIELD" == "ci" ]] && ALLOW=1
  if [[ "$ALLOW" -eq 0 ]]; then
    log_step orchestrator "EXIT 2 --no-witness refused: env=$ENV_FIELD (must be local/dev/test/ci) and BUILD_ANYTHING_ALLOW_NO_WITNESS not set — LAW-17 mandates witness in prod"
    exit 2
  fi
  log_step orchestrator "--no-witness allowed (env=$ENV_FIELD or BUILD_ANYTHING_ALLOW_NO_WITNESS=1)"
fi

# ── Gate registry ──────────────────────────────────────────────────
# id::script::out-rel  (out-rel relative to ATOM_DIR)
GATES=(
  "mech-lint::$MECH_DIR/lint-check.sh::gate-mechanical/lint.json"
  "mech-type::$MECH_DIR/type-check.sh::gate-mechanical/type.json"
  "mech-coverage::$MECH_DIR/coverage-check.sh::gate-mechanical/coverage.json"
  "mech-mutation::$MECH_DIR/mutation-test.sh::gate-mechanical/mutation.json"
  "mech-bundle::$MECH_DIR/bundle-budget.sh::gate-mechanical/bundle.json"
  "mech-lighthouse::$MECH_DIR/lighthouse-check.sh::gate-mechanical/lighthouse.json"
  "mech-load::$MECH_DIR/load-test-smoke.sh::gate-mechanical/load.json"
  "mech-obs::$MECH_DIR/observability-check.sh::gate-mechanical/observability.json"
  "mech-property::$MECH_DIR/property-test-runner.sh::gate-mechanical/property.json"
  "sec-secret::$SEC_DIR/secret-scan.sh::gate-security/secret-scan.json"
  "sec-sqli::$SEC_DIR/sql-injection-scan.sh::gate-security/sql-injection.json"
  "sec-arch::$SEC_DIR/architecture-bridge-check.sh::gate-security/architecture.json"
  "be-invariant::$BACK_DIR/db-invariant-check.sh::gate-backend/db-invariant.json"
  "be-idempotency::$BACK_DIR/idempotency-test.sh::gate-backend/idempotency.json"
  "be-concurrency::$BACK_DIR/concurrency-test.sh::gate-backend/concurrency.json"
  "be-tx::$BACK_DIR/transaction-atomicity-test.sh::gate-backend/transaction-atomicity.json"
  "be-bgjob::$BACK_DIR/background-job-assertion.sh::gate-backend/background-job.json"
  "be-audit::$BACK_DIR/audit-log-assertion.sh::gate-backend/audit-log.json"
  "be-authz::$BACK_DIR/authorization-test.sh::gate-backend/authorization.json"
  "be-tenant::$BACK_DIR/multi-tenant-isolation-test.sh::gate-backend/multi-tenant-isolation.json"
  "be-contract::$BACK_DIR/api-contract-test.sh::gate-backend/api-contract.json"
  "be-cache::$BACK_DIR/cache-invariant-test.sh::gate-backend/cache-invariant.json"
  "be-ratelimit::$BACK_DIR/rate-limit-test.sh::gate-backend/rate-limit.json"
  "cloud-iac::$CLOUD_DIR/iac-drift-check.sh::gate-cloud/iac-drift.json"
  "cloud-ci::$CLOUD_DIR/ci-gate-seal-check.sh::gate-cloud/ci-gate-seal.json"
  "cloud-deploy::$CLOUD_DIR/deployment-runbook-test.sh::gate-cloud/deploy-runbook.json"
  "cloud-slo::$CLOUD_DIR/slo-availability-test.sh::gate-cloud/slo-availability.json"
  "cloud-scaling::$CLOUD_DIR/scaling-proof-test.sh::gate-cloud/scaling-proof.json"
  "spec-pfc::$SPEC_DIR/product-feature-coverage.sh::gate-spec/product-feature-coverage.json"
  "ui-uiux::$UIUX_DIR/audit.sh::gate-ui-ux/ui-audit.json"
)

contains() { local x="$1"; shift; for e in "$@"; do [[ "$e" == "$x" ]] && return 0; done; return 1; }

mkdir -p "$ATOM_DIR/gate-mechanical" "$ATOM_DIR/gate-security" "$ATOM_DIR/gate-backend" "$ATOM_DIR/gate-cloud" "$ATOM_DIR/gate-spec" "$ATOM_DIR/gate-ui-ux"

RAN=0
SKIPPED=0
for entry in "${GATES[@]}"; do
  id=$(awk -F'::' '{print $1}' <<< "$entry")
  script=$(awk -F'::' '{print $2}' <<< "$entry")
  out_rel=$(awk -F'::' '{print $3}' <<< "$entry")

  # filter
  if [[ ${#ONLY[@]} -gt 0 ]] && ! contains "$id" "${ONLY[@]}"; then SKIPPED=$((SKIPPED+1)); continue; fi
  if [[ ${#SKIP[@]} -gt 0 ]] && contains "$id" "${SKIP[@]}"; then log_step orchestrator "SKIP $id (--skip)"; SKIPPED=$((SKIPPED+1)); continue; fi

  if [[ ! -f "$script" ]]; then
    log_step orchestrator "WARN $id: script missing ($script) — emitting N/A"
    emit_na_pending "$id" "$ATOM_DIR/$out_rel" "gate script not implemented yet at $script"
    continue
  fi

  log_step orchestrator "running $id → $out_rel"
  GATE_EXIT=0
  bash "$script" --atom-dir "$ATOM_DIR" --project-root "$PROJECT_ROOT" >/dev/null 2>&1 || GATE_EXIT=$?
  if [[ $GATE_EXIT -ne 0 ]]; then
    log_step orchestrator "  $id exited code=$GATE_EXIT; checking JSON output"
  fi

  # v8.3 silent-drop guard: gate script MUST leave a parseable JSON verdict at
  # $out_rel. If file missing OR not valid JSON OR missing required keys,
  # synthesize an ERROR verdict — never let a crashed gate disappear.
  OUT_PATH="$ATOM_DIR/$out_rel"
  if [[ ! -f "$OUT_PATH" ]]; then
    log_step orchestrator "  $id silent-drop: no JSON written — emitting ERROR"
    emit_error "$id" "$OUT_PATH" "gate script exited code=$GATE_EXIT without writing JSON" "$GATE_EXIT" >/dev/null
  elif ! jq -e 'type == "object" and (has("gate") or has("passed"))' "$OUT_PATH" >/dev/null 2>&1; then
    log_step orchestrator "  $id malformed JSON — emitting ERROR"
    emit_error "$id" "$OUT_PATH" "gate script wrote non-conforming JSON (missing 'gate'/'passed' keys)" "$GATE_EXIT" >/dev/null
  fi
  RAN=$((RAN+1))
done

log_step orchestrator "ran=$RAN skipped=$SKIPPED — aggregating manifest"

# ── Aggregate manifest ─────────────────────────────────────────────
MANIFEST="$ATOM_DIR/manifest.json"
ATOM_NAME=$(basename "$ATOM_DIR")
GATE_FILES=()
for d in gate-mechanical gate-security gate-backend gate-cloud gate-spec gate-ui-ux; do
  if [[ -d "$ATOM_DIR/$d" ]]; then
    for f in "$ATOM_DIR/$d"/*.json; do
      [[ -f "$f" ]] && GATE_FILES+=("$f")
    done
  fi
done

if [[ ${#GATE_FILES[@]} -eq 0 ]]; then
  log_step orchestrator "FATAL: no gate JSON files found in $ATOM_DIR"
  exit 1
fi

jq -s \
  --arg atom "$ATOM_NAME" \
  --arg ran_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '
    # Filter to gate-verdict objects only — skip raw tool dumps (arrays, etc).
    map(select(type=="object" and (has("gate") or has("passed")))) as $g |
    # v8.3 — split ERROR from real FAIL so silent-drop synthetic verdicts are
    # visible as a distinct remediation class (re-run the crashed script,
    # not the same as the assertion having failed).
    ($g | map(select(.verdict == "ERROR"))) as $err |
    ($g | map(select(.passed == false and .verdict != "ERROR"))) as $fail |
    # v8.3 LAW-CL-95 — confidence aggregate so reviewers see the WEAKEST link.
    # An atom with 29 conf=100 PASSes and 1 conf=0 N/A has min_confidence=0,
    # which surfaces the soft spot even though the "pass count" looks clean.
    ($g | map(.confidence // 100)) as $confs |
    ($g | map(.ambiguities // []) | add // []) as $all_amb |
    {
      atom: $atom,
      ran_at: $ran_at,
      schema_version: "ubs-v8.3",
      summary: {
        gates_total: ($g | length),
        pass:  ($g | map(select(.passed==true))  | length),
        fail:  ($fail | length),
        error: ($err  | length),
        na:    ($g | map(select(.passed==null))  | length),
        min_confidence:  ($confs | min // 100),
        mean_confidence: (if ($confs | length) > 0 then (($confs | add) / ($confs | length) | floor) else 100 end),
        open_ambiguities: ($all_amb | length)
      },
      ambiguities: $all_amb,
      gates: (reduce $g[] as $x ({}; . + { ($x.gate // "unknown"): $x }))
    }
  ' "${GATE_FILES[@]}" > "$MANIFEST"

log_step orchestrator "manifest written: $MANIFEST"

# ── SHA-256 + witness ──────────────────────────────────────────────
SHA_FILE="$ATOM_DIR/manifest.sha256"
SHA_VAL=$(shasum -a 256 "$MANIFEST" | awk '{print $1}')
echo "$SHA_VAL  manifest.json" > "$SHA_FILE"
log_step orchestrator "sha256=$SHA_VAL"

if [[ "$NO_WITNESS" -eq 0 ]]; then
  WITNESS_SCRIPT="$SCRIPT_DIR/witness-sign.sh"
  if [[ -f "$WITNESS_SCRIPT" ]]; then
    bash "$WITNESS_SCRIPT" --atom-dir "$ATOM_DIR" --sha "$SHA_VAL" || \
      log_step orchestrator "witness-sign failed (non-blocking)"
  else
    # placeholder witness for environments without cosign
    cat > "$ATOM_DIR/witness.json" <<JSON
{
  "witness": "local-placeholder",
  "witnessed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "manifest_sha256": "$SHA_VAL",
  "note": "LAW-17 witness placeholder — install cosign and witness-sign.sh for keyless OIDC signature"
}
JSON
  fi
fi

# ── Final summary line ─────────────────────────────────────────────
SUMMARY=$(jq -c '.summary' "$MANIFEST")
echo "$SUMMARY"

# exit non-zero if any gate failed or errored (v8.3: ERROR != FAIL, both block)
FAIL_COUNT=$(jq -r '.summary.fail' "$MANIFEST")
ERR_COUNT=$(jq -r '.summary.error // 0' "$MANIFEST")
if [[ "$FAIL_COUNT" -gt 0 || "$ERR_COUNT" -gt 0 ]]; then
  log_step orchestrator "EXIT 1 (fail=$FAIL_COUNT error=$ERR_COUNT)"
  exit 1
fi

# v8.3 LAW-CL-95 enforcement — if user requested a confidence floor, refuse to
# advance when the weakest gate's confidence sits below it. Manifest+witness are
# already written, so reviewers see exactly which gates carried the soft spots.
if [[ "$CONFIDENCE_FLOOR" -gt 0 ]]; then
  MIN_CONF=$(jq -r '.summary.min_confidence // 100' "$MANIFEST")
  if [[ "$MIN_CONF" -lt "$CONFIDENCE_FLOOR" ]]; then
    log_step orchestrator "EXIT 2 LAW-CL-95 floor breach: min_confidence=$MIN_CONF < floor=$CONFIDENCE_FLOOR"
    log_step orchestrator "  ambiguities preserved in $MANIFEST#.ambiguities"
    exit 2
  fi
  log_step orchestrator "LAW-CL-95 PASS min_confidence=$MIN_CONF ≥ floor=$CONFIDENCE_FLOOR"
fi
exit 0
