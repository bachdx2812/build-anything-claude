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
HITS_JSON=$(printf '%s\n' "${HITS[@]}" | jq -Rs 'split("\n") | map(select(length>0))')

mkdir -p "$(dirname "$OUT")"
jq -n \
  --arg gate "GATE-16-property-substitute" \
  --arg tool "$TOOL" \
  --arg ran "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson score "$COUNT" \
  --argjson passed "$PASSED" \
  --argjson matches "$HITS_JSON" \
  '{ gate: $gate, score: $score, threshold: 0, passed: $passed, verdict: (if $passed then "PASS" else "FAIL" end), evidence: { tool: $tool, matches: $matches }, ran_at: $ran }' > "$OUT"

if [[ "$PASSED" == "true" ]]; then
  log_step sqli "PASS 0 hits"
  exit 0
else
  log_step sqli "FAIL $COUNT hit(s) — see $OUT"
  exit 1
fi
