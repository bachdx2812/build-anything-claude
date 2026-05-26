#!/usr/bin/env bash
# secret-scan.sh — LAW-04 secret scan.
# Primary tool: gitleaks with optional custom rules at $PROJECT_ROOT/.gitleaks.toml.
# Fallback: grep on a curated pattern list (still catches obvious leaks).
# Single-number contract: secret_match_count (must be 0 to PASS).

set -euo pipefail
source "$(dirname "$0")/../mechanical/_common.sh"
atom_dir_from_args "$@"
log_step secret-scan "starting in $PROJECT_ROOT"

OUT="$ATOM_DIR/gate-security/secret-scan.json"
SCAN_DIR=$(jq -r '.scope.bootstrap_glob[0] // .stack.dir // "."' "$PROJECT_ROOT/.build-anything.json" 2>/dev/null || echo ".")
[[ "$SCAN_DIR" == "." || "$SCAN_DIR" == "null" ]] && SCAN_DIR="$PROJECT_ROOT" || SCAN_DIR="$PROJECT_ROOT/$SCAN_DIR"

# LAW-F6 — if scan dir is missing OR has zero scannable files, emit
# N/A_PENDING_REVIEWER. "No files to scan" is NOT the same as "no secrets found".
if [[ ! -d "$SCAN_DIR" ]]; then
  emit_na_pending "LAW-04-secret-scan" "$OUT" "scan dir $SCAN_DIR does not exist — cannot assert 'no secrets' against empty surface"
  log_step secret-scan "N/A scan dir missing (LAW-F6 — no vacuous PASS)"
  exit 0
fi
SCANNABLE=$(find "$SCAN_DIR" -type f \( -name '*.js' -o -name '*.ts' -o -name '*.py' -o -name '*.go' -o -name '*.rs' -o -name '*.yml' -o -name '*.yaml' -o -name '*.env*' \) -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' -not -name '.build-anything.json' 2>/dev/null | head -1)
if [[ -z "$SCANNABLE" ]]; then
  emit_na_pending "LAW-04-secret-scan" "$OUT" "no scannable source/config files in $SCAN_DIR (excluding .build-anything.json) — reviewer must populate scope or confirm empty repo intent"
  log_step secret-scan "N/A zero scannable files (LAW-F6 — no vacuous PASS)"
  exit 0
fi

CUSTOM_CONFIG="$PROJECT_ROOT/.gitleaks.toml"
TMP_REPORT="$(mktemp /tmp/gitleaks-XXXXXX.json)"
trap 'rm -f "$TMP_REPORT"' EXIT

MATCHES=0
TOOL=""
MATCH_DETAIL="[]"

if command -v gitleaks >/dev/null 2>&1; then
  TOOL="gitleaks $(gitleaks version 2>&1 | head -1)"
  GL_ARGS=( detect --source "$SCAN_DIR" --no-git --report-format json --report-path "$TMP_REPORT" --exit-code 0 )
  [[ -f "$CUSTOM_CONFIG" ]] && GL_ARGS+=( --config "$CUSTOM_CONFIG" )
  gitleaks "${GL_ARGS[@]}" >/dev/null 2>&1 || true
  if [[ -s "$TMP_REPORT" ]]; then
    MATCHES=$(jq 'length' "$TMP_REPORT" 2>/dev/null || echo 0)
    MATCH_DETAIL=$(jq '[.[] | {file: .File, line: .StartLine, rule: .RuleID, match: .Match}]' "$TMP_REPORT" 2>/dev/null || echo "[]")
  fi
else
  TOOL="grep (gitleaks not installed)"
fi

# Fallback grep — runs ALWAYS to catch low-entropy test keys gitleaks default rules miss.
# Stops being a substitute and becomes a *complement*. Either tool flagging triggers FAIL.
GREP_PATTERNS=(
  'sk-proj-[A-Za-z0-9_-]{20,}'
  'sk-[A-Za-z0-9]{32,}'
  'ghp_[A-Za-z0-9]{20,}'
  'AKIA[0-9A-Z]{16}'
  'AIza[0-9A-Za-z_-]{30,}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
  'BEGIN (RSA|EC|OPENSSH|DSA) PRIVATE KEY'
)
GREP_HITS=()
for pat in "${GREP_PATTERNS[@]}"; do
  while IFS= read -r line; do
    [[ -n "$line" ]] && GREP_HITS+=("$line")
  done < <(grep -rEn --include='*.js' --include='*.ts' --include='*.py' --include='*.go' --include='*.rs' --include='*.json' --include='*.yml' --include='*.yaml' --include='*.env*' --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=.coverage-tmp "$pat" "$SCAN_DIR" 2>/dev/null || true)
done
GREP_COUNT=${#GREP_HITS[@]}
if [[ "$GREP_COUNT" -gt 0 ]]; then
  GREP_JSON=$(printf '%s\n' "${GREP_HITS[@]}" | jq -Rs 'split("\n") | map(select(length>0))')
  MATCH_DETAIL=$(jq --argjson gh "$GREP_JSON" '. + ($gh | map({tool:"grep-complement", raw:.}))' <<< "$MATCH_DETAIL")
  MATCHES=$(( MATCHES + GREP_COUNT ))
fi

PASSED="true"; [[ "$MATCHES" -gt 0 ]] && PASSED="false"
mkdir -p "$(dirname "$OUT")"
# LAW-CL-95 — secret-scan is a concrete regex/tool scan over real files; confidence=100
# once the scan completes. No ambiguities on the PASS path; FAIL surfaces matched lines.
jq -n \
  --arg gate "LAW-04-secret-scan" \
  --arg tool "$TOOL" \
  --arg ran "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson score "$MATCHES" \
  --argjson passed "$PASSED" \
  --argjson detail "$MATCH_DETAIL" \
  '{ gate: $gate, score: $score, threshold: 0, passed: $passed, verdict: (if $passed then "PASS" else "FAIL" end), evidence: { tool: $tool, matches: $detail }, confidence: 100, ambiguities: [], ran_at: $ran }' > "$OUT"

if [[ "$PASSED" == "true" ]]; then
  log_step secret-scan "PASS 0 matches"
  exit 0
else
  log_step secret-scan "FAIL $MATCHES match(es) — see $OUT"
  exit 1
fi
