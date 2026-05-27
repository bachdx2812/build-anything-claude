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
# v8.7.2 priority change (LAW-INTENT-FS): the colleague Flappy Bird / Notion
# test showed that catalog match was unreliable for novel shapes — no entry =
# silent N/A = advance. Source of truth is now `declared.feature_surface[]`
# from Stage 0.1 intent verdict (user-confirmed via enumeration interview).
#
# Algorithm (v8.7.2):
#   1. Read intent/verdict.json → declared.feature_surface[*] where must=true.
#      → primary source of truth (USER said "I need this").
#   2. For each must-item, assert spec.md contains name OR any synonym.
#   3. If feature_surface absent (Stage 0.1 misconfigured), fall back to catalog.
#   4. Explicit `waived: <name>` lines bypass a missing item.
#
# Catalog (./feature-catalog.json) is now hint-only — used in fallback when
# intent verdict lacks feature_surface[].

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

# Lowercase spec text for matching (used by both feature_surface and catalog paths)
SPEC_LC=$(tr '[:upper:]' '[:lower:]' < "$SPEC_FILE")

# ── v8.7.2 PRIMARY PATH — declared.feature_surface[] from intent verdict ──
INTENT_VERDICT="$ATOM_DIR/intent/verdict.json"
if [[ -f "$INTENT_VERDICT" ]]; then
  FS_MUST_COUNT=$(jq -r '[.declared.feature_surface[]? | select(.must==true)] | length' "$INTENT_VERDICT" 2>/dev/null || echo 0)
  if [[ "$FS_MUST_COUNT" -gt 0 ]]; then
    log "using declared.feature_surface[] from intent verdict (must_count=$FS_MUST_COUNT)"
    FS_MISSING=()
    FS_COVERED=()
    for i in $(seq 0 $((FS_MUST_COUNT - 1))); do
      fs_name=$(jq -r --argjson i "$i" '[.declared.feature_surface[] | select(.must==true)][$i].name' "$INTENT_VERDICT")
      found=false
      # Match name (lowercased) as substring, then each synonym
      name_lc=$(printf '%s' "$fs_name" | tr '[:upper:]' '[:lower:]')
      if grep -qF -- "$name_lc" <<<"$SPEC_LC"; then
        found=true
      else
        while IFS= read -r -d '' syn; do
          [[ -z "$syn" ]] && continue
          syn_lc=$(printf '%s' "$syn" | tr '[:upper:]' '[:lower:]')
          if grep -qF -- "$syn_lc" <<<"$SPEC_LC"; then
            found=true
            break
          fi
        done < <(jq -r --argjson i "$i" '[.declared.feature_surface[] | select(.must==true)][$i].synonyms[]?' "$INTENT_VERDICT" 2>/dev/null | tr '\n' '\0')
      fi
      if [[ "$found" == "false" ]]; then
        if grep -qE "waive[d]? *: *$fs_name|exclude[d]? *: *$fs_name" "$SPEC_FILE"; then
          found=true
        fi
      fi
      if [[ "$found" == "true" ]]; then
        FS_COVERED+=("$fs_name")
      else
        FS_MISSING+=("$fs_name")
      fi
    done
    FS_COVERED_JSON=$(printf '%s\n' "${FS_COVERED[@]:-}" | jq -R . | jq -s 'map(select(length > 0))')
    FS_MISSING_JSON=$(printf '%s\n' "${FS_MISSING[@]:-}" | jq -R . | jq -s 'map(select(length > 0))')
    if [[ ${#FS_MISSING[@]} -gt 0 ]]; then
      jq -n --argjson missing "$FS_MISSING_JSON" --arg ran_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
          gate: "GATE-PFC",
          passed: false,
          verdict: "FAIL",
          source: "declared.feature_surface",
          reason: "spec is missing user-declared must-have features (Stage 0.1 feature_surface[*] where must=true)",
          missing_features: $missing,
          confidence: 100,
          ambiguities: [],
          ran_at: $ran_at
        }' > "$OUT"
      exit 1
    fi
    jq -n --argjson covered "$FS_COVERED_JSON" --arg ran_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{
        gate: "GATE-PFC",
        passed: true,
        verdict: "PASS",
        source: "declared.feature_surface",
        covered_features: $covered,
        confidence: 100,
        ambiguities: [],
        ran_at: $ran_at
      }' > "$OUT"
    exit 0
  fi
  log "intent verdict found but feature_surface has no must=true items — falling back to catalog (Stage 0.1 may have misconfigured)"
fi

# ── v8.2 FALLBACK PATH — catalog match (hint-only when no feature_surface) ─
if [[ ! -f "$CATALOG" ]]; then
  emit_na "no feature catalog at $CATALOG — reviewer must populate"
fi

# ── Match product type ─────────────────────────────────────────────
# Catalog: { "<type>": { "keywords": [...], "must_have": [{"name": "...", "synonyms": [...]}], "synonyms": [...] } }
# Use NUL-delimited iteration to avoid bash word-splitting on multi-word keywords.
MATCHED=""
# NOTE on the search form: `grep -qF -- "$kw" <<<"$SPEC_LC"` (here-string),
# NOT `echo "$SPEC_LC" | grep -qF "$kw"`. The pipe form is broken under
# `set -o pipefail` for spec files larger than the pipe buffer (~64KB on
# macOS): grep -q exits on first match → closes pipe → echo gets SIGPIPE
# → echo exits non-zero → pipefail makes the whole pipeline non-zero →
# the `if` condition reads false even though grep matched. Here-strings
# materialise via temp file, no pipe, no SIGPIPE.
while IFS= read -r -d '' key; do
  # Iterate keywords for this type (NUL-delimited so multi-word keywords stay whole)
  while IFS= read -r -d '' kw; do
    # Lowercase for case-insensitive compare; escape regex metachars minimally
    kw_lc=$(printf '%s' "$kw" | tr '[:upper:]' '[:lower:]')
    if grep -qF -- "$kw_lc" <<<"$SPEC_LC"; then
      MATCHED="$key"
      break 2
    fi
  done < <(jq -r --arg k "$key" '.[$k].keywords[]' "$CATALOG" | tr '\n' '\0')
done < <(jq -r 'keys[] | select(startswith("_") | not)' "$CATALOG" | tr '\n' '\0')

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
    # Here-string (not pipe) — see SIGPIPE-under-pipefail note above.
    if grep -qF -- "$syn_lc" <<<"$SPEC_LC"; then
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
