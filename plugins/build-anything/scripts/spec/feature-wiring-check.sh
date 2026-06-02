#!/usr/bin/env bash
# feature-wiring-check.sh — Stage 4 GATE-PFC-WIRE (v8.8)
#
# Sibling of product-feature-coverage.sh (GATE-PFC). GATE-PFC asks "is the
# user-declared must-have feature NAMED in spec.md?" — a TEXT check on the
# declaration. GATE-PFC-WIRE asks the question the audit proved was missing:
# "does that declared feature leave a real FOOTPRINT in the built repo — a
# route, a handler symbol, and a test that exercise it?".
#
# Audit shape: a build named "video upload" in its feature_surface, GATE-PFC
# passed because spec.md said the words — but no /api/upload route existed, no
# UploadHandler symbol, no TestUpload. Declaration ≠ wired implementation.
#
# Algorithm:
#   1. Read intent/verdict.json → declared.feature_surface[*] where must=true.
#      Absent OR zero must-items → N/A_PENDING_REVIEWER (LAW-F6).
#   2. Surface guard: if the repo has NO source files at all, the build has not
#      reached Stage 4 — emit N/A rather than FAIL the whole world (mirror of
#      capability-wiring-check.sh HAS_SURFACE).
#   3. Read .build-anything.json#feature_wiring (object keyed by feature name;
#      each value {"routes":[...],"handlers":[...],"test_refs":[...]}).
#   4. Per must-have feature (case-insensitive name match into feature_wiring):
#        - NO entry → unwired (named in spec but never declared where wired).
#        - entry present → WIRED iff every route string is in SOURCE, every
#          handler symbol is in SOURCE, and ≥1 test_ref is in SOURCE. An
#          empty/omitted category is skipped, but ≥1 category must be present
#          AND satisfied.
#        - record each missing route / handler / test_ref.
#   5. Any unwired must-have feature → FAIL. Else PASS.
#
# Footprint is SOURCE CODE only — the adapters' source-symbol search excludes
# .build-anything.json and lockfiles, so a feature that exists ONLY in config
# is exactly the vacuous PASS we are killing.
#
# LAW-CL-95: confidence + ambiguities[] on every verdict.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_wiring-lang-adapters.sh"

ATOM_DIR=""
PROJECT_ROOT=""
CATALOG="$SCRIPT_DIR/feature-catalog.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --atom-dir)     ATOM_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --catalog)      CATALOG="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${ATOM_DIR:?--atom-dir required}"
: "${PROJECT_ROOT:?--project-root required}"
CONFIG="$PROJECT_ROOT/.build-anything.json"
OUT="$ATOM_DIR/gate-spec/feature-wiring.json"
mkdir -p "$(dirname "$OUT")"

log() { echo "[$(date -u +%H:%M:%S)] [feat-wire] $*" >&2; }

emit_na() {
  local reason="$1" reason_json
  reason_json=$(printf '%s' "$reason" | jq -Rs .)
  cat > "$OUT" <<JSON
{
  "gate": "GATE-PFC-WIRE",
  "passed": null,
  "verdict": "N/A_PENDING_REVIEWER",
  "reason": $reason_json,
  "confidence": 0,
  "ambiguities": [$reason_json],
  "review_required": true,
  "schema_version": "ubs-v8.8-pfc-wire",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

emit_fail() {
  local unwired="$1" wired="$2"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-PFC-WIRE",
  "passed": false,
  "verdict": "FAIL",
  "reason": "must-have feature declared but not wired in built repo (missing route, handler symbol, or test reference in source)",
  "unwired_features": $unwired,
  "wired_features": $wired,
  "confidence": 100,
  "ambiguities": [],
  "schema_version": "ubs-v8.8-pfc-wire",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 1
}

emit_pass() {
  local wired="$1"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-PFC-WIRE",
  "passed": true,
  "verdict": "PASS",
  "wired_features": $wired,
  "confidence": 100,
  "ambiguities": [],
  "schema_version": "ubs-v8.8-pfc-wire",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

# ── LAW-F6 PRIMARY INPUT — declared.feature_surface[] where must=true ──
INTENT_VERDICT="$ATOM_DIR/intent/verdict.json"
[[ -f "$INTENT_VERDICT" ]] || emit_na "no intent/verdict.json at $INTENT_VERDICT — cannot resolve declared feature surface"

FS_MUST_COUNT=$(jq -r '[.declared.feature_surface[]? | select(.must==true)] | length' "$INTENT_VERDICT" 2>/dev/null || echo 0)
[[ "$FS_MUST_COUNT" =~ ^[0-9]+$ ]] || FS_MUST_COUNT=0
if [[ "$FS_MUST_COUNT" -eq 0 ]]; then
  emit_na "intent verdict has no declared.feature_surface[] must=true items — nothing to verify wiring for (LAW-F6: no vacuous PASS)"
fi

# ── LAW-F6 surface guard — no source at all ⇒ Stage 4 not reached ─────
# Mirror of capability-wiring-check.sh HAS_SURFACE: a repo with zero source
# files has not produced a wiring surface; emit N/A rather than FAIL.
if ! find "$PROJECT_ROOT" -type f \
     \( -name '*.go' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
        -o -name '*.mjs' -o -name '*.py' -o -name '*.rs' -o -name '*.java' -o -name '*.rb' \
        -o -name '*.kt' -o -name '*.swift' -o -name '*.cs' -o -name '*.php' \) \
     -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' \
     2>/dev/null | head -1 | grep -q .; then
  emit_na "no source files at $PROJECT_ROOT — build has not produced a feature-wiring surface yet (Stage 4 not reached)"
fi

# ── Read wiring map ───────────────────────────────────────────────────
CONFIG_JSON='{}'
[[ -f "$CONFIG" ]] && CONFIG_JSON=$(cat "$CONFIG")

log "must_features=$FS_MUST_COUNT root=$PROJECT_ROOT"

WIRED=()
UNWIRED=()

# wiring_entry_for <feature_name> → echoes the feature_wiring entry (compact
# JSON) whose KEY matches feature_name case-insensitively; empty if none.
wiring_entry_for() {
  local name_lc
  name_lc=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  jq -c --arg n "$name_lc" '
    (.feature_wiring // {})
    | to_entries
    | map(select((.key | ascii_downcase) == $n))
    | (.[0].value // empty)
  ' <<<"$CONFIG_JSON" 2>/dev/null || true
}

# check_feature_wiring <feature_name>
check_feature_wiring() {
  local feat="$1" entry
  entry=$(wiring_entry_for "$feat")
  if [[ -z "$entry" || "$entry" == "null" ]]; then
    UNWIRED+=("$feat (no feature_wiring entry — feature named in spec but never declared where wired)")
    return
  fi

  local categories_present=0
  local missing=()

  # routes — every route string must appear in SOURCE.
  local r
  while IFS= read -r r; do
    [[ -z "$r" ]] && continue
    categories_present=1
    if ! wiring_symbol_present "$PROJECT_ROOT" "$r"; then
      missing+=("route:$r")
    fi
  done < <(jq -r '.routes[]?' <<<"$entry" 2>/dev/null)

  # handlers — every handler symbol must appear in SOURCE.
  local h
  while IFS= read -r h; do
    [[ -z "$h" ]] && continue
    categories_present=1
    if ! wiring_symbol_present "$PROJECT_ROOT" "$h"; then
      missing+=("handler:$h")
    fi
  done < <(jq -r '.handlers[]?' <<<"$entry" 2>/dev/null)

  # test_refs — ≥1 of the declared test refs must appear in SOURCE.
  local test_ref_count test_hit=0 tr_present=0 t
  test_ref_count=$(jq -r '[.test_refs[]?] | length' <<<"$entry" 2>/dev/null || echo 0)
  [[ "$test_ref_count" =~ ^[0-9]+$ ]] || test_ref_count=0
  if [[ "$test_ref_count" -gt 0 ]]; then
    tr_present=1
    categories_present=1
    while IFS= read -r t; do
      [[ -z "$t" ]] && continue
      if wiring_symbol_present "$PROJECT_ROOT" "$t"; then
        test_hit=1; break
      fi
    done < <(jq -r '.test_refs[]?' <<<"$entry" 2>/dev/null)
    [[ "$test_hit" -eq 0 ]] && missing+=("test_ref:none of $test_ref_count declared test_refs found in source")
  fi

  # ≥1 category must be present AND satisfied; an empty entry is unwired.
  if [[ "$categories_present" -eq 0 ]]; then
    UNWIRED+=("$feat (feature_wiring entry present but empty — no routes, handlers, or test_refs declared)")
    return
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    local joined; joined=$(printf '%s, ' "${missing[@]}"); joined="${joined%, }"
    UNWIRED+=("$feat (missing in source: $joined)")
  else
    WIRED+=("$feat")
  fi
}

for i in $(seq 0 $((FS_MUST_COUNT - 1))); do
  FEAT=$(jq -r --argjson i "$i" '[.declared.feature_surface[] | select(.must==true)][$i].name' "$INTENT_VERDICT")
  [[ -z "$FEAT" || "$FEAT" == "null" ]] && continue
  check_feature_wiring "$FEAT"
done

WIRED_JSON=$(printf '%s\n' "${WIRED[@]:-}" | jq -R . | jq -s 'map(select(length>0))')
UNWIRED_JSON=$(printf '%s\n' "${UNWIRED[@]:-}" | jq -R . | jq -s 'map(select(length>0))')

if [[ ${#UNWIRED[@]} -gt 0 ]]; then
  log "FAIL: unwired=${#UNWIRED[@]} wired=${#WIRED[@]}"
  emit_fail "$UNWIRED_JSON" "$WIRED_JSON"
fi

log "PASS: wired=${#WIRED[@]}"
emit_pass "$WIRED_JSON"
