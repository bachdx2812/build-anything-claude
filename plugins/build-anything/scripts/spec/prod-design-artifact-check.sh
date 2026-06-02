#!/usr/bin/env bash
# prod-design-artifact-check.sh — Stage 1.D GATE-PROD-DESIGN-ART (v8.8)
#
# Sibling of production-design-gate.sh (GATE-PROD-DESIGN). That gate is a TEXT
# check: does production-design.md contain the canonical sections with minimum
# prose content? This gate asks the wiring-verification question the audit
# proved was missing: "does a production-design CLAIM leave a real ARTIFACT
# footprint?" — a monitoring rule file behind an SLO, a deploy manifest behind
# a topology — not just markdown prose asserting they exist.
#
# Why: a section can read "p95 < 200ms, 99.9% availability, prometheus alerts
# fire on breach" and PASS GATE-PROD-DESIGN while NO prometheus rule, NO alert,
# NO monitor file exists in the repo. Prose ≠ artifact. Same vacuous-PASS
# disease the GATE-WIRE family cures for capabilities/features, applied to the
# production-design layer.
#
# Citation syntax (inside a ## section body):
#   a line matching (case-insensitive) `artifact:` / `artifacts:` / `- artifact:`
#   followed by a path or glob. The token AFTER the colon is the cited path.
#
# REQUIRED-citation sections (MUST cite + cited artifact MUST exist non-empty):
#   - "SLO targets"          → a monitoring artifact (prometheus rule / monitor / alert)
#   - "Deployment topology"  → a deploy manifest (k8s / helm / terraform / compose)
# OPTIONAL sections ("Failure modes", "Observability story"): if a citation is
#   present the cited artifact MUST exist non-empty; if absent, not required (v1).
#
# LAW-F6: production-design.md absent → N/A_PENDING_REVIEWER (architect persona
# has not run yet), never silent PASS.
# LAW-CL-95: emits confidence + ambiguities[] on every verdict.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_wiring-lang-adapters.sh"

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

DESIGN="$ATOM_DIR/production-design.md"
OUT="$ATOM_DIR/gate-spec/prod-design-artifact.json"
mkdir -p "$(dirname "$OUT")"

log() { echo "[$(date -u +%H:%M:%S)] [prod-design-art] $*" >&2; }

emit_na() {
  local reason="$1" reason_json
  reason_json=$(printf '%s' "$reason" | jq -Rs .)
  cat > "$OUT" <<JSON
{
  "gate": "GATE-PROD-DESIGN-ART",
  "passed": null,
  "verdict": "N/A_PENDING_REVIEWER",
  "reason": $reason_json,
  "confidence": 0,
  "ambiguities": [$reason_json],
  "review_required": true,
  "schema_version": "ubs-v8.8-prod-design-art",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

emit_fail() {
  local findings_json="$1"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-PROD-DESIGN-ART",
  "passed": false,
  "verdict": "FAIL",
  "reason": "production-design claim not backed by a real artifact (missing citation, or cited artifact absent / zero-byte)",
  "findings": $findings_json,
  "confidence": 100,
  "ambiguities": [],
  "schema_version": "ubs-v8.8-prod-design-art",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 1
}

emit_pass() {
  local cited_json="$1"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-PROD-DESIGN-ART",
  "passed": true,
  "verdict": "PASS",
  "cited_artifacts": $cited_json,
  "confidence": 100,
  "ambiguities": [],
  "schema_version": "ubs-v8.8-prod-design-art",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

# ── Preflight (LAW-F6) ────────────────────────────────────────────────
if [[ ! -f "$DESIGN" ]]; then
  emit_na "production-design.md absent — Stage 1.B architect persona has not produced this artefact yet"
fi
if [[ ! -s "$DESIGN" ]]; then
  emit_fail '["production-design.md exists but is empty (zero bytes)"]'
fi

# ── Section body extractor (reused from production-design-gate.sh) ─────
# section_body <header-text> → prints body lines (until next ## or EOF), trimmed.
section_body() {
  local header="$1"
  awk -v h="## $header" '
    BEGIN { inside=0 }
    $0 ~ "^" h "[[:space:]]*$" { inside=1; next }
    inside && /^## / { inside=0 }
    inside { print }
  ' "$DESIGN" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -v '^$' || true
}

# ── Artifact-citation parser ──────────────────────────────────────────
# cited_path_in <body>  → echoes the first cited path token, empty if none.
# Matches a line of the form (case-insensitive, optional leading "- "):
#   artifact: <path>      |   artifacts: <path>      |   - artifact: <path>
# The path token is the first whitespace-delimited word after the colon
# (trailing punctuation/backticks stripped).
cited_path_in() {
  local body="$1" line raw
  line=$(printf '%s\n' "$body" | grep -iE '^[[:space:]]*-?[[:space:]]*artifacts?:' | head -1 || true)
  [[ -z "$line" ]] && return 0
  # Strip everything up to and including the first colon, take first token.
  raw=$(printf '%s' "$line" | sed -E 's/^[^:]*:[[:space:]]*//' | awk '{print $1}')
  # Strip surrounding backticks / quotes / trailing punctuation.
  raw=$(printf '%s' "$raw" | sed -E 's/^[`"'\'']+//; s/[`"'\'',;]+$//')
  printf '%s' "$raw"
}

# artifact_exists_nonempty <path>  → rc 0 if the cited path resolves to a real,
# non-empty file under PROJECT_ROOT. Plain paths use a direct [[ -s ]]; anything
# with glob metacharacters defers to wiring_path_glob_present (handles dir/,
# dir/*.ext, and bare *.ext forms, non-empty enforced).
artifact_exists_nonempty() {
  local p="$1"
  [[ -z "$p" ]] && return 1
  case "$p" in
    *"*"*|*/)
      wiring_path_glob_present "$PROJECT_ROOT" "$p" ;;
    *)
      [[ -s "$PROJECT_ROOT/$p" ]] ;;
  esac
}

FINDINGS=()
CITED=()

# check_section <section> <required:0|1>
check_section() {
  local sec="$1" required="$2" body cited
  body=$(section_body "$sec")
  # Absent section: only matters for REQUIRED sections.
  if [[ -z "$body" ]]; then
    if [[ "$required" -eq 1 ]]; then
      FINDINGS+=("required section '## $sec' missing or empty — must cite a backing artifact")
    fi
    return
  fi
  cited=$(cited_path_in "$body")
  if [[ -z "$cited" ]]; then
    if [[ "$required" -eq 1 ]]; then
      FINDINGS+=("required section '## $sec' has no 'artifact:' citation — claim is prose-only, not backed by a real file")
    fi
    # OPTIONAL with no citation → nothing required (v1).
    return
  fi
  # Citation present (required or optional): the cited artifact MUST exist non-empty.
  if artifact_exists_nonempty "$cited"; then
    CITED+=("$sec → $cited")
  else
    FINDINGS+=("section '## $sec' cites artifact '$cited' but no non-empty file matches it under PROJECT_ROOT")
  fi
}

# REQUIRED-citation sections.
check_section "SLO targets"         1
check_section "Deployment topology" 1
# OPTIONAL sections (cite-then-verify, but citation not mandatory).
check_section "Failure modes"        0
check_section "Observability story"  0

if [[ ${#FINDINGS[@]} -gt 0 ]]; then
  FINDINGS_JSON=$(printf '%s\n' "${FINDINGS[@]}" | jq -R . | jq -s .)
  log "FAIL: ${#FINDINGS[@]} findings"
  emit_fail "$FINDINGS_JSON"
fi

CITED_JSON=$(printf '%s\n' "${CITED[@]:-}" | jq -R . | jq -s 'map(select(length>0))')
log "PASS: ${#CITED[@]} cited artifact(s) verified non-empty"
emit_pass "$CITED_JSON"
