#!/usr/bin/env bash
# allowlist-substance-check.sh — Stage 5 GATE-SUBSTANCE (v8.8)
#
# Catches the audit's §10 class: directories counted as "delivered" that are in
# fact empty shells or hold only 0-byte source stubs.
#   §10  internal/ai, internal/notification, internal/social were declared in
#        scope yet existed only as empty dirs — counted as built, contained
#        nothing. The allowlist said "delivered"; the filesystem said otherwise.
#
# This gate confronts each DECLARED directory with the filesystem and FAILs when
# the declaration has no substance behind it:
#   FINDING-ABSENT    — a declared dir does not exist on disk.
#   FINDING-EMPTY     — a declared dir exists but contains ZERO non-empty source
#                       files (recursive; node_modules/.git/vendor excluded).
#                       i.e. "counted as delivered but contains nothing".
#   FINDING-ZEROBYTE  — a 0-byte source file lives inside a declared dir (a stub
#                       file that pads the dir but carries no implementation).
#
# Declared dirs: `.build-anything.json#substance.dirs[]` if present; else the
# `#scope.paths[]` entries that resolve to directories. Empty/none →
# N/A_PENDING_REVIEWER (LAW-F6 — never silent PASS).
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
OUT="$ATOM_DIR/gate-mechanical/substance.json"
mkdir -p "$(dirname "$OUT")"

log() { echo "[$(date -u +%H:%M:%S)] [substance] $*" >&2; }

emit_na() {
  local reason="$1" rj; rj=$(printf '%s' "$reason" | jq -Rs .)
  cat > "$OUT" <<JSON
{ "gate": "GATE-SUBSTANCE", "passed": null, "verdict": "N/A_PENDING_REVIEWER",
  "reason": $rj, "confidence": 0, "ambiguities": [$rj], "review_required": true,
  "schema_version": "ubs-v8.8-substance", "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)" }
JSON
  exit 0
}
emit_fail() {
  local findings="$1"
  cat > "$OUT" <<JSON
{ "gate": "GATE-SUBSTANCE", "passed": false, "verdict": "FAIL",
  "reason": "declared dir is empty, absent, or holds only 0-byte source stubs (counted as delivered but contains nothing)",
  "findings": $findings, "confidence": 100, "ambiguities": [],
  "schema_version": "ubs-v8.8-substance", "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)" }
JSON
  exit 1
}
emit_pass() {
  local checked="$1"
  cat > "$OUT" <<JSON
{ "gate": "GATE-SUBSTANCE", "passed": true, "verdict": "PASS",
  "dirs_checked": $checked, "confidence": 100, "ambiguities": [],
  "schema_version": "ubs-v8.8-substance", "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)" }
JSON
  exit 0
}

is_source() { case "$1" in *.go|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.py|*.rs|*.java|*.rb|*.kt|*.swift|*.cs|*.php) return 0;; *) return 1;; esac; }

# ── Resolve declared dirs ─────────────────────────────────────────────
# 1. Explicit substance.dirs[] — the canonical declaration for this gate.
# 2. Else scope.paths[] entries that resolve to directories on disk.
DIRS=""
if [[ -f "$CONFIG" ]]; then
  DIRS=$(jq -r '.substance.dirs[]? // empty' "$CONFIG" 2>/dev/null || true)
  if [[ -z "$DIRS" ]]; then
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      [[ -d "$PROJECT_ROOT/$p" ]] && DIRS+="$p"$'\n'
    done < <(jq -r '.scope.paths[]? // empty' "$CONFIG" 2>/dev/null || true)
  fi
fi
[[ -z "${DIRS//[$'\n']/}" ]] && emit_na "no substance.dirs[] and no scope.paths[] directories — nothing to verify (declare delivered dirs in substance.dirs[])"

FINDINGS=()
CHECKED=0
while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  abs="$PROJECT_ROOT/$rel"
  CHECKED=$((CHECKED+1))

  # FINDING-ABSENT — declared but not on disk.
  if [[ ! -d "$abs" ]]; then
    FINDINGS+=("$rel — declared dir absent")
    continue
  fi

  # Walk the dir once (recursive), excluding vendored/VCS noise.
  NONEMPTY_SRC=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    is_source "$(basename "$f")" || continue
    NONEMPTY_SRC=$((NONEMPTY_SRC+1))
  done < <(find "$abs" \( -name node_modules -o -name .git -o -name vendor \) -prune -o \
             -type f -size +0c -print 2>/dev/null || true)

  # FINDING-EMPTY — no non-empty source file anywhere under the dir.
  if [[ "$NONEMPTY_SRC" -eq 0 ]]; then
    FINDINGS+=("$rel — empty dir — no non-empty source file (counted as delivered but contains nothing)")
  fi

  # FINDING-ZEROBYTE — a 0-byte source file padding the dir.
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    is_source "$(basename "$f")" || continue
    rf="${f#"$PROJECT_ROOT"/}"
    FINDINGS+=("$rf — 0-byte source stub")
  done < <(find "$abs" \( -name node_modules -o -name .git -o -name vendor \) -prune -o \
             -type f -size 0 -print 2>/dev/null || true)
done <<< "$DIRS"

if [[ ${#FINDINGS[@]} -gt 0 ]]; then
  FJSON=$(printf '%s\n' "${FINDINGS[@]}" | jq -R . | jq -s 'map(select(length>0))')
  log "FAIL: ${#FINDINGS[@]} finding(s) across $CHECKED declared dir(s)"
  emit_fail "$FJSON"
fi

log "PASS: $CHECKED declared dir(s) checked, all carry non-empty source substance"
emit_pass "$CHECKED"
