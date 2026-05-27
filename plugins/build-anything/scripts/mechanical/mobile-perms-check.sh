#!/usr/bin/env bash
# mobile-perms-check.sh — GATE-MOBILE-PERMS (v8.6)
#
# Reconciles declared mobile permissions against actual code usage:
#   iOS:     Info.plist NS*UsageDescription keys  ↔  CoreLocation / AVFoundation / etc. API calls
#   Android: AndroidManifest.xml <uses-permission>  ↔  Camera / Location / Bluetooth / etc. API calls
#
# Two-way enforcement (mirrors App Store / Play review):
#   1. Orphan permission        — declared but no code uses it  → FAIL (will be rejected)
#   2. Missing usage description — code uses API but no permission declared → FAIL (will crash at runtime)
#
# Inputs (from .build-anything.json):
#   project_type            (must match mobile-*)
#   mobile.perms.ios_root   (default "ios/" — searches for Info.plist anywhere under)
#   mobile.perms.android_root (default "android/")
#   mobile.perms.code_globs (default mobile-stack-aware — swift|kt|java|ts|tsx|js|dart)
#   mobile.perms.strict     (default true — FAIL on orphans; false → orphans become warnings)
#
# Rules:
#   project_type NOT mobile-* → N/A_PENDING_REVIEWER
#   Neither Info.plist NOR AndroidManifest found → FAIL (mobile-* must have at least one)
#   declared perm with no code grep hit AND strict=true → FAIL
#   API grep hit with no declared perm → FAIL
#
# Exit: 0 PASS or N/A, 1 FAIL, 2 preflight error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../backend/_common.sh"

atom_dir_from_args "$@"
EVIDENCE_LOCAL="$ATOM_DIR/gate-mechanical"
mkdir -p "$EVIDENCE_LOCAL"
OUT="$EVIDENCE_LOCAL/mobile-perms.json"

PROJECT_TYPE=$(cfg "project_type" "backend")
IOS_ROOT=$(cfg "mobile.perms.ios_root" "ios")
ANDROID_ROOT=$(cfg "mobile.perms.android_root" "android")
STRICT=$(cfg "mobile.perms.strict" "true")

[[ "$IOS_ROOT" = /* ]]     || IOS_ROOT="$PROJECT_ROOT/$IOS_ROOT"
[[ "$ANDROID_ROOT" = /* ]] || ANDROID_ROOT="$PROJECT_ROOT/$ANDROID_ROOT"

emit_perms_na() {
  cat > "$OUT" <<JSON
{
  "gate": "GATE-MOBILE-PERMS",
  "passed": null,
  "verdict": "N/A_PENDING_REVIEWER",
  "reason": "$1",
  "review_required": true,
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

emit_perms_fail() {
  local reason="$1" details="${2:-}"
  [[ -z "$details" ]] && details='{}'
  cat > "$OUT" <<JSON
{
  "gate": "GATE-MOBILE-PERMS",
  "passed": false,
  "verdict": "FAIL",
  "reason": "$reason",
  "evidence": $details,
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 1
}

emit_perms_pass() {
  local details="$1"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-MOBILE-PERMS",
  "passed": true,
  "verdict": "PASS",
  "evidence": $details,
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

# ── Trigger check ──────────────────────────────────────────────────
case "$PROJECT_TYPE" in
  mobile-*) : ;;
  *)
    emit_perms_na "project_type=$PROJECT_TYPE — perms gate only fires for mobile-*"
    ;;
esac

# ── Locate manifests ───────────────────────────────────────────────
INFO_PLIST=""
ANDROID_MANIFEST=""

if [[ -d "$IOS_ROOT" ]]; then
  # Prefer ios/<App>/Info.plist over ios/Pods/.../Info.plist (skip Pods)
  INFO_PLIST=$(find "$IOS_ROOT" -name "Info.plist" -not -path "*/Pods/*" -not -path "*/build/*" 2>/dev/null | head -1)
fi
if [[ -d "$ANDROID_ROOT" ]]; then
  ANDROID_MANIFEST=$(find "$ANDROID_ROOT" -name "AndroidManifest.xml" -not -path "*/build/*" 2>/dev/null | head -1)
fi

if [[ -z "$INFO_PLIST" && -z "$ANDROID_MANIFEST" ]]; then
  emit_perms_fail "mobile-* project but neither Info.plist nor AndroidManifest.xml found" \
    "{\"ios_root\":\"$IOS_ROOT\",\"android_root\":\"$ANDROID_ROOT\"}"
fi

# ── Source code search roots ───────────────────────────────────────
# Use the project root; common mobile stacks scatter source across ios/, android/, src/, lib/
CODE_SEARCH_ROOTS=("$PROJECT_ROOT")

# ── iOS permission ↔ API regex table (phase-1 top 10) ──────────────
# Format: KEY|api_regex
IOS_PERMS=(
  "NSCameraUsageDescription|AVCaptureDevice|UIImagePickerController|ARKit|expo-camera|react-native-camera|image_picker"
  "NSPhotoLibraryUsageDescription|PHPhotoLibrary|UIImagePickerController|expo-image-picker|image_picker|react-native-image-picker"
  "NSPhotoLibraryAddUsageDescription|UIImageWriteToSavedPhotosAlbum|PHAssetCreationRequest|expo-media-library"
  "NSLocationWhenInUseUsageDescription|CLLocationManager|requestWhenInUseAuthorization|expo-location|react-native-geolocation|geolocator"
  "NSLocationAlwaysAndWhenInUseUsageDescription|requestAlwaysAuthorization|startMonitoringSignificantLocationChanges"
  "NSContactsUsageDescription|CNContactStore|ABAddressBook|expo-contacts|react-native-contacts|flutter_contacts"
  "NSMicrophoneUsageDescription|AVAudioRecorder|AVAudioSession|AVCaptureDevice.*audio|expo-av|react-native-audio|record"
  "NSCalendarsUsageDescription|EKEventStore|expo-calendar|device_calendar"
  "NSMotionUsageDescription|CMMotionManager|CMPedometer|expo-sensors|sensors_plus"
  "NSBluetoothAlwaysUsageDescription|CBCentralManager|CBPeripheralManager|flutter_blue|react-native-ble-plx"
  "NSFaceIDUsageDescription|LAContext|LocalAuthentication|expo-local-authentication|react-native-touch-id|local_auth"
  "NSUserTrackingUsageDescription|ATTrackingManager|requestTrackingAuthorization|react-native-tracking-transparency"
)

# ── Android permission ↔ API regex table ───────────────────────────
ANDROID_PERMS=(
  "android.permission.CAMERA|android.hardware.Camera|CameraManager|CameraX|MediaStore.ACTION_IMAGE_CAPTURE|expo-camera|react-native-camera|image_picker"
  "android.permission.ACCESS_FINE_LOCATION|FusedLocationProviderClient|LocationManager|getLastLocation|expo-location|geolocator"
  "android.permission.ACCESS_COARSE_LOCATION|FusedLocationProviderClient|LocationManager|expo-location"
  "android.permission.ACCESS_BACKGROUND_LOCATION|requestBackgroundPermissions|backgroundLocationUpdates"
  "android.permission.READ_CONTACTS|ContactsContract|expo-contacts|react-native-contacts|flutter_contacts"
  "android.permission.RECORD_AUDIO|MediaRecorder|AudioRecord|expo-av|react-native-audio|record"
  "android.permission.READ_CALENDAR|CalendarContract|expo-calendar|device_calendar"
  "android.permission.READ_EXTERNAL_STORAGE|Environment.getExternalStorage|MediaStore|expo-media-library"
  "android.permission.BLUETOOTH_CONNECT|BluetoothAdapter|BluetoothDevice.connect|flutter_blue|react-native-ble-plx"
  "android.permission.BLUETOOTH_SCAN|BluetoothLeScanner|startScan"
  "android.permission.POST_NOTIFICATIONS|NotificationManagerCompat|NotificationCompat.Builder|expo-notifications|firebase_messaging"
  "android.permission.USE_BIOMETRIC|BiometricPrompt|androidx.biometric|expo-local-authentication|local_auth"
  "android.permission.INTERNET|HttpURLConnection|OkHttpClient|Retrofit|fetch\\(|axios"
)

# ── Helper: grep code for any pipe-separated alt pattern ──────────
code_grep() {
  local pattern="$1"
  grep -rEoq --include='*.swift' --include='*.m' --include='*.mm' \
    --include='*.kt' --include='*.java' \
    --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' \
    --include='*.dart' \
    "($pattern)" "${CODE_SEARCH_ROOTS[@]}" 2>/dev/null
}

FINDINGS=()

# ── iOS reconciliation ─────────────────────────────────────────────
declared_ios=()
if [[ -n "$INFO_PLIST" ]]; then
  # Plain-text Info.plist (XML): keys are <key>NSCameraUsageDescription</key>
  # Binary Info.plist needs plutil — try plutil first
  if file "$INFO_PLIST" 2>/dev/null | grep -q "Apple binary property list"; then
    # Convert binary plist to XML on the fly for parsing
    plist_xml=$(plutil -convert xml1 -o - "$INFO_PLIST" 2>/dev/null || echo "")
  else
    plist_xml=$(cat "$INFO_PLIST")
  fi

  while IFS= read -r key; do
    [[ -n "$key" ]] && declared_ios+=("$key")
  done < <(echo "$plist_xml" | grep -oE '<key>NS[A-Za-z]+UsageDescription</key>' | sed 's/<key>//; s/<\/key>//')

  # 1) orphan check: declared but no code usage
  for entry in "${IOS_PERMS[@]}"; do
    key="${entry%%|*}"
    rx="${entry#*|}"
    declared=0
    for d in "${declared_ios[@]:-}"; do [[ "$d" == "$key" ]] && declared=1; done
    [[ "$declared" -eq 0 ]] && continue
    if ! code_grep "$rx"; then
      FINDINGS+=("{\"severity\":\"HIGH\",\"platform\":\"ios\",\"kind\":\"orphan-perm\",\"key\":\"$key\",\"reason\":\"declared in Info.plist but no matching API call found in code\"}")
    fi
  done

  # 2) missing-description check: code uses API but no key declared
  for entry in "${IOS_PERMS[@]}"; do
    key="${entry%%|*}"
    rx="${entry#*|}"
    declared=0
    for d in "${declared_ios[@]:-}"; do [[ "$d" == "$key" ]] && declared=1; done
    [[ "$declared" -eq 1 ]] && continue
    if code_grep "$rx"; then
      FINDINGS+=("{\"severity\":\"CRITICAL\",\"platform\":\"ios\",\"kind\":\"missing-usage-description\",\"key\":\"$key\",\"reason\":\"code references API requiring $key but Info.plist has no such key — iOS will crash on first use\"}")
    fi
  done
fi

# ── Android reconciliation ─────────────────────────────────────────
declared_android=()
if [[ -n "$ANDROID_MANIFEST" ]]; then
  while IFS= read -r perm; do
    [[ -n "$perm" ]] && declared_android+=("$perm")
  done < <(grep -oE 'android:name="[^"]+"' "$ANDROID_MANIFEST" 2>/dev/null \
            | grep -oE '"[^"]+"' | tr -d '"' \
            | grep -E '^android\.permission\.')

  for entry in "${ANDROID_PERMS[@]}"; do
    key="${entry%%|*}"
    rx="${entry#*|}"
    declared=0
    for d in "${declared_android[@]:-}"; do [[ "$d" == "$key" ]] && declared=1; done
    [[ "$declared" -eq 0 ]] && continue
    if ! code_grep "$rx"; then
      FINDINGS+=("{\"severity\":\"HIGH\",\"platform\":\"android\",\"kind\":\"orphan-perm\",\"key\":\"$key\",\"reason\":\"declared in AndroidManifest but no matching API call found in code\"}")
    fi
  done

  for entry in "${ANDROID_PERMS[@]}"; do
    key="${entry%%|*}"
    rx="${entry#*|}"
    declared=0
    for d in "${declared_android[@]:-}"; do [[ "$d" == "$key" ]] && declared=1; done
    [[ "$declared" -eq 1 ]] && continue
    if code_grep "$rx"; then
      FINDINGS+=("{\"severity\":\"CRITICAL\",\"platform\":\"android\",\"kind\":\"missing-permission\",\"key\":\"$key\",\"reason\":\"code references API requiring $key but AndroidManifest has no such uses-permission — Android will throw SecurityException\"}")
    fi
  done
fi

# ── Aggregate verdict ──────────────────────────────────────────────
findings_count=${#FINDINGS[@]}

critical=0
high=0
for f in "${FINDINGS[@]:-}"; do
  case "$f" in
    *CRITICAL*) critical=$((critical+1)) ;;
    *HIGH*)     high=$((high+1)) ;;
  esac
done

if [[ "$findings_count" -gt 0 ]]; then
  findings_json="["
  for i in "${!FINDINGS[@]}"; do
    [[ $i -gt 0 ]] && findings_json+=","
    findings_json+="${FINDINGS[$i]}"
  done
  findings_json+="]"
else
  findings_json="[]"
fi

declared_ios_json=$(printf '%s\n' "${declared_ios[@]:-}" | jq -R . | jq -s '[.[] | select(length > 0)]' 2>/dev/null || echo '[]')
declared_android_json=$(printf '%s\n' "${declared_android[@]:-}" | jq -R . | jq -s '[.[] | select(length > 0)]' 2>/dev/null || echo '[]')

details=$(jq -n \
  --arg pt "$PROJECT_TYPE" \
  --arg ip "$INFO_PLIST" \
  --arg am "$ANDROID_MANIFEST" \
  --argjson di "$declared_ios_json" \
  --argjson da "$declared_android_json" \
  --argjson findings "$findings_json" \
  --argjson critical "$critical" \
  --argjson high "$high" \
  '{project_type: $pt, info_plist: $ip, android_manifest: $am, declared_ios_keys: $di, declared_android_perms: $da, findings: $findings, counts: {CRITICAL: $critical, HIGH: $high}}')

# CRITICAL findings always FAIL (missing usage description = app crash / rejection)
if [[ "$critical" -gt 0 ]]; then
  emit_perms_fail "missing usage descriptions / permissions (CRITICAL=$critical, HIGH=$high)" "$details"
fi

# Orphan-perm (HIGH) only FAILs in strict mode
if [[ "$STRICT" == "true" && "$high" -gt 0 ]]; then
  emit_perms_fail "orphan permissions declared but unused (HIGH=$high; strict mode)" "$details"
fi

emit_perms_pass "$details"
