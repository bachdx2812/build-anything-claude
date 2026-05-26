#!/usr/bin/env bash
# product-feature-coverage.sh — Stage 1 GATE-PFC
#
# Purpose: catch fundamental SPEC gaps where the atom claims to build product
# type X (e.g. "youtube clone") but its declared success_criteria omit the
# canonical feature set for that product (e.g. upload+play video for youtube).
#
# Why: a previous v8.1 run shipped a "youtube clone" that had NO upload and
# NO play. Stage 1 declared PASS. The spec was the bug. This gate exists to
# prevent that class of vacuous PASS.
#
# Algorithm:
#   1. Read atom spec (success_criteria + product description).
#   2. Match product description against catalog of canonical product types.
#   3. If match → assert every canonical feature appears in success_criteria
#      OR is explicitly waived in spec.waivers[] with reason.
#   4. If no match → emit N/A_PENDING_REVIEWER (LAW-F6: never vacuous PASS).
#
# Catalog is data, not code — see ./feature-catalog.json. Reviewers extend it.

set -euo pipefail

ATOM_DIR=""
CATALOG="$(dirname "$0")/feature-catalog.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --atom-dir) ATOM_DIR="$2"; shift 2 ;;
    --catalog)  CATALOG="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${ATOM_DIR:?--atom-dir required}"
SPEC_FILE="$ATOM_DIR/spec.md"
OUT="$ATOM_DIR/gate-spec/product-feature-coverage.json"
mkdir -p "$(dirname "$OUT")"

log() { echo "[$(date -u +%H:%M:%S)] [pfc] $*" >&2; }

# LAW-CL-95 — every verdict carries {confidence, ambiguities}.
# PFC matches keywords in spec text → mechanical match, confidence=100 when matched.
# N/A = no match → confidence=0; reason becomes the ambiguity.
emit_na() {
  local reason_json
  reason_json=$(printf '%s' "$1" | jq -Rs . 2>/dev/null || printf '"%s"' "$1")
  cat > "$OUT" <<JSON
{
  "gate": "GATE-PFC",
  "passed": null,
  "verdict": "N/A_PENDING_REVIEWER",
  "reason": "$1",
  "confidence": 0,
  "ambiguities": [$reason_json],
  "review_required": true,
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

emit_fail() {
  local missing="$1"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-PFC",
  "passed": false,
  "verdict": "FAIL",
  "reason": "spec is missing canonical features for the declared product type",
  "missing_features": $missing,
  "confidence": 100,
  "ambiguities": [],
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 1
}

emit_pass() {
  local matched_type="$1" covered="$2"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-PFC",
  "passed": true,
  "verdict": "PASS",
  "product_type": "$matched_type",
  "covered_features": $covered,
  "confidence": 100,
  "ambiguities": [],
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

# ── Read spec ──────────────────────────────────────────────────────
if [[ ! -f "$SPEC_FILE" ]]; then
  emit_na "no spec.md at $SPEC_FILE — cannot check feature coverage"
fi

# ── Load catalog ───────────────────────────────────────────────────
if [[ ! -f "$CATALOG" ]]; then
  emit_na "no feature catalog at $CATALOG — reviewer must populate"
fi

# Lowercase spec text for matching
SPEC_LC=$(tr '[:upper:]' '[:lower:]' < "$SPEC_FILE")

# ── Match product type ─────────────────────────────────────────────
# Catalog: { "<type>": { "keywords": [...], "must_have": [{"name": "...", "synonyms": [...]}], "synonyms": [...] } }
# Use NUL-delimited iteration to avoid bash word-splitting on multi-word keywords.
MATCHED=""
while IFS= read -r -d '' key; do
  # Iterate keywords for this type (NUL-delimited so multi-word keywords stay whole)
  while IFS= read -r -d '' kw; do
    # Lowercase for case-insensitive compare; escape regex metachars minimally
    kw_lc=$(printf '%s' "$kw" | tr '[:upper:]' '[:lower:]')
    if echo "$SPEC_LC" | grep -qF "$kw_lc"; then
      MATCHED="$key"
      break 2
    fi
  done < <(jq -r --arg k "$key" '.[$k].keywords[]' "$CATALOG" | tr '\n' '\0')
done < <(jq -r 'keys[]' "$CATALOG" | tr '\n' '\0')

if [[ -z "$MATCHED" ]]; then
  emit_na "no canonical product type matched in spec text — reviewer must confirm product type is novel OR add type to catalog"
fi

log "matched product type: $MATCHED"

# ── Check every must_have feature appears in spec ──────────────────
MISSING=()
COVERED=()
mh_count=$(jq -r --arg k "$MATCHED" '.[$k].must_have | length' "$CATALOG")
for i in $(seq 0 $((mh_count - 1))); do
  name=$(jq -r --arg k "$MATCHED" --argjson i "$i" '.[$k].must_have[$i].name' "$CATALOG")
  found=false
  # Try each synonym (NUL-delimited to preserve multi-word terms) then the canonical name
  while IFS= read -r -d '' syn; do
    syn_lc=$(printf '%s' "$syn" | tr '[:upper:]' '[:lower:]')
    if echo "$SPEC_LC" | grep -qF "$syn_lc"; then
      found=true
      break
    fi
  done < <(jq -r --arg k "$MATCHED" --argjson i "$i" '.[$k].must_have[$i].synonyms[], .[$k].must_have[$i].name' "$CATALOG" | tr '\n' '\0')
  # Also accept explicit waiver
  if [[ "$found" == "false" ]]; then
    if grep -qE "waive[d]? *: *$name|exclude[d]? *: *$name" "$SPEC_FILE"; then
      found=true
    fi
  fi
  if [[ "$found" == "true" ]]; then
    COVERED+=("$name")
  else
    MISSING+=("$name")
  fi
done

COVERED_JSON=$(printf '%s\n' "${COVERED[@]:-}" | jq -R . | jq -s 'map(select(length > 0))')
MISSING_JSON=$(printf '%s\n' "${MISSING[@]:-}" | jq -R . | jq -s 'map(select(length > 0))')

if [[ ${#MISSING[@]} -gt 0 ]]; then
  emit_fail "$MISSING_JSON"
fi

emit_pass "$MATCHED" "$COVERED_JSON"
