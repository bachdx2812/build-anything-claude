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
source "$MECH_DIR/_common.sh"

ATOM_DIR=""
PROJECT_ROOT=""
SKIP=()
ONLY=()
NO_WITNESS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --atom-dir)     ATOM_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --skip)         SKIP+=("$2"); shift 2 ;;
    --only)         ONLY+=("$2"); shift 2 ;;
    --no-witness)   NO_WITNESS=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
: "${ATOM_DIR:?--atom-dir required}"
: "${PROJECT_ROOT:=$(pwd)}"
ATOM_DIR=$(cd "$PROJECT_ROOT" && cd "$ATOM_DIR" && pwd)
PROJECT_ROOT=$(cd "$PROJECT_ROOT" && pwd)
export ATOM_DIR PROJECT_ROOT

log_step orchestrator "atom=$ATOM_DIR project=$PROJECT_ROOT"

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
  "cloud-ci::$CLOUD_DIR/ci-gate-seal-check.sh::gate-cloud/ci-seal.json"
  "cloud-deploy::$CLOUD_DIR/deployment-runbook-test.sh::gate-cloud/deployment-runbook.json"
  "cloud-slo::$CLOUD_DIR/slo-availability-test.sh::gate-cloud/slo.json"
  "cloud-scaling::$CLOUD_DIR/scaling-proof-test.sh::gate-cloud/scaling.json"
)

contains() { local x="$1"; shift; for e in "$@"; do [[ "$e" == "$x" ]] && return 0; done; return 1; }

mkdir -p "$ATOM_DIR/gate-mechanical" "$ATOM_DIR/gate-security" "$ATOM_DIR/gate-backend" "$ATOM_DIR/gate-cloud"

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
  if bash "$script" --atom-dir "$ATOM_DIR" --project-root "$PROJECT_ROOT" >/dev/null 2>&1; then
    :
  else
    # FAIL or runtime error — script should already have emitted JSON on its own
    log_step orchestrator "  $id exited non-zero (FAIL or runtime); see $out_rel"
  fi
  RAN=$((RAN+1))
done

log_step orchestrator "ran=$RAN skipped=$SKIPPED — aggregating manifest"

# ── Aggregate manifest ─────────────────────────────────────────────
MANIFEST="$ATOM_DIR/manifest.json"
ATOM_NAME=$(basename "$ATOM_DIR")
GATE_FILES=()
for d in gate-mechanical gate-security gate-backend gate-cloud; do
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
    {
      atom: $atom,
      ran_at: $ran_at,
      schema_version: "ubs-v8.1",
      summary: {
        gates_total: ($g | length),
        pass:  ($g | map(select(.passed==true))  | length),
        fail:  ($g | map(select(.passed==false)) | length),
        na:    ($g | map(select(.passed==null))  | length)
      },
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

# exit non-zero if any gate failed
FAIL_COUNT=$(jq -r '.summary.fail' "$MANIFEST")
[[ "$FAIL_COUNT" -gt 0 ]] && exit 1 || exit 0
