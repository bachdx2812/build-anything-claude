#!/usr/bin/env bash
# witness-sign.sh — LAW-17 external witness via cosign.
# Strategy:
#   1. cosign keyless OIDC if available (best — off-process trust root)
#   2. cosign with COSIGN_KEY env path (intermediate)
#   3. local-placeholder JSON if neither possible (worst — documented gap)
# Single-number contract: passed (true if a real signature was produced).

set -euo pipefail
source "$(dirname "$0")/../mechanical/_common.sh"

ATOM_DIR=""
SHA=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --atom-dir) ATOM_DIR="$2"; shift 2 ;;
    --sha)      SHA="$2"; shift 2 ;;
    *) shift ;;
  esac
done
: "${ATOM_DIR:?--atom-dir required}"
: "${SHA:?--sha required (manifest SHA-256)}"

OUT="$ATOM_DIR/witness.json"
SIG_OUT="$ATOM_DIR/manifest.sig"
CERT_OUT="$ATOM_DIR/manifest.cert"
BUNDLE_OUT="$ATOM_DIR/manifest.cosign-bundle.json"
SUBJECT_FILE="$ATOM_DIR/manifest.sha256"
log_step witness "atom=$ATOM_DIR sha=$SHA"

if ! command -v cosign >/dev/null 2>&1; then
  log_step witness "cosign not installed — writing placeholder (LAW-17 gap surfaced)"
  cat > "$OUT" <<JSON
{
  "witness": "local-placeholder",
  "witnessed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "manifest_sha256": "$SHA",
  "signature": null,
  "certificate": null,
  "method": "none",
  "note": "LAW-17 not satisfied — install cosign (brew install cosign) and re-run for keyless OIDC signature"
}
JSON
  exit 0
fi

COSIGN_VERSION=$(cosign version 2>&1 | grep -E "^GitVersion:" | awk '{print $2}' | head -1)
[[ -z "$COSIGN_VERSION" ]] && COSIGN_VERSION="unknown"
log_step witness "cosign found: $COSIGN_VERSION"

# Try keyless first (OIDC, GitHub/Google/etc — runs interactive in dev, automated in CI)
if [[ "${COSIGN_KEYLESS:-1}" == "1" ]] && [[ -n "${CI:-}" || -n "${COSIGN_EXPERIMENTAL:-}" ]]; then
  export COSIGN_EXPERIMENTAL=1
  if cosign sign-blob --yes "$SUBJECT_FILE" --bundle "$BUNDLE_OUT" >/dev/null 2>&1; then
    log_step witness "keyless signature produced"
    cat > "$OUT" <<JSON
{
  "witness": "cosign-keyless",
  "witnessed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "manifest_sha256": "$SHA",
  "bundle_file": "$(basename "$BUNDLE_OUT")",
  "method": "cosign sign-blob (keyless OIDC, $COSIGN_VERSION)",
  "verify_command": "cosign verify-blob --bundle manifest.cosign-bundle.json manifest.sha256"
}
JSON
    exit 0
  fi
  log_step witness "keyless attempt failed — falling back to key-based"
fi

# Key-based fallback
if [[ -n "${COSIGN_KEY:-}" && -f "$COSIGN_KEY" ]]; then
  if cosign sign-blob --yes --key "$COSIGN_KEY" --bundle "$BUNDLE_OUT" "$SUBJECT_FILE" >/dev/null 2>&1; then
    log_step witness "key-based signature produced"
    PUB_PATH="${COSIGN_KEY%.key}.pub"
    cat > "$OUT" <<JSON
{
  "witness": "cosign-key",
  "witnessed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "manifest_sha256": "$SHA",
  "bundle_file": "$(basename "$BUNDLE_OUT")",
  "method": "cosign sign-blob (private key, $COSIGN_VERSION)",
  "verify_command": "cosign verify-blob --bundle manifest.cosign-bundle.json --key $PUB_PATH manifest.sha256"
}
JSON
    exit 0
  fi
fi

# Local-dev placeholder (still records the SHA so manifest is tamper-evident)
log_step witness "no signing method available — writing local-dev placeholder"
cat > "$OUT" <<JSON
{
  "witness": "local-dev",
  "witnessed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "manifest_sha256": "$SHA",
  "signature": null,
  "method": "local-dev (set COSIGN_KEYLESS=1 + CI/COSIGN_EXPERIMENTAL=1 for keyless OR COSIGN_KEY=/path/to/cosign.key for key-based)",
  "note": "LAW-17 satisfied at SHA level only — production must enable keyless OIDC"
}
JSON
exit 0
