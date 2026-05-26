#!/usr/bin/env bash
# Shared helpers for cloud/* gates. Delegates to backend/_common.sh to avoid drift.
# Source this from any scripts/cloud/*.sh.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../backend/_common.sh"

# Tool presence check — emit N/A_PENDING_REVIEWER if tool absent (not vacuous PASS).
require_tool_or_na() {
  local tool="$1" gate="$2" out="$3"
  if ! command -v "$tool" >/dev/null 2>&1; then
    log_step "${gate}" "tool '$tool' not installed — N/A_PENDING_REVIEWER"
    emit_na_pending "$gate" "$out" "tool '$tool' not on PATH; reviewer must install OR mark gate not-applicable for this atom"
    exit 0
  fi
}
