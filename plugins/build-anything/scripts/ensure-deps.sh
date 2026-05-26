#!/usr/bin/env bash
# ensure-deps.sh — Stage 0.5 dependency check
#
# v8.4 change: bmad-method demoted to INFORMATIONAL-ONLY.
# Reasons:
#   - `npx bmad-method run` does NOT exist (install/status/uninstall only).
#   - `npx bmad-method install` hangs on interactive "Installation directory:"
#     prompt despite --directory + --yes flags, blocking the pipeline.
#   - The skill now carries persona prompts under
#     sub-skills/spec/references/personas/ and dispatches them via the Claude
#     Code Task tool. The package's presence is no longer required for
#     Stage 1.B to function.
#
# Verifies the 2 BLOCKING dependencies and PROBES (non-blocking) for the
# third:
#
#   1. research          — local skill at ~/.claude/skills/research/        (BLOCKING)
#   2. ui-ux-pro-max     — local skill at ~/.claude/skills/ui-ux-pro-max/   (BLOCKING)
#   3. bmad-method       — npx package presence in project tree              (INFORMATIONAL)
#
# Honors LAW-F6: a missing BLOCKING dep is NEVER a vacuous PASS — HALT.
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

# ── 3. bmad-method (npx package) — INFORMATIONAL ONLY (v8.4) ───────
# Stage 1.B uses internalised persona prompts under sub-skills/spec/
# references/personas/. The npx package is recorded for evidence but
# never blocks. We DO NOT attempt `npx bmad-method install` because:
#   - the CLI prompts for "Installation directory:" interactively even
#     with --directory + --yes, causing the pipeline to hang.
#   - `npx bmad-method run` does NOT exist as a subcommand.
# Detection strategy: probe for existing in-project install only.
bmad_status="INFORMATIONAL_ABSENT"
if [[ -d "$PROJECT_ROOT/_bmad" || -d "$PROJECT_ROOT/bmad" || -f "$PROJECT_ROOT/bmad-modules.yaml" || -d "$PROJECT_ROOT/.bmad-core" ]]; then
  bmad_status="INFORMATIONAL_PRESENT"
  if [[ -d "$PROJECT_ROOT/_bmad" ]]; then
    bmad_install_path="$PROJECT_ROOT/_bmad"
  else
    bmad_install_path="$PROJECT_ROOT (in-project)"
  fi
  log "bmad-method present in project ($bmad_install_path) — informational, persona prompts are used regardless"
else
  log "bmad-method npx package absent — non-blocking (v8.4 method-not-invocation)"
fi

# ── Emit manifest ──────────────────────────────────────────────────
cat > "$ATOM_DIR/deps.json" <<JSON
{
  "deps_ok": $([[ "$research_status" == "PRESENT" && "$uiux_status" == "PRESENT" ]] && echo true || echo false),
  "checked_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "schema_version": "ubs-v8.4",
  "deps": {
    "research":      { "status": "$research_status",   "path": "$research_path",   "blocking": true },
    "ui-ux-pro-max": { "status": "$uiux_status",       "path": "$uiux_path",       "blocking": true },
    "bmad-method":   { "status": "$bmad_status",       "install_path": "$bmad_install_path", "version": "$bmad_version", "blocking": false, "note": "v8.4: persona prompts internalised under sub-skills/spec/references/personas/; npx package is informational only" }
  },
  "skills_dir": "$SKILLS_DIR",
  "project_root": "$PROJECT_ROOT"
}
JSON

log "deps.json written → $ATOM_DIR/deps.json"

if [[ "$research_status" != "PRESENT" || "$uiux_status" != "PRESENT" ]]; then
  log "FAIL: required local skills missing (research and/or ui-ux-pro-max)"
  exit 2
fi

log "deps ensured. bmad-method status: $bmad_status (informational)"
exit 0
