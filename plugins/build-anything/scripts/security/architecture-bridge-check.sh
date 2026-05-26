#!/usr/bin/env bash
# architecture-bridge-check.sh — arch-bridge gate.
# Detects forbidden cross-layer dependencies (eg frontend importing backend/DB).
# Primary: dependency-cruiser if installed. Fallback: grep for known anti-patterns.
# Single-number contract: violation_count (must be 0 to PASS).

set -euo pipefail
source "$(dirname "$0")/../mechanical/_common.sh"
atom_dir_from_args "$@"
log_step arch-bridge "starting in $PROJECT_ROOT"

OUT="$ATOM_DIR/gate-security/architecture.json"
FE_DIR=$(jq -r '.frontend.dir // "frontend"' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo "frontend")
BE_DIR=$(jq -r '.backend.dir // .stack.dir // "backend"' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo "backend")
FE_ABS="$PROJECT_ROOT/$FE_DIR"
BE_ABS="$PROJECT_ROOT/$BE_DIR"

# LAW-F6 — if neither frontend nor backend dirs exist, there is no cross-layer
# surface to audit. Emit N/A_PENDING_REVIEWER, never vacuous PASS.
if [[ ! -d "$FE_ABS" && ! -d "$BE_ABS" ]]; then
  emit_na_pending "architecture-bridge-substitute" "$OUT" "neither frontend ($FE_DIR) nor backend ($BE_DIR) dir exists at $PROJECT_ROOT — no cross-layer surface to audit"
  log_step arch-bridge "N/A no FE/BE dirs (LAW-F6 — no vacuous PASS)"
  exit 0
fi
# LAW-F6 — if frontend dir missing, the "FE imports BE" check has no surface.
# (BE-only repos are valid; just emit N/A so reviewer can confirm.)
if [[ ! -d "$FE_ABS" ]]; then
  emit_na_pending "architecture-bridge-substitute" "$OUT" "frontend dir $FE_DIR does not exist at $PROJECT_ROOT — cross-layer check is FE→BE only; reviewer to confirm BE-only nature"
  log_step arch-bridge "N/A no FE dir (LAW-F6 — no vacuous PASS)"
  exit 0
fi

HITS=()
TOOL=""

if command -v depcruise >/dev/null 2>&1 && [[ -d "$FE_ABS" ]]; then
  TOOL="dependency-cruiser $(depcruise --version 2>&1)"
  TMP=$(mktemp /tmp/depcruise-XXXXXX.json)
  trap 'rm -f "$TMP"' EXIT
  depcruise --output-type json --include-only "^$FE_DIR" "$FE_ABS" > "$TMP" 2>/dev/null || true
  if [[ -s "$TMP" ]]; then
    while IFS= read -r m; do HITS+=("$m"); done < <(jq -r --arg be "$BE_DIR" '.modules[]? | .dependencies[]? | select(.resolved | startswith($be)) | "\(.module) → \(.resolved)"' "$TMP" 2>/dev/null || true)
  fi
else
  TOOL="grep (dependency-cruiser not installed — install with: npm i -g dependency-cruiser)"
fi

# Regex complement — catches imports/requires of backend modules from frontend dir
if [[ -d "$FE_ABS" ]]; then
  PATTERNS=(
    "require\(['\"].*${BE_DIR}/"
    "from ['\"].*${BE_DIR}/"
    "import .* from ['\"].*${BE_DIR}/"
    "require\(['\"].*\\.\\./.*db['\"]\\)"   # ../db references in FE
    "const Database = "                       # explicit Database refs in FE files
  )
  for pat in "${PATTERNS[@]}"; do
    while IFS= read -r line; do
      [[ -n "$line" ]] && HITS+=("$line")
    done < <(grep -rEn --include='*.js' --include='*.ts' --include='*.tsx' --include='*.jsx' --exclude-dir=node_modules --exclude-dir=.git "$pat" "$FE_ABS" 2>/dev/null || true)
  done
fi

COUNT=${#HITS[@]}
PASSED="true"; [[ "$COUNT" -gt 0 ]] && PASSED="false"
if [[ "$COUNT" -gt 0 ]]; then
  HITS_JSON=$(printf '%s\n' "${HITS[@]}" | jq -Rs 'split("\n") | map(select(length>0))')
else
  HITS_JSON='[]'
fi

mkdir -p "$(dirname "$OUT")"
# LAW-CL-95 — concrete grep/depcruise scan over real files; confidence=100 on run.
jq -n \
  --arg gate "architecture-bridge-substitute" \
  --arg tool "$TOOL" \
  --arg ran "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson score "$COUNT" \
  --argjson passed "$PASSED" \
  --argjson matches "$HITS_JSON" \
  '{ gate: $gate, score: $score, threshold: 0, passed: $passed, verdict: (if $passed then "PASS" else "FAIL" end), evidence: { tool: $tool, matches: $matches }, confidence: 100, ambiguities: [], ran_at: $ran }' > "$OUT"

if [[ "$PASSED" == "true" ]]; then
  log_step arch-bridge "PASS 0 violations"
  exit 0
else
  log_step arch-bridge "FAIL $COUNT violation(s) — see $OUT"
  exit 1
fi
