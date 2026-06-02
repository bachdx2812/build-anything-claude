#!/usr/bin/env bash
# stub-detection.sh — Stage 5 GATE-STUB (v8.8)
#
# Catches the audit's most damning class: a function that CLAIMS to implement a
# must-have feature but whose body is a stub or a lie.
#   §8   GenerateLesson is fmt.Sprintf, not an AI call; AzureSpeechEvaluate is a
#        comment with Provider:"azure".
#   §15.3 lesson/repository.go sets IsAIGenerated:true even though the content was
#        string-formatted — "the data lies about its provenance."
#
# Two high-precision smells (both hard FAIL inside scanned targets):
#   SMELL-NOTIMPL    — a body that announces it is not real: panic("not
#                      implemented"), errors.New("...not configured"),
#                      NotImplementedError, throw new Error("not implemented"),
#                      "TODO: implement".
#   SMELL-PROVENANCE — a truth-claim about AI generation / provider is set
#                      (is_ai_generated=true, provider="openai|azure|...") while
#                      the file makes NO outbound call (no http/SDK client call).
#                      i.e. the result claims a provenance it never earned.
#
# Scan targets: `.build-anything.json#stub_scan.targets[]` (the must-have feature
# implementation files; GATE-PFC-WIRE will auto-populate these). Falls back to
# changed_files(). Empty → N/A_PENDING_REVIEWER (LAW-F6 — never silent PASS).
# Reviewer waiver: `stub_scan.waived[]` substring match on "<file>" or "<file>:smell".
# LAW-CL-95: confidence + ambiguities[].

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_common.sh"

ATOM_DIR=""; PROJECT_ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --atom-dir)     ATOM_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done
: "${ATOM_DIR:?--atom-dir required}"
: "${PROJECT_ROOT:=$(pwd)}"
export ATOM_DIR PROJECT_ROOT
CONFIG="$PROJECT_ROOT/.build-anything.json"
OUT="$ATOM_DIR/gate-mechanical/stub-detection.json"
mkdir -p "$(dirname "$OUT")"

log() { echo "[$(date -u +%H:%M:%S)] [stub] $*" >&2; }

emit_na() {
  local reason="$1" rj; rj=$(printf '%s' "$reason" | jq -Rs .)
  cat > "$OUT" <<JSON
{ "gate": "GATE-STUB", "passed": null, "verdict": "N/A_PENDING_REVIEWER",
  "reason": $rj, "confidence": 0, "ambiguities": [$rj], "review_required": true,
  "schema_version": "ubs-v8.8-stub", "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)" }
JSON
  exit 0
}
emit_fail() {
  local findings="$1"
  cat > "$OUT" <<JSON
{ "gate": "GATE-STUB", "passed": false, "verdict": "FAIL",
  "reason": "stubbed or provenance-lying code in a claimed must-have feature file",
  "findings": $findings, "confidence": 100, "ambiguities": [],
  "schema_version": "ubs-v8.8-stub", "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)" }
JSON
  exit 1
}
emit_pass() {
  local scanned="$1"
  cat > "$OUT" <<JSON
{ "gate": "GATE-STUB", "passed": true, "verdict": "PASS",
  "files_scanned": $scanned, "confidence": 100, "ambiguities": [],
  "schema_version": "ubs-v8.8-stub", "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)" }
JSON
  exit 0
}

# ── Smell patterns ────────────────────────────────────────────────────
NOTIMPL_RE='panic\([^)]*(not implemented|unimplemented)|errors\.New\([^)]*(not implemented|not configured|unimplemented)|fmt\.Errorf\([^)]*(not implemented|not configured)|NotImplementedError|throw new [A-Za-z]*Error\([^)]*not implemented|TODO:? *implement|FIXME:? *implement'
# A truth-claim about provenance / provider.
CLAIM_RE='(is_ai_generated|isaigenerated)[[:space:]]*[:=][[:space:]]*true|provider[[:space:]]*[:=][[:space:]]*"?(openai|anthropic|claude|azure|gpt-|whisper|gemini|bedrock)'
# Evidence of an actual outbound/SDK call (NOT just a vendor name).
OUTBOUND_RE='\bhttp\.|fetch\(|axios|requests\.(get|post|put)|httpx|urllib|\.post\(|\.get\(|client\.[A-Za-z]+\(|createchatcompletion|chat\.completions|messages\.create|generate_content|invokemodel|\.do\(|RoundTrip'

is_source() { case "$1" in *.go|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.py|*.rs|*.java|*.rb|*.kt|*.swift|*.cs|*.php) return 0;; *) return 1;; esac; }

is_waived() {
  local key="$1" w
  while IFS= read -r w; do
    [[ -z "$w" ]] && continue
    [[ "$key" == *"$w"* ]] && return 0
  done < <(jq -r '.stub_scan.waived[]?' "$CONFIG" 2>/dev/null)
  return 1
}

# ── Resolve scan targets ──────────────────────────────────────────────
TARGETS=""
[[ -f "$CONFIG" ]] && TARGETS=$(jq -r '.stub_scan.targets[]? // empty' "$CONFIG" 2>/dev/null || true)
[[ -z "$TARGETS" ]] && TARGETS=$(changed_files || true)
[[ -z "$TARGETS" ]] && emit_na "no stub_scan.targets[] and no changed files — nothing to scan (declare the must-have feature files in stub_scan.targets[])"

FINDINGS=()
SCANNED=0
while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  is_source "$rel" || continue
  abs="$PROJECT_ROOT/$rel"
  [[ -f "$abs" ]] || continue
  SCANNED=$((SCANNED+1))

  # SMELL-NOTIMPL — line-level
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    ln="${hit%%:*}"
    is_waived "$rel:notimpl" && continue
    FINDINGS+=("$rel:$ln NOTIMPL — body announces it is not implemented/configured")
  done < <(grep -nEi "$NOTIMPL_RE" "$abs" 2>/dev/null || true)

  # SMELL-PROVENANCE — file-level: claim present, outbound call absent
  if grep -qEi "$CLAIM_RE" "$abs" 2>/dev/null; then
    if ! grep -qEi "$OUTBOUND_RE" "$abs" 2>/dev/null; then
      is_waived "$rel:provenance" || \
        FINDINGS+=("$rel PROVENANCE-LIE — sets AI/provider truth-claim but file makes no outbound/SDK call")
    fi
  fi
done <<< "$TARGETS"

if [[ ${#FINDINGS[@]} -gt 0 ]]; then
  FJSON=$(printf '%s\n' "${FINDINGS[@]}" | jq -R . | jq -s 'map(select(length>0))')
  log "FAIL: ${#FINDINGS[@]} finding(s) across $SCANNED file(s)"
  emit_fail "$FJSON"
fi

log "PASS: $SCANNED file(s) scanned, no stub/provenance smells"
emit_pass "$SCANNED"
