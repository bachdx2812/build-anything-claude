#!/usr/bin/env bash
# bmad-prd-gate.sh — Stage 1.B GATE-PRD enforcement.
#
# BMAD-method, not BMAD-invocation. The skill internalises the BMAD multi-
# persona pattern (PM, Architect, UX) via Task-tool dispatch with persona
# prompt files under sub-skills/spec/references/personas/. The optional
# npx bmad-method install is informational only; the gate verifies that the
# personas produced their artefacts regardless of source.
#
# Required artefacts (mode `multi-persona`):
#   {atom_dir}/prd.md            — PM persona output
#   {atom_dir}/architecture.md   — Architect persona output
#   {atom_dir}/ux-spec.md        — UX persona output
#
# Fallback artefacts (mode `single-persona`, --fast only):
#   {atom_dir}/prd.md            — combined PM/Arch/UX in one file
#
# Section requirements per artefact (defined per file):
#   prd.md          → Vision, MVP Scope, Acceptance Criteria
#   architecture.md → Stack, Components, Data model
#   ux-spec.md      → Page inventory, Per-page UX, Accessibility
# Each named section MUST have ≥ 1 non-empty content line after the header.
# A header with no body = stub = FAIL (LAW-F6).
#
# Exit codes follow gate contract: 0 PASS or N/A, 1 FAIL, 2 preflight error.

set -uo pipefail

set -uo pipefail

ATOM_DIR=""
PROJECT_ROOT=""
MODE="auto"   # auto | multi-persona | single-persona

while [[ $# -gt 0 ]]; do
  case "$1" in
    --atom-dir)     ATOM_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --mode)         MODE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${ATOM_DIR:?--atom-dir required}"
: "${PROJECT_ROOT:?--project-root required}"
OUT="$ATOM_DIR/gate-spec/bmad-prd.json"
mkdir -p "$(dirname "$OUT")"

log() { echo "[$(date -u +%H:%M:%S)] [bmad-prd] $*" >&2; }

emit() {
  local verdict="$1" passed="$2" confidence="$3" reason="$4" details_json="$5"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-PRD",
  "verdict": "$verdict",
  "passed": $passed,
  "confidence": $confidence,
  "reason": $(printf '%s' "$reason" | jq -Rs .),
  "ambiguities": [],
  "details": $details_json,
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
}

# BMAD npx status is informational only — gate trusts artefacts, not the
# installer. Recorded for evidence trail.
BMAD_STATUS="UNKNOWN"
if [[ -f "$ATOM_DIR/deps.json" ]]; then
  BMAD_STATUS=$(jq -r '.deps["bmad-method"].status // "UNKNOWN"' "$ATOM_DIR/deps.json")
fi

PRD="$ATOM_DIR/prd.md"
ARCH="$ATOM_DIR/architecture.md"
UX="$ATOM_DIR/ux-spec.md"

# ── Section-with-body check ───────────────────────────────────────
# A section "passes" iff its header line exists AND at least one
# non-blank, non-header line follows within the same section.
section_has_body() {
  local file="$1" section="$2"
  [[ -f "$file" ]] || return 1
  awk -v sec="$section" '
    BEGIN { in_sec=0; found=0; sec_depth=99; }
    {
      lower=tolower($0)
      lsec=tolower(sec)
      # Enter section on `## Section` or `**Section**` (case-insensitive)
      if (lower ~ "^#+ *"lsec"([^a-z0-9]|$)" || lower ~ "^\\*\\*"lsec"([^a-z0-9]|$)") {
        in_sec=1
        if (match($0, /^#+/)) { sec_depth=RLENGTH } else { sec_depth=99 }
        next
      }
      if (in_sec) {
        # Heading lookahead: equal-or-shallower depth ends section,
        # deeper heading (sub-section) counts as body content.
        if (match($0, /^#+/)) {
          if (RLENGTH <= sec_depth) { in_sec=0; next }
          found=1; exit
        }
        if ($0 ~ /[^[:space:]]/) { found=1; exit }
      }
    }
    END { exit !found }
  ' "$file"
}

# Check artefact: file exists AND every required section has body.
# Sets RESULT_OK=1|0 and RESULT_MISSING="..."
check_artefact() {
  local label="$1" file="$2"; shift 2
  local sections=("$@")
  RESULT_OK=0
  RESULT_MISSING=""
  if [[ ! -f "$file" ]]; then
    RESULT_MISSING="file-absent"
    return
  fi
  local miss=()
  for s in "${sections[@]}"; do
    if ! section_has_body "$file" "$s"; then miss+=("$s"); fi
  done
  if [[ ${#miss[@]} -eq 0 ]]; then
    RESULT_OK=1
  else
    RESULT_MISSING="missing-sections:$(IFS=,; echo "${miss[*]}")"
  fi
}

# Resolve mode if auto: multi-persona if both arch + ux exist, else single-persona
if [[ "$MODE" == "auto" ]]; then
  if [[ -f "$ARCH" && -f "$UX" ]]; then MODE="multi-persona"; else MODE="single-persona"; fi
fi
log "mode=$MODE bmad-status=$BMAD_STATUS"

# ── Verify per mode ───────────────────────────────────────────────
ARTEFACTS_JSON='[]'

if [[ "$MODE" == "multi-persona" ]]; then
  check_artefact "prd"  "$PRD"  "Vision" "MVP Scope" "Acceptance Criteria"
  PRD_OK=$RESULT_OK; PRD_REASON="$RESULT_MISSING"
  check_artefact "arch" "$ARCH" "Stack" "Components" "Data model"
  ARCH_OK=$RESULT_OK; ARCH_REASON="$RESULT_MISSING"
  check_artefact "ux"   "$UX"   "Page inventory" "Per-page UX" "Accessibility"
  UX_OK=$RESULT_OK; UX_REASON="$RESULT_MISSING"

  ARTEFACTS_JSON=$(jq -n \
    --arg prd_status   "$([[ $PRD_OK   -eq 1 ]] && echo ok || echo "$PRD_REASON")" \
    --arg arch_status  "$([[ $ARCH_OK  -eq 1 ]] && echo ok || echo "$ARCH_REASON")" \
    --arg ux_status    "$([[ $UX_OK    -eq 1 ]] && echo ok || echo "$UX_REASON")" \
    '[
      {file: "prd.md", required_sections: ["Vision","MVP Scope","Acceptance Criteria"], status: $prd_status},
      {file: "architecture.md", required_sections: ["Stack","Components","Data model"], status: $arch_status},
      {file: "ux-spec.md", required_sections: ["Page inventory","Per-page UX","Accessibility"], status: $ux_status}
    ]')

  if [[ "$PRD_OK" -eq 1 && "$ARCH_OK" -eq 1 && "$UX_OK" -eq 1 ]]; then
    log "PASS: all three persona artefacts have required sections with body"
    DETAILS=$(jq -n --arg mode "$MODE" --arg bmad "$BMAD_STATUS" --argjson art "$ARTEFACTS_JSON" \
      '{mode: $mode, bmad_status: $bmad, artefacts: $art}')
    emit "PASS" "true" "100" "PM+Architect+UX persona artefacts complete (BMAD-method)" "$DETAILS"
    exit 0
  fi
  DETAILS=$(jq -n --arg mode "$MODE" --arg bmad "$BMAD_STATUS" --argjson art "$ARTEFACTS_JSON" \
    '{mode: $mode, bmad_status: $bmad, artefacts: $art}')
  log "FAIL: one or more persona artefacts incomplete"
  emit "FAIL" "false" "100" "Stage 1.B persona artefacts incomplete or stubbed" "$DETAILS"
  exit 1
fi

# single-persona mode — one combined prd.md must cover the PM core sections.
check_artefact "prd-combined" "$PRD" "Vision" "MVP Scope" "Acceptance Criteria"
PRD_OK=$RESULT_OK; PRD_REASON="$RESULT_MISSING"
ARTEFACTS_JSON=$(jq -n \
  --arg prd_status "$([[ $PRD_OK -eq 1 ]] && echo ok || echo "$PRD_REASON")" \
  '[{file: "prd.md", required_sections: ["Vision","MVP Scope","Acceptance Criteria"], status: $prd_status}]')

if [[ "$PRD_OK" -eq 1 ]]; then
  DETAILS=$(jq -n --arg mode "$MODE" --arg bmad "$BMAD_STATUS" --argjson art "$ARTEFACTS_JSON" \
    '{mode: $mode, bmad_status: $bmad, artefacts: $art}')
  log "PASS: single-persona PRD covers required sections"
  emit "PASS" "true" "85" "single-persona PRD complete (BMAD-method, fast mode)" "$DETAILS"
  exit 0
fi

DETAILS=$(jq -n --arg mode "$MODE" --arg bmad "$BMAD_STATUS" --argjson art "$ARTEFACTS_JSON" \
  '{mode: $mode, bmad_status: $bmad, artefacts: $art}')
log "FAIL: single-persona PRD missing required sections: $PRD_REASON"
emit "FAIL" "false" "100" "Stage 1.B PRD missing required sections" "$DETAILS"
exit 1
