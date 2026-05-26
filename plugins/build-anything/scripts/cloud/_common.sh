#!/usr/bin/env bash
# Shared helpers for cloud/* gates. Delegates to backend/_common.sh to avoid drift.
# Source this from any scripts/cloud/*.sh.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../backend/_common.sh"

# Override atom_dir_from_args so cloud gates write to gate-cloud/, not gate-backend/.
atom_dir_from_args() {
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
  EVIDENCE_DIR="$ATOM_DIR/gate-cloud"
  mkdir -p "$EVIDENCE_DIR"
  export ATOM_DIR PROJECT_ROOT EVIDENCE_DIR
}

# Tool presence check — emit N/A_PENDING_REVIEWER if tool absent (not vacuous PASS).
require_tool_or_na() {
  local tool="$1" gate="$2" out="$3"
  if ! command -v "$tool" >/dev/null 2>&1; then
    log_step "${gate}" "tool '$tool' not installed — N/A_PENDING_REVIEWER"
    emit_na_pending "$gate" "$out" "tool '$tool' not on PATH; reviewer must install OR mark gate not-applicable for this atom"
    exit 0
  fi
}
