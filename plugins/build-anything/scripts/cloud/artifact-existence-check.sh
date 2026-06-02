#!/usr/bin/env bash
# artifact-existence-check.sh — GATE-CLOUD-ART (v8.8).
#
# The audit (§6 / §12) caught a report claiming "K8s configs ready" while the
# repo's k8s/ directory was EMPTY. GATE-22 (iac-drift) checks Terraform DRIFT,
# but nothing asserted that the cloud/infra artifacts the build CLAIMS to ship
# actually EXIST as non-empty files. A declaration of "k8s deploy" with no
# k8s/*.yaml on disk is exactly the vacuous shape this gate kills.
#
# Algorithm:
#   1. Read .build-anything.json#cloud.required_artifacts[] = array of
#      {"name":"...","glob":"..."} declarations.
#   2. For each, assert wiring_path_glob_present PROJECT_ROOT "$glob"
#      (≥1 NON-EMPTY file matches the glob — dir/, dir/*.ext, or *.ext).
#   3. Any missing → FAIL (missing_artifacts[]). Else PASS (present_artifacts[]).
#
# LAW-F6: empty/absent required_artifacts ⇒ N/A_PENDING_REVIEWER, never a
# silent PASS — an unconfigured cloud surface must be reviewed, not waved through.
# LAW-CL-95: confidence + ambiguities[] on every verdict.
#
# Contract: bash script → stdout integer rc + JSON evidence file.
#   exit 0 = PASS or N/A; exit 1 = FAIL (declared artifact missing).
#
# bash 3.2 compatible (macOS default). No mapfile, no globstar.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../spec/_wiring-lang-adapters.sh"

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
CONFIG="$PROJECT_ROOT/.build-anything.json"
OUT="$ATOM_DIR/gate-cloud/artifact-existence.json"
mkdir -p "$(dirname "$OUT")"

log() { echo "[$(date -u +%H:%M:%S)] [cloud-art] $*" >&2; }

emit_na() {
  local reason="$1" reason_json
  reason_json=$(printf '%s' "$reason" | jq -Rs .)
  cat > "$OUT" <<JSON
{
  "gate": "GATE-CLOUD-ART",
  "passed": null,
  "verdict": "N/A_PENDING_REVIEWER",
  "reason": $reason_json,
  "confidence": 0,
  "ambiguities": [$reason_json],
  "review_required": true,
  "schema_version": "ubs-v8.8-cloud-art",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

emit_fail() {
  local kind="$1" missing="$2" present="$3" kind_json
  kind_json=$(printf '%s' "$kind" | jq -Rs .)
  cat > "$OUT" <<JSON
{
  "gate": "GATE-CLOUD-ART",
  "passed": false,
  "verdict": "FAIL",
  "reason": "declared cloud/infra artifact has no non-empty file on disk (report claims ready, repo is empty)",
  "artifact_kind": $kind_json,
  "missing_artifacts": $missing,
  "present_artifacts": $present,
  "confidence": 100,
  "ambiguities": [],
  "schema_version": "ubs-v8.8-cloud-art",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 1
}

emit_pass() {
  local kind="$1" present="$2" kind_json
  kind_json=$(printf '%s' "$kind" | jq -Rs .)
  cat > "$OUT" <<JSON
{
  "gate": "GATE-CLOUD-ART",
  "passed": true,
  "verdict": "PASS",
  "artifact_kind": $kind_json,
  "present_artifacts": $present,
  "confidence": 100,
  "ambiguities": [],
  "schema_version": "ubs-v8.8-cloud-art",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

# ── LAW-F6 input guard ────────────────────────────────────────────────
[[ ! -f "$CONFIG" ]] && emit_na "no .build-anything.json at $PROJECT_ROOT — no declared cloud artifacts to verify"

CONFIG_JSON=$(cat "$CONFIG")

# Validate the config parses and required_artifacts is a non-empty array.
COUNT=$(jq -r '(.cloud.required_artifacts // []) | length' <<<"$CONFIG_JSON" 2>/dev/null || echo 0)
[[ "$COUNT" =~ ^[0-9]+$ ]] || COUNT=0
if [[ "$COUNT" -eq 0 ]]; then
  emit_na "cloud.required_artifacts is empty or absent — reviewer must declare expected infra artifacts OR confirm atom ships none"
fi

# Optional context tag (no behavior change in v1).
ARTIFACT_KIND=$(jq -r '.cloud.artifact_kind // empty' <<<"$CONFIG_JSON" 2>/dev/null || true)
[[ "$ARTIFACT_KIND" == "null" ]] && ARTIFACT_KIND=""

log "checking $COUNT declared artifact(s) kind='${ARTIFACT_KIND:-unset}' root=$PROJECT_ROOT"

# ── Per-artifact existence check ──────────────────────────────────────
MISSING=()
PRESENT=()

i=0
while [[ "$i" -lt "$COUNT" ]]; do
  NAME=$(jq -r --argjson i "$i" '.cloud.required_artifacts[$i].name // empty' <<<"$CONFIG_JSON" 2>/dev/null || true)
  GLOB=$(jq -r --argjson i "$i" '.cloud.required_artifacts[$i].glob // empty' <<<"$CONFIG_JSON" 2>/dev/null || true)
  i=$((i+1))

  # A declaration with no glob cannot be verified — treat as missing (reviewer
  # must supply a concrete path pattern; we never fabricate a PASS).
  if [[ -z "$GLOB" || "$GLOB" == "null" ]]; then
    MISSING+=("${NAME:-unnamed}: no glob declared (reviewer must supply a path pattern)")
    continue
  fi
  [[ -z "$NAME" || "$NAME" == "null" ]] && NAME="$GLOB"

  if wiring_path_glob_present "$PROJECT_ROOT" "$GLOB"; then
    PRESENT+=("$NAME ($GLOB)")
  else
    MISSING+=("$NAME: no non-empty file matches $GLOB")
  fi
done

MISSING_JSON=$(printf '%s\n' "${MISSING[@]:-}" | jq -R . | jq -s 'map(select(length>0))')
PRESENT_JSON=$(printf '%s\n' "${PRESENT[@]:-}" | jq -R . | jq -s 'map(select(length>0))')

if [[ ${#MISSING[@]} -gt 0 ]]; then
  log "FAIL: missing=${#MISSING[@]} present=${#PRESENT[@]}"
  emit_fail "$ARTIFACT_KIND" "$MISSING_JSON" "$PRESENT_JSON"
fi

log "PASS: present=${#PRESENT[@]}"
emit_pass "$ARTIFACT_KIND" "$PRESENT_JSON"
