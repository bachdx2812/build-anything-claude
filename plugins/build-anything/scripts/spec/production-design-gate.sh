#!/usr/bin/env bash
# production-design-gate.sh — Stage 1.D GATE-PROD-DESIGN (v8.5)
#
# Purpose: prevent the skill from emitting a v8.5 architecture without the
# production-design layer (capacity model, failure modes, SLOs, etc.). The
# architect persona must produce {atom_dir}/production-design.md with the
# canonical sections; this gate verifies presence + minimum content rules.
#
# Why: v8.5 audit found stacks were picked with no thought given to:
#   - capacity (RPS / storage / bandwidth numbers)
#   - failure modes (what breaks, how do we know, how do we roll back)
#   - SLOs (what guarantees do we offer)
#   - tenancy / data lifecycle / observability
# Skipping these is how MVPs ship and immediately collapse under traffic.
#
# Required sections (body presence + min-content rules):
#   1. Capacity model            (body MUST contain digits 0-9)
#   2. Failure modes             (body MUST contain ≥3 markdown table data rows)
#   3. Tenancy model             (body present)
#   4. Data lifecycle            (body present)
#   5. SLO targets               (body MUST contain "p95" AND ("%" OR "availability"))
#   6. Deployment topology       (body present)
#   7. Observability story       (body present)
#   8. Boring-tech justification (body present)
#
# LAW-F6: no vacuous PASS. Missing file or no body → N/A_PENDING_REVIEWER or FAIL,
# never silent-PASS.
# LAW-CL-95: emits confidence + ambiguities[].

set -euo pipefail

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
OUT="$ATOM_DIR/gate-spec/prod-design.json"
mkdir -p "$(dirname "$OUT")"

log() { echo "[$(date -u +%H:%M:%S)] [prod-design] $*" >&2; }

emit_na() {
  local reason="$1"
  local reason_json
  reason_json=$(printf '%s' "$reason" | jq -Rs .)
  cat > "$OUT" <<JSON
{
  "gate": "GATE-PROD-DESIGN",
  "passed": null,
  "verdict": "N/A_PENDING_REVIEWER",
  "reason": $reason_json,
  "confidence": 0,
  "ambiguities": [$reason_json],
  "review_required": true,
  "schema_version": "ubs-v8.5-prod-design",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

emit_fail() {
  local findings_json="$1"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-PROD-DESIGN",
  "passed": false,
  "verdict": "FAIL",
  "reason": "production-design.md missing required sections or content rules",
  "findings": $findings_json,
  "confidence": 100,
  "ambiguities": [],
  "schema_version": "ubs-v8.5-prod-design",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 1
}

emit_pass() {
  local sections_json="$1"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-PROD-DESIGN",
  "passed": true,
  "verdict": "PASS",
  "sections_present": $sections_json,
  "confidence": 100,
  "ambiguities": [],
  "schema_version": "ubs-v8.5-prod-design",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

# ── Read project_type from .build-anything.json (v8.6: mobile SLI dialect) ─
PROJECT_TYPE="backend"
if [[ -f "$PROJECT_ROOT/.build-anything.json" ]]; then
  PROJECT_TYPE=$(jq -r '.project_type // "backend"' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo "backend")
fi

# ── Preflight ─────────────────────────────────────────────────────
if [[ ! -f "$DESIGN" ]]; then
  emit_na "production-design.md absent — Stage 1.B architect persona has not produced this artefact yet"
fi

if [[ ! -s "$DESIGN" ]]; then
  emit_fail '["production-design.md exists but is empty (zero bytes)"]'
fi

# ── Section body extractor ────────────────────────────────────────
# section_body <header-text> → prints body lines (until next ## or EOF)
section_body() {
  local header="$1"
  awk -v h="## $header" '
    BEGIN { inside=0 }
    $0 ~ "^" h "[[:space:]]*$" { inside=1; next }
    inside && /^## / { inside=0 }
    inside { print }
  ' "$DESIGN" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -v '^$' || true
}

FINDINGS=()
SECTIONS_PRESENT=()

# Required sections list
REQUIRED_SECTIONS=(
  "Capacity model"
  "Failure modes"
  "Tenancy model"
  "Data lifecycle"
  "SLO targets"
  "Deployment topology"
  "Observability story"
  "Boring-tech justification"
)

for sec in "${REQUIRED_SECTIONS[@]}"; do
  body=$(section_body "$sec")
  if [[ -z "$body" ]]; then
    FINDINGS+=("section '## $sec' missing or empty body")
    continue
  fi
  SECTIONS_PRESENT+=("$sec")

  case "$sec" in
    "Capacity model")
      # Body must contain at least one digit
      if ! echo "$body" | grep -qE '[0-9]'; then
        FINDINGS+=("section '## Capacity model' has no digits — adjectives are not capacity numbers")
      fi
      ;;
    "Failure modes")
      # Count markdown table data rows: lines starting with | that are not header/separator
      rows=$(echo "$body" | awk '
        /^\|/ {
          # Skip separator rows like |---|---|
          if ($0 ~ /^\|[[:space:]]*-+[[:space:]]*\|/) next
          # Skip header row (first row with | Failure |)
          if ($0 ~ /^\|[[:space:]]*Failure[[:space:]]*\|/) { is_header=1; next }
          # Count as data row if it has at least 3 pipe-delimited columns
          if (gsub(/\|/, "|") >= 4) print
        }
      ' | wc -l | tr -d ' ')
      if [[ "$rows" -lt 3 ]]; then
        FINDINGS+=("section '## Failure modes' has $rows data rows; need ≥3")
      fi
      ;;
    "SLO targets")
      lower=$(echo "$body" | tr '[:upper:]' '[:lower:]')
      case "$PROJECT_TYPE" in
        mobile-*)
          # v8.6 mobile SLI dialect: accept cold-start / jank / crash-free in
          # addition to web's p95 / availability. Mobile cares about app-side
          # perceived latency + stability, not backend p95.
          latency_ok=0
          stability_ok=0
          echo "$lower" | grep -qE '(p95|p99|cold[- ]?start|jank|frame[- ]?drop|launch[- ]?time)' && latency_ok=1
          echo "$lower" | grep -qE '(%|availability|crash[- ]?free|anr[- ]?rate)' && stability_ok=1
          if [[ "$latency_ok" -eq 0 ]]; then
            FINDINGS+=("section '## SLO targets' missing latency SLI — need p95/p99 OR cold-start OR jank/frame-drop OR launch-time for project_type=$PROJECT_TYPE")
          fi
          if [[ "$stability_ok" -eq 0 ]]; then
            FINDINGS+=("section '## SLO targets' missing stability SLI — need availability/% OR crash-free OR ANR-rate for project_type=$PROJECT_TYPE")
          fi
          ;;
        *)
          if ! echo "$lower" | grep -q 'p95'; then
            FINDINGS+=("section '## SLO targets' missing 'p95' — latency SLI required")
          fi
          if ! echo "$lower" | grep -qE '(%|availability)'; then
            FINDINGS+=("section '## SLO targets' missing '%' or 'availability' — availability SLO required")
          fi
          ;;
      esac
      ;;
  esac
done

if [[ ${#FINDINGS[@]} -gt 0 ]]; then
  FINDINGS_JSON=$(printf '%s\n' "${FINDINGS[@]}" | jq -R . | jq -s .)
  log "FAIL: ${#FINDINGS[@]} findings"
  emit_fail "$FINDINGS_JSON"
fi

SECTIONS_JSON=$(printf '%s\n' "${SECTIONS_PRESENT[@]}" | jq -R . | jq -s .)
log "PASS: ${#SECTIONS_PRESENT[@]} sections present with required content"
emit_pass "$SECTIONS_JSON"
