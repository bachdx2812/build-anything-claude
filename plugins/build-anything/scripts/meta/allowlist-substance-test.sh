#!/usr/bin/env bash
# allowlist-substance-test.sh — meta-gate for GATE-SUBSTANCE (v8.8 Stage 5).
#
# Fixtures mirror the exact §10 mandarin shape the audit found: directories
# declared as delivered that the filesystem says are empty / 0-byte.
#   1. SUBSTANCE     → PASS — internal/auth declared and holds a real, non-empty
#      service.go. Declaration earned.
#   2. EMPTY-DIR     → FAIL — internal/ai declared, dir created but EMPTY (the
#      §10 shape: counted as built, contains nothing).
#   3. ZERO-BYTE     → FAIL — internal/social declared, holds only a 0-byte x.go
#      stub that pads the dir with no implementation.
#   4. NO-DIRS       → N/A — nothing declared (no substance, no scope.paths).
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE_SCRIPT="$SKILL_ROOT/scripts/mechanical/allowlist-substance-check.sh"
OUT_BASE="$(mktemp -d -t substance-meta-XXXXXX)"
declare -a CASES_PASSED CASES_FAILED
log() { echo "[meta:substance] $*" >&2; }
[[ -f "$GATE_SCRIPT" ]] || { log "FATAL: gate script missing: $GATE_SCRIPT"; exit 2; }

setup() {  # <name> <config-json> → echoes case_dir
  local name="$1" cfg="$2"
  local case_dir="$OUT_BASE/$name"
  mkdir -p "$case_dir/atom/gate-mechanical"
  printf '%s' "$cfg" > "$case_dir/.build-anything.json"
  echo "$case_dir"
}

run_case() {
  local name="$1" case_dir="$2" want_verdict="$3" want_rc="$4"
  log "case=$name expect=verdict:$want_verdict rc:$want_rc"
  set +e
  bash "$GATE_SCRIPT" --atom-dir "$case_dir/atom" --project-root "$case_dir" \
    >"$case_dir/stdout" 2>"$case_dir/stderr"
  local rc=$?
  set -e
  local vf="$case_dir/atom/gate-mechanical/substance.json"
  [[ -f "$vf" ]] || { log "  -> FAIL: no verdict file"; CASES_FAILED+=("$name(no-verdict)"); return; }
  local v; v=$(jq -r '.verdict' "$vf" 2>/dev/null)
  if [[ "$v" == "$want_verdict" && "$rc" == "$want_rc" ]]; then
    log "  -> PASS"; CASES_PASSED+=("$name")
  else
    log "  -> FAIL: got verdict=$v rc=$rc"
    jq -c '{verdict,findings,reason}' "$vf" 2>/dev/null | sed 's/^/       /' >&2 || true
    CASES_FAILED+=("$name(verdict=$v,rc=$rc)")
  fi
}

# ── Case 1: real substance → PASS ─────────────────────────────────────
CD=$(setup "1_substance" '{"env":"test","substance":{"dirs":["internal/auth"]}}')
mkdir -p "$CD/internal/auth"
cat > "$CD/internal/auth/service.go" <<'GO'
package auth

import "errors"

func Authenticate(user, pass string) (string, error) {
	if user == "" || pass == "" {
		return "", errors.New("missing credentials")
	}
	return "token-" + user, nil
}
GO
run_case "1_substance" "$CD" "PASS" "0"

# ── Case 2: empty declared dir → FAIL (the §10 shape) ─────────────────
CD=$(setup "2_empty_dir" '{"env":"test","substance":{"dirs":["internal/ai"]}}')
mkdir -p "$CD/internal/ai"   # declared + present, but EMPTY
run_case "2_empty_dir" "$CD" "FAIL" "1"

# ── Case 3: 0-byte source stub → FAIL ─────────────────────────────────
CD=$(setup "3_zero_byte" '{"env":"test","substance":{"dirs":["internal/social"]}}')
mkdir -p "$CD/internal/social"
: > "$CD/internal/social/x.go"   # 0-byte source file
run_case "3_zero_byte" "$CD" "FAIL" "1"

# ── Case 4: nothing declared → N/A ────────────────────────────────────
CD=$(setup "4_no_dirs" '{"env":"test"}')
run_case "4_no_dirs" "$CD" "N/A_PENDING_REVIEWER" "0"

if [[ ${#CASES_FAILED[@]} -gt 0 ]]; then
  log "FAILED cases:"; for c in "${CASES_FAILED[@]}"; do log "  - $c"; done
  log "summary: pass=${#CASES_PASSED[@]} fail=${#CASES_FAILED[@]} verdict=FAIL"
  exit 1
fi
log "summary: pass=${#CASES_PASSED[@]} fail=0 verdict=PASS"
exit 0
