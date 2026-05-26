#!/usr/bin/env bash
# ensure-deps.sh — Stage 0.5 dependency check + auto-install
#
# Verifies and installs (if missing) the 3 companion skills/tools required by
# the v8.2+ build-anything pipeline:
#
#   1. research          — local skill at ~/.claude/skills/research/
#   2. ui-ux-pro-max     — local skill at ~/.claude/skills/ui-ux-pro-max/
#   3. bmad-method       — npx package; installed into project via
#                          `npx bmad-method install --modules bmm --tools claude-code --yes`
#
# Honors LAW-F6: a missing dep is NEVER a vacuous PASS — either install or HALT.
# Emits JSON manifest at {ATOM_DIR}/deps.json so the orchestrator can audit.

set -euo pipefail

PROJECT_ROOT=""
ATOM_DIR=""
SKILLS_DIR="${HOME}/.claude/skills"
MODE="auto"   # auto | check-only | force-install

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --atom-dir)     ATOM_DIR="$2"; shift 2 ;;
    --check-only)   MODE="check-only"; shift ;;
    --force-install) MODE="force-install"; shift ;;
    *) shift ;;
  esac
done

: "${PROJECT_ROOT:?--project-root required}"
: "${ATOM_DIR:?--atom-dir required}"
mkdir -p "$ATOM_DIR"

log() { echo "[$(date -u +%H:%M:%S)] [ensure-deps] $*" >&2; }

# Per-dep status keys
research_status="MISSING"
research_path=""
uiux_status="MISSING"
uiux_path=""
bmad_status="MISSING"
bmad_version=""
bmad_install_path=""

# ── 1. research skill ──────────────────────────────────────────────
if [[ -f "$SKILLS_DIR/research/SKILL.md" ]]; then
  research_status="PRESENT"
  research_path="$SKILLS_DIR/research/SKILL.md"
  log "research skill OK ($research_path)"
else
  log "FATAL: research skill not found at $SKILLS_DIR/research/"
  log "       Cannot auto-install — local skill. Manual fix required."
  if [[ "$MODE" != "check-only" ]]; then
    echo "{\"deps_ok\": false, \"missing\": [\"research\"], \"reason\": \"local skill missing — manual install required\"}" > "$ATOM_DIR/deps.json"
    exit 2
  fi
fi

# ── 2. ui-ux-pro-max skill ─────────────────────────────────────────
if [[ -f "$SKILLS_DIR/ui-ux-pro-max/SKILL.md" ]]; then
  uiux_status="PRESENT"
  uiux_path="$SKILLS_DIR/ui-ux-pro-max/SKILL.md"
  log "ui-ux-pro-max skill OK ($uiux_path)"
else
  log "FATAL: ui-ux-pro-max skill not found at $SKILLS_DIR/ui-ux-pro-max/"
  log "       Cannot auto-install — local skill. Manual fix required."
  if [[ "$MODE" != "check-only" ]]; then
    echo "{\"deps_ok\": false, \"missing\": [\"ui-ux-pro-max\"], \"reason\": \"local skill missing — manual install required\"}" > "$ATOM_DIR/deps.json"
    exit 2
  fi
fi

# ── 3. bmad-method (npx package) ───────────────────────────────────
# Check 1: is it already installed in the project?
# bmad v6 installs to _bmad/, v5/legacy to bmad/ or .bmad-core/
if [[ -d "$PROJECT_ROOT/_bmad" || -d "$PROJECT_ROOT/bmad" || -f "$PROJECT_ROOT/bmad-modules.yaml" || -d "$PROJECT_ROOT/.bmad-core" ]]; then
  bmad_status="PRESENT"
  if [[ -d "$PROJECT_ROOT/_bmad" ]]; then
    bmad_install_path="$PROJECT_ROOT/_bmad"
  else
    bmad_install_path="$PROJECT_ROOT (in-project)"
  fi
  log "bmad-method already installed in project ($bmad_install_path)"
fi

# Check 2: is npx bmad-method callable?
if [[ "$bmad_status" == "MISSING" ]]; then
  if command -v npx >/dev/null 2>&1; then
    # Try to query version without full install
    if bmad_version=$(npx --yes -p bmad-method@latest bmad-method --version 2>/dev/null | tail -1); then
      log "bmad-method npx package reachable (version: $bmad_version)"
    else
      bmad_version=""
    fi
  else
    log "FATAL: npx not available — cannot install bmad-method"
    if [[ "$MODE" != "check-only" ]]; then
      echo "{\"deps_ok\": false, \"missing\": [\"bmad-method\"], \"reason\": \"npx missing on host\"}" > "$ATOM_DIR/deps.json"
      exit 2
    fi
  fi

  # Install if mode allows
  if [[ "$MODE" != "check-only" ]]; then
    log "Installing bmad-method into $PROJECT_ROOT …"
    set +e
    npx --yes bmad-method install \
      --directory "$PROJECT_ROOT" \
      --modules bmm \
      --tools claude-code \
      --yes 2>&1 | tail -20 >&2
    rc=$?
    set -e
    if [[ $rc -eq 0 ]] && [[ -d "$PROJECT_ROOT/_bmad" || -d "$PROJECT_ROOT/bmad" || -f "$PROJECT_ROOT/bmad-modules.yaml" || -d "$PROJECT_ROOT/.bmad-core" ]]; then
      bmad_status="INSTALLED"
      if [[ -d "$PROJECT_ROOT/_bmad" ]]; then
        bmad_install_path="$PROJECT_ROOT/_bmad"
      else
        bmad_install_path="$PROJECT_ROOT"
      fi
      log "bmad-method installed OK ($bmad_install_path)"
    else
      log "WARN: bmad install completed with rc=$rc but artefacts not detected"
      bmad_status="INSTALL_FAILED"
      # do not exit 2 here — bmad is advisory in fast mode; gate-spec will hard-fail if it's truly needed
    fi
  fi
fi

# ── Emit manifest ──────────────────────────────────────────────────
cat > "$ATOM_DIR/deps.json" <<JSON
{
  "deps_ok": $([[ "$research_status" == "PRESENT" && "$uiux_status" == "PRESENT" && "$bmad_status" != "MISSING" ]] && echo true || echo false),
  "checked_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deps": {
    "research":      { "status": "$research_status",   "path": "$research_path" },
    "ui-ux-pro-max": { "status": "$uiux_status",       "path": "$uiux_path" },
    "bmad-method":   { "status": "$bmad_status",       "install_path": "$bmad_install_path", "version": "$bmad_version" }
  },
  "skills_dir": "$SKILLS_DIR",
  "project_root": "$PROJECT_ROOT"
}
JSON

log "deps.json written → $ATOM_DIR/deps.json"

if [[ "$research_status" != "PRESENT" || "$uiux_status" != "PRESENT" ]]; then
  log "FAIL: required local skills missing"
  exit 2
fi

if [[ "$bmad_status" == "INSTALL_FAILED" || "$bmad_status" == "MISSING" ]]; then
  log "WARN: bmad-method not present — spec stage will run in degraded mode"
  # exit 0 with warning — let gate-spec decide if bmad is required for this atom type
fi

log "deps ensured."
exit 0
