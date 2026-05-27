#!/usr/bin/env bash
# e2e-maestro.sh — GATE-25-E2E-MOBILE (v8.6)
#
# Mobile-equivalent of e2e-playwright.sh. Drives Maestro (cross-platform
# YAML-based UI automation: iOS native, Android native, RN, Flutter, Expo).
#
# Inputs (from .build-anything.json):
#   project_type        (must match mobile-*)
#   maestro.enabled     (bool)
#   maestro.flows_dir   (default ".maestro/" — Maestro convention)
#   maestro.app_id      (iOS bundle id OR Android package name)
#   maestro.platform    ("ios" | "android" | "auto" — auto = derive from project_type)
#   maestro.boot        (bool, default false — boot sim/emu; CI usually leaves false)
#   maestro.run_cmd     (default "maestro test ${flows_dir}")
#
# Rules (mirroring v8.5.1 Playwright mandate at LAW-F6 layer):
#   - project_type ∈ mobile-* AND maestro.enabled=false → FAIL (declared-but-skipped is the v8.5 hole)
#   - project_type NOT mobile-* → N/A_PENDING_REVIEWER (Playwright handles web)
#   - maestro binary missing → FAIL with install hint (not silent N/A)
#   - flows_dir absent OR contains 0 *.yaml flows → FAIL
#   - maestro run exits 0 AND output shows ≥1 passed AND 0 failed → PASS
#   - vacuous run (0 passed AND 0 failed) → FAIL
#
# Exit: 0 PASS or N/A, 1 FAIL, 2 preflight error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../backend/_common.sh"

atom_dir_from_args "$@"
EVIDENCE_LOCAL="$ATOM_DIR/gate-mechanical"
mkdir -p "$EVIDENCE_LOCAL"
OUT="$EVIDENCE_LOCAL/e2e-maestro.json"

PROJECT_TYPE=$(cfg "project_type" "backend")
MAESTRO_ENABLED=$(cfg "maestro.enabled" "false")
FLOWS_DIR=$(cfg "maestro.flows_dir" ".maestro")
APP_ID=$(cfg "maestro.app_id" "")
PLATFORM=$(cfg "maestro.platform" "auto")
BOOT=$(cfg "maestro.boot" "false")
RUN_CMD=$(cfg "maestro.run_cmd" "")

[[ "$FLOWS_DIR" = /* ]] || FLOWS_DIR="$PROJECT_ROOT/$FLOWS_DIR"

emit_mobile_na() {
  cat > "$OUT" <<JSON
{
  "gate": "GATE-25-E2E-MOBILE",
  "passed": null,
  "verdict": "N/A_PENDING_REVIEWER",
  "reason": "$1",
  "review_required": true,
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

emit_mobile_fail() {
  local reason="$1" details="${2:-}"
  [[ -z "$details" ]] && details='{}'
  cat > "$OUT" <<JSON
{
  "gate": "GATE-25-E2E-MOBILE",
  "passed": false,
  "verdict": "FAIL",
  "reason": "$reason",
  "evidence": $details,
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 1
}

emit_mobile_pass() {
  local details="$1"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-25-E2E-MOBILE",
  "passed": true,
  "verdict": "PASS",
  "evidence": $details,
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

# ── Trigger check: only for mobile-* project_type ──────────────────
case "$PROJECT_TYPE" in
  mobile-*) : ;;
  *)
    emit_mobile_na "project_type=$PROJECT_TYPE — Maestro runner handles mobile only"
    ;;
esac

# ── Resolve platform from project_type when auto ───────────────────
if [[ "$PLATFORM" == "auto" ]]; then
  case "$PROJECT_TYPE" in
    mobile-ios)            PLATFORM="ios" ;;
    mobile-android)        PLATFORM="android" ;;
    mobile-rn|mobile-expo|mobile-flutter)
      # Cross-platform stacks default to iOS; operator can override
      # via maestro.platform to test android specifically.
      PLATFORM="ios"
      ;;
    *)                     PLATFORM="ios" ;;
  esac
fi

# ── LAW-F6: mobile project_type + maestro disabled → FAIL ──────────
# Same reasoning as v8.5.1 e2e-playwright mandate: declared-but-skipped is
# the exact hole that lets shipping bugs through.
if [[ "$MAESTRO_ENABLED" != "true" ]]; then
  emit_mobile_fail "project_type=$PROJECT_TYPE requires maestro.enabled=true; LAW-F6 forbids skipping mobile E2E" \
    '{"hint": "Add { \"maestro\": { \"enabled\": true, \"flows_dir\": \".maestro\", \"app_id\": \"com.example.app\" } } to .build-anything.json"}'
fi

# ── Maestro binary check ───────────────────────────────────────────
if ! command -v maestro >/dev/null 2>&1; then
  emit_mobile_fail "maestro binary not on PATH" \
    '{"install": "curl -Ls \"https://get.maestro.mobile.dev\" | bash", "docs": "https://maestro.mobile.dev/getting-started/installing-maestro"}'
fi
MAESTRO_VERSION=$(maestro --version 2>/dev/null | head -1 | tr -d '\r' || echo "unknown")

# ── Flows directory check ──────────────────────────────────────────
if [[ ! -d "$FLOWS_DIR" ]]; then
  emit_mobile_fail "maestro.flows_dir not found at $FLOWS_DIR" \
    "{\"expected\": \"$FLOWS_DIR\", \"hint\": \"Maestro flows are *.yaml files under .maestro/ by convention\"}"
fi

flow_count=$(find "$FLOWS_DIR" -type f \( -name "*.yaml" -o -name "*.yml" \) 2>/dev/null | wc -l | tr -d ' ')
if [[ "$flow_count" -eq 0 ]]; then
  emit_mobile_fail "no Maestro flows found under $FLOWS_DIR (looking for *.yaml/*.yml)" \
    "{\"flows_dir\": \"$FLOWS_DIR\", \"yaml_count\": 0}"
fi

# ── App ID check ───────────────────────────────────────────────────
if [[ -z "$APP_ID" ]]; then
  emit_mobile_fail "maestro.app_id is required (iOS bundle id OR Android package name)" \
    '{"hint": "iOS: com.example.MyApp ; Android: com.example.myapp"}'
fi

# ── Boot simulator / emulator (optional; off by default for CI) ────
SPAWNED_BOOT_PIDS=()
cleanup_boot() {
  for pid in "${SPAWNED_BOOT_PIDS[@]:-}"; do
    [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null || true
  done
}
trap cleanup_boot EXIT

if [[ "$BOOT" == "true" ]]; then
  case "$PLATFORM" in
    ios)
      if ! command -v xcrun >/dev/null 2>&1; then
        emit_mobile_fail "maestro.boot=true requires xcrun (Xcode command-line tools)" \
          '{"install": "xcode-select --install"}'
      fi
      # Boot first available booted-or-shutdown iPhone simulator
      sim_udid=$(xcrun simctl list devices available 2>/dev/null | awk '/iPhone/{print; exit}' | grep -oE '\([A-F0-9-]{36}\)' | tr -d '()' | head -1)
      if [[ -n "$sim_udid" ]]; then
        xcrun simctl boot "$sim_udid" 2>/dev/null || true
        echo "[e2e-maestro] booted iOS simulator $sim_udid" >&2
      fi
      ;;
    android)
      if ! command -v emulator >/dev/null 2>&1; then
        emit_mobile_fail "maestro.boot=true requires Android emulator on PATH" \
          '{"install": "Install Android Studio + create AVD; ensure $ANDROID_HOME/emulator in PATH"}'
      fi
      avd=$(emulator -list-avds 2>/dev/null | head -1)
      if [[ -n "$avd" ]]; then
        emulator -avd "$avd" -no-window -no-audio >/dev/null 2>&1 &
        SPAWNED_BOOT_PIDS+=("$!")
        echo "[e2e-maestro] booting Android emulator $avd (pid=$!)" >&2
        # Wait for boot (max 120s)
        for _ in $(seq 1 60); do
          if adb shell getprop sys.boot_completed 2>/dev/null | grep -q 1; then
            break
          fi
          sleep 2
        done
      fi
      ;;
  esac
fi

# ── Run Maestro ────────────────────────────────────────────────────
[[ -z "$RUN_CMD" ]] && RUN_CMD="maestro test $FLOWS_DIR"

run_log=$(mktemp)
echo "[e2e-maestro] running: $RUN_CMD" >&2
set +e
(cd "$PROJECT_ROOT" && eval "$RUN_CMD") >"$run_log" 2>&1
rc=$?
set -e

# ── Parse results ──────────────────────────────────────────────────
# Maestro output line shapes:
#   "[Passed]"  / "[Failed]"  per flow
#   Summary    "X passed, Y failed"
passed_count=$(grep -cE '\[Passed\]' "$run_log" 2>/dev/null || echo 0)
failed_count=$(grep -cE '\[Failed\]' "$run_log" 2>/dev/null || echo 0)
# Fallback parse: count YAML files run via "Running on" markers
runs_count=$(grep -cE '^>> Running ' "$run_log" 2>/dev/null || echo 0)

# Strip newlines / non-digits
passed_count=${passed_count//[^0-9]/}
failed_count=${failed_count//[^0-9]/}
runs_count=${runs_count//[^0-9]/}
: "${passed_count:=0}"
: "${failed_count:=0}"
: "${runs_count:=0}"

details=$(jq -n \
  --arg pt "$PROJECT_TYPE" \
  --arg pl "$PLATFORM" \
  --arg fd "$FLOWS_DIR" \
  --arg app "$APP_ID" \
  --arg ver "$MAESTRO_VERSION" \
  --arg log "$(tail -50 "$run_log" 2>/dev/null | jq -Rs . | sed 's/^"//;s/"$//' )" \
  --argjson flow_count "$flow_count" \
  --argjson passed "$passed_count" \
  --argjson failed "$failed_count" \
  --argjson runs "$runs_count" \
  --argjson rc "$rc" \
  '{project_type: $pt, platform: $pl, flows_dir: $fd, app_id: $app, maestro_version: $ver, flow_count: $flow_count, passed: $passed, failed: $failed, runs: $runs, exit_code: $rc, tail_log: $log}')

rm -f "$run_log"

# Vacuous-run guard (LAW-F6)
if [[ "$rc" -eq 0 && "$passed_count" -eq 0 && "$failed_count" -eq 0 ]]; then
  emit_mobile_fail "maestro reported 0 passed AND 0 failed (vacuous run — likely no flows executed)" "$details"
fi

if [[ "$rc" -ne 0 || "$failed_count" -gt 0 ]]; then
  emit_mobile_fail "maestro: rc=$rc passed=$passed_count failed=$failed_count" "$details"
fi

if [[ "$passed_count" -eq 0 ]]; then
  emit_mobile_fail "maestro: 0 flows passed (rc=$rc; check tail_log)" "$details"
fi

emit_mobile_pass "$details"
