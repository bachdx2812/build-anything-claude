#!/usr/bin/env bash
# audit.sh — GATE-UIUX runner. Static UI quality audit driven by ui-ux-pro-max
# design system + a regex rule pack. LAW-F6 compliant: never vacuous PASS.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../backend/_common.sh"

atom_dir_from_args "$@"
EVIDENCE_DIR_LOCAL="$ATOM_DIR/gate-ui-ux"
mkdir -p "$EVIDENCE_DIR_LOCAL"
OUT="$EVIDENCE_DIR_LOCAL/ui-audit.json"

# LAW-CL-95 — UI/UX audit verdicts carry {confidence, ambiguities}.
# Findings are deterministic file/style scans → confidence=100 once scan ran.
# N/A = no UI surface declared → confidence=0; reason is the ambiguity.
emit_ui_na() {
  local reason_json
  reason_json=$(printf '%s' "$1" | jq -Rs . 2>/dev/null || printf '"%s"' "$1")
  cat > "$OUT" <<JSON
{
  "gate": "GATE-UIUX",
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

emit_ui_fail() {
  local findings="$1" counts="$2"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-UIUX",
  "passed": false,
  "verdict": "FAIL",
  "evidence": {
    "findings": $findings,
    "counts_by_severity": $counts
  },
  "confidence": 100,
  "ambiguities": [],
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 1
}

emit_ui_pass() {
  local findings="$1" counts="$2" ds_path="$3" pages="$4"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-UIUX",
  "passed": true,
  "verdict": "PASS",
  "evidence": {
    "design_system_path": "$ds_path",
    "pages_audited": $pages,
    "findings": $findings,
    "counts_by_severity": $counts
  },
  "confidence": 100,
  "ambiguities": [],
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

# ── Gate trigger check ─────────────────────────────────────────────
UI_ENABLED=$(cfg "ui.enabled" "false")
PROJECT_TYPE=$(cfg "project_type" "backend")

# v8.6: native mobile UI is not DOM-audited. Native HIG / Material 3 persona
# is deferred to v8.7. Emit N/A so the gate doesn't fire CSS-based rules
# against SwiftUI / Compose / RN / Flutter source.
case "$PROJECT_TYPE" in
  mobile-*)
    emit_ui_na "project_type=$PROJECT_TYPE — native UI audit deferred to v8.7 (DOM rules don't apply)"
    ;;
  desktop-browser-*)
    emit_ui_na "project_type=$PROJECT_TYPE — DOM UI audit doesn't apply to a browser binary; UX is governed by GATE-25-E2E-BROWSER journeys + GATE-BROWSER-WPT conformance"
    ;;
esac

if [[ "$UI_ENABLED" != "true" && "$PROJECT_TYPE" != "frontend" && "$PROJECT_TYPE" != "mixed" ]]; then
  emit_ui_na "no UI surface declared (ui.enabled=false, project_type=$PROJECT_TYPE)"
fi

# ── Locate source root ─────────────────────────────────────────────
SRC_ROOT=$(cfg "ui.source_root" "$PROJECT_ROOT/frontend")
[[ "$SRC_ROOT" = /* ]] || SRC_ROOT="$PROJECT_ROOT/$SRC_ROOT"

if [[ ! -d "$SRC_ROOT" ]]; then
  emit_ui_fail '[{"severity":"CRITICAL","rule":"ui-source-missing","reason":"ui.enabled=true but source_root not found: '"$SRC_ROOT"'"}]' '{"CRITICAL":1,"HIGH":0,"MEDIUM":0,"LOW":0}'
fi

# ── Ensure ui-ux-pro-max present ───────────────────────────────────
UIUX_SKILL="$HOME/.claude/skills/ui-ux-pro-max"
if [[ ! -f "$UIUX_SKILL/scripts/search.py" ]]; then
  emit_ui_fail '[{"severity":"CRITICAL","rule":"dep-missing","reason":"ui-ux-pro-max not installed at '"$UIUX_SKILL"'"}]' '{"CRITICAL":1,"HIGH":0,"MEDIUM":0,"LOW":0}'
fi

# ── Generate design system ─────────────────────────────────────────
log_step ui-ux "generating design system via ui-ux-pro-max"
ATOM_NAME=$(basename "$ATOM_DIR")
SPEC_TXT=""
[[ -f "$ATOM_DIR/spec.md" ]] && SPEC_TXT=$(tr '\n' ' ' < "$ATOM_DIR/spec.md" | tr -s ' ' | cut -c1-200)
QUERY="${SPEC_TXT:-$ATOM_NAME}"

DS_DIR="$ATOM_DIR/design-system"
mkdir -p "$DS_DIR"
(cd "$DS_DIR" && \
  python3 "$UIUX_SKILL/scripts/search.py" "$QUERY" --design-system --persist -p "$ATOM_NAME" -f markdown \
  > "$EVIDENCE_DIR_LOCAL/design-system.log" 2>&1 || true)

DS_PATH="design-system/MASTER.md"
if [[ ! -f "$ATOM_DIR/$DS_PATH" && ! -f "$DS_DIR/MASTER.md" ]]; then
  log_step ui-ux "warn: design-system generation did not produce MASTER.md — auditing source anyway"
  DS_PATH="design-system/design-system.log"
fi

# ── Run regex audit pack ───────────────────────────────────────────
log_step ui-ux "auditing source under $SRC_ROOT"

FINDINGS_FILE="$EVIDENCE_DIR_LOCAL/.findings.jsonl"
: > "$FINDINGS_FILE"

# Helper: append a finding
finding() {
  local sev="$1" rule="$2" file="$3" line="$4" snippet="$5"
  # Escape quotes for JSON
  snippet=$(printf '%s' "$snippet" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"severity":"%s","rule":"%s","file":"%s","line":%s,"snippet":"%s"}\n' "$sev" "$rule" "$file" "$line" "$snippet" >> "$FINDINGS_FILE"
}

# Rule 1: no-emoji-icons (CRITICAL)
# Match high-plane unicode commonly used as emoji (rough but useful)
while IFS=: read -r f l rest; do
  finding "CRITICAL" "no-emoji-icons" "$f" "$l" "${rest:0:80}"
done < <(grep -rnE '[\xf0-\xf4][\x80-\xbf]{3}' "$SRC_ROOT" --include='*.tsx' --include='*.jsx' --include='*.vue' --include='*.svelte' --include='*.html' 2>/dev/null || true)

# Rule 2: color-semantic (HIGH) — raw hex in components (excluding token files)
while IFS=: read -r f l rest; do
  case "$f" in
    *tokens*|*theme*|*variables*|*colors*) continue ;;
  esac
  finding "HIGH" "color-semantic" "$f" "$l" "${rest:0:80}"
done < <(grep -rnE '#[0-9a-fA-F]{6}\b|rgb\(' "$SRC_ROOT" --include='*.tsx' --include='*.jsx' 2>/dev/null || true)

# Rule 3: viewport-meta presence — must exist in some index.html
VP_OK=0
for idx in $(find "$SRC_ROOT" "$PROJECT_ROOT" -maxdepth 4 -name 'index.html' 2>/dev/null | head -5); do
  if grep -q 'name="viewport"' "$idx" 2>/dev/null; then VP_OK=1; break; fi
done
if [[ $VP_OK -eq 0 ]]; then
  finding "HIGH" "viewport-meta" "(any)/index.html" 0 "missing <meta name=\"viewport\" ...>"
fi

# Rule 4: image-alt-text (HIGH) — <img without alt=
while IFS=: read -r f l rest; do
  # Skip if alt= appears on same or next line (heuristic)
  if ! echo "$rest" | grep -q 'alt='; then
    finding "HIGH" "image-alt-text" "$f" "$l" "${rest:0:80}"
  fi
done < <(grep -rnE '<img[[:space:]]+[^>]*src=' "$SRC_ROOT" --include='*.tsx' --include='*.jsx' --include='*.html' --include='*.vue' 2>/dev/null || true)

# Rule 5: inline-style-discipline (MEDIUM) — style={{ with 3+ commas (rough)
while IFS=: read -r f l rest; do
  if [[ $(echo "$rest" | grep -o ',' | wc -l) -ge 3 ]]; then
    finding "MEDIUM" "inline-style-discipline" "$f" "$l" "${rest:0:80}"
  fi
done < <(grep -rnE 'style=\{\{' "$SRC_ROOT" --include='*.tsx' --include='*.jsx' 2>/dev/null || true)

# Rule 6: aria-icon-only-button (HIGH) — heuristic: <button>...icon-only.*</button> without aria-label
while IFS=: read -r f l rest; do
  if ! echo "$rest" | grep -q 'aria-label='; then
    finding "HIGH" "aria-icon-only" "$f" "$l" "${rest:0:80}"
  fi
done < <(grep -rnE '<button[^>]*>[[:space:]]*<(svg|i|Icon)' "$SRC_ROOT" --include='*.tsx' --include='*.jsx' 2>/dev/null || true)

# ── Aggregate findings ─────────────────────────────────────────────
TOTAL_LINES=$(wc -l < "$FINDINGS_FILE" | tr -d ' ')
if [[ "$TOTAL_LINES" -eq 0 ]]; then
  FINDINGS_JSON='[]'
  COUNTS='{"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0}'
else
  FINDINGS_JSON=$(jq -s '.' "$FINDINGS_FILE" 2>/dev/null || echo "[]")
  COUNTS=$(jq -s '[.[]] | group_by(.severity) | map({(.[0].severity): length}) | add // {}' "$FINDINGS_FILE" 2>/dev/null || echo '{}')
  COUNTS=$(echo "$COUNTS" | jq '{CRITICAL: (.CRITICAL // 0), HIGH: (.HIGH // 0), MEDIUM: (.MEDIUM // 0), LOW: (.LOW // 0)}')
fi

MAX_CRIT=$(cfg "ui.thresholds.max_critical" "0")
MAX_HIGH=$(cfg "ui.thresholds.max_high" "3")

CRIT_COUNT=$(echo "$COUNTS" | jq -r '.CRITICAL')
HIGH_COUNT=$(echo "$COUNTS" | jq -r '.HIGH')

log_step ui-ux "findings: total=$TOTAL_LINES critical=$CRIT_COUNT high=$HIGH_COUNT (thresholds: max_crit=$MAX_CRIT max_high=$MAX_HIGH)"

PAGES_JSON=$(jq -c '[.ui.pages[]?.name // empty]' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo '[]')

if [[ "$CRIT_COUNT" -gt "$MAX_CRIT" || "$HIGH_COUNT" -gt "$MAX_HIGH" ]]; then
  emit_ui_fail "$FINDINGS_JSON" "$COUNTS"
fi

emit_ui_pass "$FINDINGS_JSON" "$COUNTS" "$DS_PATH" "$PAGES_JSON"
