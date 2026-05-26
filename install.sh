#!/usr/bin/env bash
# install.sh — symlink `skill/` into ~/.claude/skills/build-anything/
# Idempotent. Run again to re-sync after `git pull`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
SKILL_SRC="$REPO_ROOT/skill"
SKILL_DST_DIR="$HOME/.claude/skills"
SKILL_DST="$SKILL_DST_DIR/build-anything"

if [[ ! -d "$SKILL_SRC" ]]; then
  echo "ERROR: $SKILL_SRC does not exist. Are you in the repo root?" >&2
  exit 1
fi

mkdir -p "$SKILL_DST_DIR"

if [[ -L "$SKILL_DST" ]]; then
  current=$(readlink "$SKILL_DST")
  if [[ "$current" == "$SKILL_SRC" ]]; then
    echo "OK: $SKILL_DST already points to $SKILL_SRC — nothing to do."
    exit 0
  fi
  echo "INFO: existing symlink points to $current — replacing."
  rm "$SKILL_DST"
elif [[ -e "$SKILL_DST" ]]; then
  backup="$SKILL_DST.backup.$(date +%Y%m%d%H%M%S)"
  echo "INFO: existing directory at $SKILL_DST — backing up to $backup"
  mv "$SKILL_DST" "$backup"
fi

ln -s "$SKILL_SRC" "$SKILL_DST"

echo "OK: linked $SKILL_DST -> $SKILL_SRC"
echo ""
echo "Verify:"
echo "  ls -la $SKILL_DST"
echo ""
echo "Use in Claude Code:"
echo "  /build-anything"
