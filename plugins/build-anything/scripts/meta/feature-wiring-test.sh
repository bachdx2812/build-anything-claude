#!/usr/bin/env bash
# feature-wiring-test.sh — meta-gate for GATE-PFC-WIRE (v8.8 Stage 4).
#
# Asserts the feature-wiring gate correctly distinguishes a feature that is
# merely NAMED (spec/intent + a feature_wiring declaration) from one that is
# actually WIRED (route + handler symbol + test reference present in source):
#   1. PASS — must-have feature has its route, handler, and test_ref in source.
#   2. FAIL — handler symbol declared in wiring map but ABSENT from source
#             (the audit shape: route + test present, no handler implementation).
#   3. FAIL — must-have feature has NO feature_wiring entry at all (named in
#             spec but never declared where wired).
#   4. N/A  — no declared.feature_surface[] must-items (LAW-F6: no vacuous PASS).
#
# Why this exists: GATE-PFC (text) passed a build that NAMED "video upload" in
# its feature_surface while no /api/upload route, no UploadHandler, no test
# existed. GATE-PFC-WIRE is the v8.8 fix. Without this regression a future edit
# could collapse wiring back to a declaration check and the finding returns.
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE_SCRIPT="$SKILL_ROOT/scripts/spec/feature-wiring-check.sh"

OUT_BASE="$(mktemp -d -t feat-wire-meta-XXXXXX)"
declare -a CASES_PASSED CASES_FAILED

log() { echo "[meta:feat-wire] $*" >&2; }

[[ -f "$GATE_SCRIPT" ]] || { log "FATAL: gate script missing: $GATE_SCRIPT"; exit 2; }

# setup <name> <feature_surface-json-array> <config-json> → echoes case_dir
setup() {
  local name="$1" fs="$2" cfg="$3"
  local case_dir="$OUT_BASE/$name"
  local atom_dir="$case_dir/atom"
  mkdir -p "$atom_dir/intent" "$atom_dir/gate-spec"
  cat > "$atom_dir/intent/verdict.json" <<EOF
{ "declared": { "feature_surface": $fs }, "next_action": "READY", "confidence": 100 }
EOF
  printf '%s' "$cfg" > "$case_dir/.build-anything.json"
  echo "$case_dir"
}

run_case() {
  local name="$1" case_dir="$2" expected_verdict="$3" expected_rc="$4"
  local atom_dir="$case_dir/atom"
  log "case=$name expect=verdict:$expected_verdict rc:$expected_rc"
  set +e
  bash "$GATE_SCRIPT" --atom-dir "$atom_dir" --project-root "$case_dir" \
    >"$case_dir/stdout" 2>"$case_dir/stderr"
  local actual_rc=$?
  set -e
  local verdict_file="$atom_dir/gate-spec/feature-wiring.json"
  if [[ ! -f "$verdict_file" ]]; then
    log "  -> FAIL: no verdict file"; CASES_FAILED+=("$name(no-verdict)"); return
  fi
  local actual_verdict
  actual_verdict=$(jq -r '.verdict' "$verdict_file" 2>/dev/null)
  if [[ "$actual_verdict" == "$expected_verdict" && "$actual_rc" == "$expected_rc" ]]; then
    log "  -> PASS"; CASES_PASSED+=("$name")
  else
    log "  -> FAIL: got verdict=$actual_verdict rc=$actual_rc"
    jq -c '{verdict,unwired_features,wired_features,reason}' "$verdict_file" 2>/dev/null | sed 's/^/       /' >&2 || true
    CASES_FAILED+=("$name(verdict=$actual_verdict,rc=$actual_rc)")
  fi
}

# Wiring map shared by cases 1 & 2 — "video upload" declares where it's wired.
WIRE_CFG='{
  "feature_wiring": {
    "video upload": {
      "routes": ["/api/upload"],
      "handlers": ["UploadHandler"],
      "test_refs": ["TestUpload"]
    }
  }
}'
UPLOAD_FS='[{"name":"video upload","must":true}]'

# ── Case 1: fully wired → PASS ─────────────────────────────────────────
CD=$(setup "1_wired" "$UPLOAD_FS" "$WIRE_CFG")
mkdir -p "$CD/src"
printf '%s\n' 'package main
// route /api/upload handled by UploadHandler
func UploadHandler() {}' > "$CD/src/router.go"
printf '%s\n' 'package main
func TestUpload(t *testing.T) {}' > "$CD/src/upload_test.go"
run_case "1_wired" "$CD" "PASS" "0"

# ── Case 2: handler symbol missing from source → FAIL ──────────────────
# Route + test present; UploadHandler is declared in wiring but never written.
CD=$(setup "2_missing_handler" "$UPLOAD_FS" "$WIRE_CFG")
mkdir -p "$CD/src"
printf '%s\n' 'package main
// route /api/upload registered here, but no handler symbol
func register() {}' > "$CD/src/router.go"
printf '%s\n' 'package main
func TestUpload(t *testing.T) {}' > "$CD/src/upload_test.go"
run_case "2_missing_handler" "$CD" "FAIL" "1"

# ── Case 3: feature has NO feature_wiring entry → FAIL ─────────────────
# "comments" is a must-have but feature_wiring has no key for it; a src file
# exists so the surface guard does not trip.
CD=$(setup "3_no_wiring_entry" '[{"name":"comments","must":true}]' \
  '{"feature_wiring":{"video upload":{"routes":["/api/upload"]}}}')
mkdir -p "$CD/src"
printf '%s\n' 'package main
func main() {}' > "$CD/src/app.go"
run_case "3_no_wiring_entry" "$CD" "FAIL" "1"

# ── Case 4: no feature_surface must-items → N/A (LAW-F6) ───────────────
CD=$(setup "4_no_feature_surface" '[]' '{"feature_wiring":{}}')
mkdir -p "$CD/src"
printf '%s\n' 'package main
func main() {}' > "$CD/src/app.go"
run_case "4_no_feature_surface" "$CD" "N/A_PENDING_REVIEWER" "0"

# ── Aggregate ──────────────────────────────────────────────────────────
if [[ ${#CASES_FAILED[@]} -gt 0 ]]; then
  log "FAILED cases:"; for c in "${CASES_FAILED[@]}"; do log "  - $c"; done
  log "summary: pass=${#CASES_PASSED[@]} fail=${#CASES_FAILED[@]} verdict=FAIL"
  exit 1
fi
log "summary: pass=${#CASES_PASSED[@]} fail=0 verdict=PASS"
exit 0
