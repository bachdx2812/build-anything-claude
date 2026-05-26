#!/usr/bin/env bash
# sql-injection-scan.sh — GATE-16 (property-substitute) SQL string-concat scanner.
# Primary: semgrep if installed. Fallback: regex grep for INSERT/SELECT/UPDATE with
# template interpolation patterns (`${...}` or "%s" % var or f"...{var}...").
# Single-number contract: hit_count (must be 0 to PASS).

set -euo pipefail
source "$(dirname "$0")/../mechanical/_common.sh"
atom_dir_from_args "$@"
log_step sqli "starting in $PROJECT_ROOT"

OUT="$ATOM_DIR/gate-security/sql-injection.json"
SCAN_DIR=$(jq -r '.scope.bootstrap_glob[0] // .stack.dir // "."' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo ".")
[[ "$SCAN_DIR" == "." || "$SCAN_DIR" == "null" ]] && SCAN_DIR="$PROJECT_ROOT" || SCAN_DIR="$PROJECT_ROOT/$SCAN_DIR"

# LAW-F6 — empty/missing source surface MUST be N/A_PENDING_REVIEWER.
# "Found 0 SQL-injection patterns in 0 source files" is vacuous PASS.
if [[ ! -d "$SCAN_DIR" ]]; then
  emit_na_pending "GATE-12-sqli-substitute" "$OUT" "scan dir $SCAN_DIR does not exist — cannot assert 'no SQL-injection' against empty surface"
  log_step sqli "N/A scan dir missing (LAW-F6 — no vacuous PASS)"
  exit 0
fi
SCAN_HITS=$(find "$SCAN_DIR" -type f \( -name '*.js' -o -name '*.ts' -o -name '*.py' -o -name '*.go' \) -not -path '*/node_modules/*' -not -path '*/.git/*' -not -name '.build-anything.json' 2>/dev/null | head -1)
if [[ -z "$SCAN_HITS" ]]; then
  emit_na_pending "GATE-12-sqli-substitute" "$OUT" "no source files (.js/.ts/.py/.go) in $SCAN_DIR — reviewer must populate scope or confirm no-server-code intent"
  log_step sqli "N/A zero source files (LAW-F6 — no vacuous PASS)"
  exit 0
fi

HITS=()
TOOL=""

if command -v semgrep >/dev/null 2>&1; then
  TOOL="semgrep $(semgrep --version 2>&1)"
  TMP=$(mktemp /tmp/semgrep-XXXXXX.json)
  trap 'rm -f "$TMP"' EXIT
  semgrep --config=p/sql-injection --json --output "$TMP" "$SCAN_DIR" >/dev/null 2>&1 || true
  if [[ -s "$TMP" ]]; then
    while IFS= read -r m; do HITS+=("$m"); done < <(jq -r '.results[]? | "\(.path):\(.start.line):\(.extra.lines // "")"' "$TMP" 2>/dev/null || true)
  fi
else
  TOOL="grep (semgrep not installed — install with: pip install semgrep)"
fi

# Always-on regex complement
PATTERNS=(
  '(INSERT|SELECT|UPDATE|DELETE) [^;]*\$\{'   # JS template literal in SQL
  '\.prepare\(["`].*\$\{'                      # better-sqlite3 prepare with interpolation
  '\.query\(["`].*\$\{'                        # pg/mysql .query with template literal
  'execute\(["][^"]*"%s'                        # python % string formatting
  'execute\(f["\x27]'                          # python f-string in execute
  '\.Raw\(["`].*\$\{'                          # gorm Raw with interpolation
)
for pat in "${PATTERNS[@]}"; do
  while IFS= read -r line; do
    [[ -n "$line" ]] && HITS+=("$line")
  done < <(grep -rEn --include='*.js' --include='*.ts' --include='*.py' --include='*.go' --exclude-dir=node_modules --exclude-dir=.git "$pat" "$SCAN_DIR" 2>/dev/null || true)
done

COUNT=${#HITS[@]}
PASSED="true"; [[ "$COUNT" -gt 0 ]] && PASSED="false"
if [[ "$COUNT" -gt 0 ]]; then
  HITS_JSON=$(printf '%s\n' "${HITS[@]}" | jq -Rs 'split("\n") | map(select(length>0))')
else
  HITS_JSON='[]'
fi

mkdir -p "$(dirname "$OUT")"
# LAW-CL-95 — concrete regex scan on real files; confidence=100 once it runs.
jq -n \
  --arg gate "GATE-12-sqli-substitute" \
  --arg tool "$TOOL" \
  --arg ran "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson score "$COUNT" \
  --argjson passed "$PASSED" \
  --argjson matches "$HITS_JSON" \
  '{ gate: $gate, score: $score, threshold: 0, passed: $passed, verdict: (if $passed then "PASS" else "FAIL" end), evidence: { tool: $tool, matches: $matches }, confidence: 100, ambiguities: [], ran_at: $ran }' > "$OUT"

if [[ "$PASSED" == "true" ]]; then
  log_step sqli "PASS 0 hits"
  exit 0
else
  log_step sqli "FAIL $COUNT hit(s) — see $OUT"
  exit 1
fi
