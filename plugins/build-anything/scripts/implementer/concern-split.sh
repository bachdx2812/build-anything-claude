#!/usr/bin/env bash
# concern-split.sh — Stage 4 BMAD-method dispatcher pre-flight.
#
# Reads the atom's allowlist (from .build-anything.json or atom brief) and
# partitions every file/glob into one of three concern groups:
#
#   backend   — server / API / DB code
#   frontend  — UI components / pages
#   tests     — cross-concern E2E / integration tests
#
# Writes {atom_dir}/implementer/concern-split.json with:
#   - mode: "multi-persona" if ≥ 2 dispatchable concerns, else "single-persona"
#   - concerns.{backend,frontend,tests}.{globs, files, dispatch}
#   - uncategorised[]: files that didn't match any known concern pattern
#
# Honours LAW-02 (allowlist) and LAW-F6 (no vacuous PASS): an uncategorised
# file is NEVER silently dropped — it forces the reviewer to categorise or HALT.
#
# Exit: 0 OK, 1 uncategorised allowlist (HALT), 2 preflight error.

set -uo pipefail

ATOM_DIR=""
PROJECT_ROOT=""
FORCE_SINGLE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --atom-dir)     ATOM_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --force-single) FORCE_SINGLE=1; shift ;;
    *) shift ;;
  esac
done
: "${ATOM_DIR:?--atom-dir required}"
: "${PROJECT_ROOT:?--project-root required}"

OUT_DIR="$ATOM_DIR/implementer"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/concern-split.json"

log() { echo "[$(date -u +%H:%M:%S)] [concern-split] $*" >&2; }

# ── Gather allowlist ─────────────────────────────────────────────
# Priority: atom brief allowlist > .build-anything.json scope.paths > scope.bootstrap_glob
ALLOWLIST=()

# Try atom brief first
BRIEF="$ATOM_DIR/spec.md"
if [[ -f "$BRIEF" ]]; then
  # Lines like `- allowlist: backend/**` or `- backend/**` under an `## Allowlist` header
  while IFS= read -r line; do
    [[ -n "$line" ]] && ALLOWLIST+=("$line")
  done < <(awk '
    BEGIN { in_sec=0 }
    /^#+ *[Aa]llowlist/ { in_sec=1; next }
    in_sec {
      if ($0 ~ /^#+ /) { in_sec=0; next }
      # strip leading "- " or "* "
      sub(/^[[:space:]]*[-*][[:space:]]*/, "", $0)
      if ($0 ~ /[^[:space:]]/) print $0
    }
  ' "$BRIEF")
fi

# Fallback: scope.paths
CFG="$PROJECT_ROOT/.build-anything.json"
if [[ ${#ALLOWLIST[@]} -eq 0 && -f "$CFG" ]]; then
  while IFS= read -r p; do
    [[ -n "$p" ]] && ALLOWLIST+=("$p")
  done < <(jq -r '.scope.paths[]? // empty' "$CFG" 2>/dev/null)
fi

# Last-resort: bootstrap_glob
if [[ ${#ALLOWLIST[@]} -eq 0 && -f "$CFG" ]]; then
  while IFS= read -r g; do
    [[ -n "$g" ]] && ALLOWLIST+=("$g/**")
  done < <(jq -r '.scope.bootstrap_glob[]? // empty' "$CFG" 2>/dev/null)
fi

if [[ ${#ALLOWLIST[@]} -eq 0 ]]; then
  log "FATAL: empty allowlist — cannot split concerns"
  cat > "$OUT" <<JSON
{
  "mode": "ERROR",
  "reason": "empty-allowlist",
  "concerns": { "backend": {}, "frontend": {}, "tests": {} },
  "uncategorised": []
}
JSON
  exit 2
fi

log "allowlist size: ${#ALLOWLIST[@]}"

# ── Concern patterns (extend here as new stacks land) ────────────
is_tests() {
  local p="$1"
  case "$p" in
    e2e/*|*/e2e/*|tests/e2e/*|playwright/*|cypress/*|*spec/e2e/*) return 0 ;;
    tests/integration/*|integration-tests/*) return 0 ;;
    *.e2e.*|*.spec.e2e.*) return 0 ;;
  esac
  return 1
}
is_backend() {
  local p="$1"
  case "$p" in
    backend/*|api/*|server/*|services/*|db/*|migrations/*|prisma/*) return 0 ;;
    cmd/*|internal/*|pkg/*) return 0 ;;
    app/api/*|app/server/*) return 0 ;;
    *.go|*.py|*.rs) return 0 ;;
  esac
  return 1
}
is_frontend() {
  local p="$1"
  case "$p" in
    frontend/*|web/*|client/*|ui/*|app/*) return 0 ;;
    src/components/*|src/pages/*|src/app/*|src/views/*) return 0 ;;
    public/*|static/*|styles/*) return 0 ;;
    *.tsx|*.jsx|*.vue|*.svelte) return 0 ;;
  esac
  return 1
}

# Order: tests first (e2e under app/ should still be tests), then backend, then frontend.
classify() {
  local p="$1"
  if is_tests "$p"; then echo "tests"; return; fi
  if is_backend "$p"; then echo "backend"; return; fi
  if is_frontend "$p"; then echo "frontend"; return; fi
  echo "uncategorised"
}

BE_GLOBS=(); BE_FILES=()
FE_GLOBS=(); FE_FILES=()
TS_GLOBS=(); TS_FILES=()
UNCAT=()

for entry in "${ALLOWLIST[@]}"; do
  CLASS=$(classify "$entry")
  case "$CLASS" in
    backend)       BE_GLOBS+=("$entry") ;;
    frontend)      FE_GLOBS+=("$entry") ;;
    tests)         TS_GLOBS+=("$entry") ;;
    uncategorised) UNCAT+=("$entry") ;;
  esac
done

# Resolve files inside project for one concern (best-effort, may glob).
# Echoes one file path per line on stdout; caller captures into an array.
resolve_files_for() {
  local g
  for g in "$@"; do
    if [[ "$g" == *"*"* ]]; then
      (cd "$PROJECT_ROOT" 2>/dev/null && find . -path "./${g}" -type f 2>/dev/null | sed 's|^\./||' | head -200)
    else
      [[ -f "$PROJECT_ROOT/$g" ]] && echo "$g"
    fi
  done
}

# Capture stdout into arrays, tolerating empty globs.
while IFS= read -r f; do [[ -n "$f" ]] && BE_FILES+=("$f"); done < <(resolve_files_for ${BE_GLOBS[@]+"${BE_GLOBS[@]}"})
while IFS= read -r f; do [[ -n "$f" ]] && FE_FILES+=("$f"); done < <(resolve_files_for ${FE_GLOBS[@]+"${FE_GLOBS[@]}"})
while IFS= read -r f; do [[ -n "$f" ]] && TS_FILES+=("$f"); done < <(resolve_files_for ${TS_GLOBS[@]+"${TS_GLOBS[@]}"})

# Dispatch eligibility: a concern is dispatched iff it has ≥1 glob.
BE_DISPATCH=$([[ ${#BE_GLOBS[@]} -gt 0 ]] && echo true || echo false)
FE_DISPATCH=$([[ ${#FE_GLOBS[@]} -gt 0 ]] && echo true || echo false)
TS_DISPATCH=$([[ ${#TS_GLOBS[@]} -gt 0 ]] && echo true || echo false)

# Mode resolution.
DISPATCH_COUNT=0
[[ "$BE_DISPATCH" == "true" ]] && DISPATCH_COUNT=$((DISPATCH_COUNT+1))
[[ "$FE_DISPATCH" == "true" ]] && DISPATCH_COUNT=$((DISPATCH_COUNT+1))
[[ "$TS_DISPATCH" == "true" ]] && DISPATCH_COUNT=$((DISPATCH_COUNT+1))

if [[ "$FORCE_SINGLE" -eq 1 || "$DISPATCH_COUNT" -le 1 ]]; then
  MODE="single-persona"
else
  MODE="multi-persona"
fi

# Build JSON arrays helper — call with array expanded via ${arr[@]+"${arr[@]}"}
# which expands to NOTHING when the array is empty (avoiding stray "").
arr_json() {
  if [[ $# -eq 0 ]]; then
    echo "[]"
  else
    printf '%s\n' "$@" | jq -R . | jq -s .
  fi
}

BE_GLOBS_JSON=$(arr_json ${BE_GLOBS[@]+"${BE_GLOBS[@]}"})
FE_GLOBS_JSON=$(arr_json ${FE_GLOBS[@]+"${FE_GLOBS[@]}"})
TS_GLOBS_JSON=$(arr_json ${TS_GLOBS[@]+"${TS_GLOBS[@]}"})
BE_FILES_JSON=$(arr_json ${BE_FILES[@]+"${BE_FILES[@]}"})
FE_FILES_JSON=$(arr_json ${FE_FILES[@]+"${FE_FILES[@]}"})
TS_FILES_JSON=$(arr_json ${TS_FILES[@]+"${TS_FILES[@]}"})
UNCAT_JSON=$(arr_json ${UNCAT[@]+"${UNCAT[@]}"})

jq -n \
  --arg mode "$MODE" \
  --argjson be_g "$BE_GLOBS_JSON" --argjson be_f "$BE_FILES_JSON" --argjson be_d "$BE_DISPATCH" \
  --argjson fe_g "$FE_GLOBS_JSON" --argjson fe_f "$FE_FILES_JSON" --argjson fe_d "$FE_DISPATCH" \
  --argjson ts_g "$TS_GLOBS_JSON" --argjson ts_f "$TS_FILES_JSON" --argjson ts_d "$TS_DISPATCH" \
  --argjson uncat "$UNCAT_JSON" \
  --arg ran_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    schema_version: "ubs-v8.4-implementer-split",
    mode: $mode,
    ran_at: $ran_at,
    concerns: {
      backend:  { globs: $be_g, files: $be_f, dispatch: $be_d },
      frontend: { globs: $fe_g, files: $fe_f, dispatch: $fe_d },
      tests:    { globs: $ts_g, files: $ts_f, dispatch: $ts_d }
    },
    uncategorised: $uncat
  }' > "$OUT"

log "split written → $OUT (mode=$MODE be=$BE_DISPATCH fe=$FE_DISPATCH ts=$TS_DISPATCH uncat=${#UNCAT[@]})"

if [[ ${#UNCAT[@]} -gt 0 ]]; then
  log "HALT: ${#UNCAT[@]} uncategorised allowlist entry/entries — reviewer must categorise"
  for u in "${UNCAT[@]}"; do log "  - $u"; done
  exit 1
fi

exit 0
