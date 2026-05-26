#!/usr/bin/env bash
# _common.sh — shared helpers for /build-anything mechanical gate scripts.
# Source this file: `source "$(dirname "$0")/_common.sh"`
# Provides: detect_stack, emit_json, require_cmd, atom_dir_from_args, log_step.

set -euo pipefail

# ── stack detection ────────────────────────────────────────────────
# Echoes one of: node | python | go | rust | unknown
# Priority: .build-anything.json#stack.lang > marker files in root > marker files one level down.
detect_stack() {
  local root="${1:-.}"
  # 1. Config override
  local cfg_lang=""
  if [[ -f "$root/.build-anything.json" ]] && command -v jq >/dev/null 2>&1; then
    cfg_lang=$(jq -r '.stack.lang // empty' "$root/.build-anything.json" 2>/dev/null || true)
  fi
  if [[ -n "$cfg_lang" && "$cfg_lang" != "null" ]]; then echo "$cfg_lang"; return; fi
  # 2. Marker files at root, then one subdir down (for monorepo-style toy layouts)
  for d in "$root" "$root"/*/; do
    [[ -e "$d/package.json" ]] && { echo "node"; return; }
    [[ -e "$d/pyproject.toml" || -e "$d/setup.py" || -e "$d/requirements.txt" ]] && { echo "python"; return; }
    [[ -e "$d/go.mod" ]] && { echo "go"; return; }
    [[ -e "$d/Cargo.toml" ]] && { echo "rust"; return; }
  done
  echo "unknown"
}

# ── JSON output ────────────────────────────────────────────────────
# emit_json <gate-id> <score> <threshold> <passed:true|false> <out-file> [extra-json] [confidence] [ambiguities-json-array]
# LAW-CL-95 — confidence default 100 for mechanical gates (numeric proof in hand).
# Callers SHOULD override when the score is heuristic / partial-evidence (e.g. lint-style ratio).
emit_json() {
  local gate="$1" score="$2" thresh="$3" passed="$4" out="$5"
  local extra="${6:-}"
  local confidence="${7:-100}"
  local ambiguities="${8:-[]}"
  [[ -z "$extra" ]] && extra='{}'
  mkdir -p "$(dirname "$out")"
  cat > "$out" <<JSON
{
  "gate": "$gate",
  "score": $score,
  "threshold": $thresh,
  "passed": $passed,
  "delta": $(awk -v s="$score" -v t="$thresh" 'BEGIN{printf "%.4f", s-t}'),
  "confidence": $confidence,
  "ambiguities": $ambiguities,
  "extra": $extra,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  echo "$score"  # stdout single-number per LAW-11 contract
}

# ── command availability ───────────────────────────────────────────
require_cmd() {
  local cmd="$1" hint="${2:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "FATAL: required tool '$cmd' not found in PATH. ${hint}" >&2
    exit 127
  fi
}

# ── atom dir parsing ───────────────────────────────────────────────
# Usage: atom_dir_from_args "$@" ; echo "$ATOM_DIR"
atom_dir_from_args() {
  ATOM_DIR=""
  PROJECT_ROOT=""
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
}

# ── changed files (atom scope) ─────────────────────────────────────
# Echoes one path per line; relative to PROJECT_ROOT.
# Resolution order: scope.paths in config > git diff > scope.bootstrap_glob > empty.
# Empty result MUST cause caller to emit N/A_PENDING_REVIEWER (LAW-F6), never vacuous PASS.
changed_files() {
  # 1. Explicit allowlist in config (works in any mode — bootstrap or atom-on-existing).
  local cfg="$PROJECT_ROOT/.build-anything.json"
  if [[ -f "$cfg" ]] && command -v jq >/dev/null 2>&1; then
    local paths
    paths=$(jq -r '.scope.paths[]? // empty' "$cfg" 2>/dev/null || true)
    if [[ -n "$paths" ]]; then echo "$paths"; return; fi
  fi
  # 2. Git diff vs base branch (atom-on-existing-project case).
  local base; base=$(jq -r '.scope.base_ref // "HEAD"' "$cfg" 2>/dev/null || echo "HEAD")
  local diff_out=""
  if ( cd "$PROJECT_ROOT" && git rev-parse --git-dir >/dev/null 2>&1 ); then
    diff_out=$( cd "$PROJECT_ROOT" && git diff --name-only --diff-filter=ACMR "$base" 2>/dev/null || true )
  fi
  if [[ -n "$diff_out" ]]; then echo "$diff_out"; return; fi
  # 3. Bootstrap mode — scope.bootstrap_glob lists dirs to walk for new-project full-surface scan.
  if [[ -f "$cfg" ]] && command -v jq >/dev/null 2>&1; then
    local globs
    globs=$(jq -r '.scope.bootstrap_glob[]? // empty' "$cfg" 2>/dev/null || true)
    if [[ -n "$globs" ]]; then
      while IFS= read -r g; do
        [[ -z "$g" ]] && continue
        ( cd "$PROJECT_ROOT" && find $g -type f 2>/dev/null ) || true
      done <<< "$globs"
      return
    fi
  fi
  # 4. Nothing — caller must emit N/A_PENDING_REVIEWER.
  return 0
}

# ── logging ────────────────────────────────────────────────────────
log_step()  { echo "[$(date -u +%H:%M:%S)] [$1] $2" >&2; }
log_fatal() { echo "FATAL: $*" >&2; exit 1; }

# ── portable readarray (bash 3.2 compat — macOS default has no mapfile) ──────
# Usage: read_lines VAR_NAME < <(cmd)
read_lines() {
  local __var="$1"; eval "$__var=()"
  local __line
  while IFS= read -r __line; do
    eval "$__var+=(\"\$__line\")"
  done
}

# F6 fix — empty/vacuous config must NOT claim PASS. N/A is a verdict.
# emit_na_pending <gate-id> <out-file> <reason>
emit_na_pending() {
  local gate="$1" out="$2" reason="${3:-no scope}"
  # LAW-CL-95 — N/A means we lack evidence to render a verdict; confidence=0,
  # the reason becomes the (single) declared ambiguity that the reviewer must resolve.
  local reason_json
  reason_json=$(printf '%s' "$reason" | jq -Rs . 2>/dev/null || printf '"%s"' "$reason")
  mkdir -p "$(dirname "$out")"
  cat > "$out" <<JSON
{
  "gate": "$gate",
  "score": null,
  "threshold": null,
  "passed": null,
  "verdict": "N/A_PENDING_REVIEWER",
  "reason": "$reason",
  "confidence": 0,
  "ambiguities": [$reason_json],
  "review_required": true,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  echo "NA"
}

# v8.3 — silent gate drop guard. When a gate script crashes without writing its
# JSON output, the orchestrator MUST synthesize an ERROR verdict so the gate
# does not silently disappear from the manifest (which would let a crashed gate
# masquerade as a never-registered gate — same failure class as vacuous PASS).
# emit_error <gate-id> <out-file> <reason> [<exit-code>]
emit_error() {
  local gate="$1" out="$2" reason="${3:-script crashed without writing JSON}" code="${4:-1}"
  # LAW-CL-95 — ERROR is the "we tried to render a verdict but the script crashed"
  # state. Confidence is 0; the crash reason is the declared ambiguity.
  local reason_json
  reason_json=$(printf '%s' "$reason" | jq -Rs . 2>/dev/null || printf '"%s"' "$reason")
  mkdir -p "$(dirname "$out")"
  cat > "$out" <<JSON
{
  "gate": "$gate",
  "score": null,
  "threshold": null,
  "passed": false,
  "verdict": "ERROR",
  "reason": "$reason",
  "exit_code": $code,
  "confidence": 0,
  "ambiguities": [$reason_json],
  "review_required": true,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  echo "ERROR"
}

# ── threshold reader ──────────────────────────────────────────────
# Reads dot-path key from .build-anything.json, prints value or default.
threshold() {
  local key="$1" default="$2"
  local cfg="$PROJECT_ROOT/.build-anything.json"
  if [[ -f "$cfg" ]] && command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" --arg d "$default" \
      '. as $r | ($k | split(".")) as $p | reduce $p[] as $s ($r; .[$s] // null) // $d' \
      "$cfg" 2>/dev/null || echo "$default"
  else
    echo "$default"
  fi
}
