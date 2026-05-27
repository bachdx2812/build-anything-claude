#!/usr/bin/env bash
# mobile-e2e-test.sh — meta-gate for v8.6 mobile layer (GATE-25-E2E-MOBILE + GATE-MOBILE-PERMS)
#
# Asserts both mobile mechanical gates correctly enforce LAW-F6 (no vacuous PASS):
#
# e2e-maestro fixtures:
#   1. project_type=backend → N/A_PENDING_REVIEWER (web passthrough)
#   2. project_type=mobile-rn with maestro.enabled=false → FAIL (LAW-F6 declared-but-skipped)
#   3. project_type=mobile-ios with no .maestro/ dir → FAIL (flows_dir missing)
#   4. project_type=mobile-ios with .maestro/ but 0 *.yaml → FAIL (0 flows)
#
# mobile-perms fixtures:
#   5. project_type=backend → N/A_PENDING_REVIEWER (non-mobile)
#   6. project_type=mobile-ios with code using AVCaptureDevice but no NSCameraUsageDescription → FAIL (missing-description CRITICAL)
#   7. project_type=mobile-android with AndroidManifest declaring CAMERA but no code uses it → FAIL (orphan HIGH, strict mode)
#
# Why this exists: v8.6 closes the mobile-E2E + perms gap. Without this meta-gate, the
# mobile-* dispatch path could silently relax (e.g. skip maestro requirement, accept orphan
# perms) and Devin could ship un-runnable mobile apps that App Store / Play instantly reject.
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MAESTRO_SCRIPT="$SKILL_ROOT/scripts/mechanical/e2e-maestro.sh"
PERMS_SCRIPT="$SKILL_ROOT/scripts/mechanical/mobile-perms-check.sh"

OUT_BASE="$(mktemp -d -t mobile-e2e-meta-XXXXXX)"
SUMMARY="$OUT_BASE/summary.json"
declare -a CASES_PASSED CASES_FAILED

log() { echo "[meta:mobile-e2e] $*" >&2; }

if [[ ! -x "$MAESTRO_SCRIPT" ]]; then
  log "FATAL: maestro gate script not executable: $MAESTRO_SCRIPT"
  exit 2
fi
if [[ ! -x "$PERMS_SCRIPT" ]]; then
  log "FATAL: perms gate script not executable: $PERMS_SCRIPT"
  exit 2
fi

# ── Fixture builder ───────────────────────────────────────────────
mk_project() {
  local name="$1" config_json="$2"
  local proj_dir="$OUT_BASE/$name"
  mkdir -p "$proj_dir"
  echo "$config_json" > "$proj_dir/.build-anything.json"
  mkdir -p "$proj_dir/atom/gate-mechanical"
  echo "$proj_dir"
}

run_case() {
  local name="$1" gate_script="$2" proj_dir="$3" verdict_file="$4" expected_verdict="$5" expected_rc="$6"
  log "case=$name script=$(basename "$gate_script") expect=verdict:$expected_verdict rc:$expected_rc"

  set +e
  bash "$gate_script" --atom-dir "$proj_dir/atom" --project-root "$proj_dir" \
    >"$proj_dir/stdout" 2>"$proj_dir/stderr"
  local actual_rc=$?
  set -e

  if [[ ! -f "$proj_dir/atom/$verdict_file" ]]; then
    log "  -> FAIL: no verdict file at $proj_dir/atom/$verdict_file"
    CASES_FAILED+=("$name(no-verdict-file)")
    return
  fi

  local actual_verdict
  actual_verdict=$(jq -r '.verdict' "$proj_dir/atom/$verdict_file" 2>/dev/null)

  if [[ "$actual_verdict" == "$expected_verdict" && "$actual_rc" == "$expected_rc" ]]; then
    log "  -> PASS"
    CASES_PASSED+=("$name")
  else
    log "  -> FAIL: got verdict=$actual_verdict rc=$actual_rc"
    log "       file: $proj_dir/atom/$verdict_file"
    jq -c '.' "$proj_dir/atom/$verdict_file" 2>/dev/null | sed 's/^/         /' >&2 || true
    CASES_FAILED+=("$name(verdict=$actual_verdict,rc=$actual_rc)")
  fi
}

# ── Case 1: backend → e2e-maestro N/A ────────────────────────────────
PROJ=$(mk_project "1_maestro_web_na" '{"project_type":"backend"}')
run_case "1_maestro_web_na" "$MAESTRO_SCRIPT" "$PROJ" "gate-mechanical/e2e-maestro.json" "N/A_PENDING_REVIEWER" "0"

# ── Case 2: mobile-rn maestro disabled → FAIL (LAW-F6) ──────────────
PROJ=$(mk_project "2_maestro_disabled_fail" '{"project_type":"mobile-rn","maestro":{"enabled":false}}')
run_case "2_maestro_disabled_fail" "$MAESTRO_SCRIPT" "$PROJ" "gate-mechanical/e2e-maestro.json" "FAIL" "1"

# ── Case 3: mobile-ios no flows_dir → FAIL ───────────────────────────
PROJ=$(mk_project "3_maestro_no_flows_dir" '{"project_type":"mobile-ios","maestro":{"enabled":true,"flows_dir":".maestro","app_id":"com.example.app"}}')
# Skip flows_dir creation — gate must FAIL before reaching maestro binary check
run_case "3_maestro_no_flows_dir" "$MAESTRO_SCRIPT" "$PROJ" "gate-mechanical/e2e-maestro.json" "FAIL" "1"

# ── Case 4: mobile-ios flows_dir empty (0 yaml) → FAIL ───────────────
PROJ=$(mk_project "4_maestro_zero_flows" '{"project_type":"mobile-ios","maestro":{"enabled":true,"flows_dir":".maestro","app_id":"com.example.app"}}')
mkdir -p "$PROJ/.maestro"
# Empty dir — no yaml files
run_case "4_maestro_zero_flows" "$MAESTRO_SCRIPT" "$PROJ" "gate-mechanical/e2e-maestro.json" "FAIL" "1"

# ── Case 5: backend → mobile-perms N/A ───────────────────────────────
PROJ=$(mk_project "5_perms_web_na" '{"project_type":"frontend"}')
run_case "5_perms_web_na" "$PERMS_SCRIPT" "$PROJ" "gate-mechanical/mobile-perms.json" "N/A_PENDING_REVIEWER" "0"

# ── Case 6: mobile-ios code uses camera, no Info.plist entry → FAIL (CRITICAL) ──
PROJ=$(mk_project "6_perms_missing_camera_desc" '{"project_type":"mobile-ios","mobile":{"perms":{"ios_root":"ios","android_root":"android"}}}')
mkdir -p "$PROJ/ios/MyApp"
cat > "$PROJ/ios/MyApp/Info.plist" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.example.myapp</string>
</dict>
</plist>
XML
mkdir -p "$PROJ/ios/MyApp/Sources"
cat > "$PROJ/ios/MyApp/Sources/CameraView.swift" <<'SWIFT'
import AVFoundation

class CameraController {
  func openCamera() {
    let device = AVCaptureDevice.default(for: .video)
    print(device)
  }
}
SWIFT
run_case "6_perms_missing_camera_desc" "$PERMS_SCRIPT" "$PROJ" "gate-mechanical/mobile-perms.json" "FAIL" "1"

# ── Case 7: mobile-android orphan CAMERA permission → FAIL (HIGH, strict) ─────
PROJ=$(mk_project "7_perms_orphan_camera" '{"project_type":"mobile-android","mobile":{"perms":{"strict":true}}}')
mkdir -p "$PROJ/android/app/src/main"
cat > "$PROJ/android/app/src/main/AndroidManifest.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.CAMERA"/>
  <uses-permission android:name="android.permission.INTERNET"/>
  <application/>
</manifest>
XML
mkdir -p "$PROJ/android/app/src/main/kotlin/com/example"
cat > "$PROJ/android/app/src/main/kotlin/com/example/MainActivity.kt" <<'KOTLIN'
package com.example
import okhttp3.OkHttpClient
class MainActivity {
  val client = OkHttpClient()
  // INTERNET used via OkHttpClient; CAMERA declared but never used → orphan
}
KOTLIN
run_case "7_perms_orphan_camera" "$PERMS_SCRIPT" "$PROJ" "gate-mechanical/mobile-perms.json" "FAIL" "1"

# ── Aggregate ──────────────────────────────────────────────────────
TOTAL=$(( ${#CASES_PASSED[@]} + ${#CASES_FAILED[@]} ))
jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson total "$TOTAL" \
  --argjson pass "${#CASES_PASSED[@]}" \
  --argjson fail "${#CASES_FAILED[@]}" \
  --argjson passed "$(printf '%s\n' "${CASES_PASSED[@]:-}" | jq -R . | jq -s 'map(select(length>0))')" \
  --argjson failed "$(printf '%s\n' "${CASES_FAILED[@]:-}" | jq -R . | jq -s 'map(select(length>0))')" \
  '{
    meta_gate: "mobile-e2e-test",
    schema_version: "ubs-v8.6-meta",
    timestamp: $ts,
    cases_total: $total,
    cases_pass: $pass,
    cases_fail: $fail,
    cases_passed: $passed,
    cases_failed: $failed,
    verdict: (if $fail == 0 then "PASS" else "FAIL" end),
    interpretation: (if $fail == 0
      then "GATE-25-E2E-MOBILE + GATE-MOBILE-PERMS correctly enforce LAW-F6 — v8.6 mobile-layer invariant holds"
      else "Mobile-layer gate regressed — one or more fixtures returned unexpected verdict"
    end)
  }' > "$SUMMARY"

log "summary: $SUMMARY"
jq -r '"cases pass=" + (.cases_pass|tostring) + " fail=" + (.cases_fail|tostring) + " verdict=" + .verdict' "$SUMMARY" >&2

if [[ ${#CASES_FAILED[@]} -gt 0 ]]; then
  log "FAILED cases:"
  for c in "${CASES_FAILED[@]}"; do log "  - $c"; done
  exit 1
fi
exit 0
