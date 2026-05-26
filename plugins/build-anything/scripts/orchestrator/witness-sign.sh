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
PROJECT_ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --atom-dir)     ATOM_DIR="$2"; shift 2 ;;
    --sha)          SHA="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done
: "${ATOM_DIR:?--atom-dir required}"
: "${SHA:?--sha required (manifest SHA-256)}"
: "${PROJECT_ROOT:=$(pwd)}"

OUT="$ATOM_DIR/witness.json"
SIG_OUT="$ATOM_DIR/manifest.sig"
CERT_OUT="$ATOM_DIR/manifest.cert"
BUNDLE_OUT="$ATOM_DIR/manifest.cosign-bundle.json"
SUBJECT_FILE="$ATOM_DIR/manifest.sha256"

# v8.3 — config-driven signing. Read cosign.signing.{key_path, refuse_placeholder}
# from .build-anything.json. CLI/env vars still work as override.
CFG="$PROJECT_ROOT/.build-anything.json"
CFG_KEY_PATH=""
REFUSE_PLACEHOLDER="false"
if [[ -f "$CFG" ]] && command -v jq >/dev/null 2>&1; then
  CFG_KEY_PATH=$(jq -r '.cosign.signing.key_path // empty' "$CFG" 2>/dev/null || true)
  REFUSE_PLACEHOLDER=$(jq -r '.cosign.signing.refuse_placeholder // false' "$CFG" 2>/dev/null || echo false)
fi
# Config key_path takes precedence over COSIGN_KEY env if both set
[[ -n "$CFG_KEY_PATH" ]] && COSIGN_KEY="$CFG_KEY_PATH"

log_step witness "atom=$ATOM_DIR sha=$SHA refuse_placeholder=$REFUSE_PLACEHOLDER key_path=${COSIGN_KEY:-none}"

if ! command -v cosign >/dev/null 2>&1; then
  if [[ "$REFUSE_PLACEHOLDER" == "true" ]]; then
    log_step witness "FATAL cosign missing AND cosign.signing.refuse_placeholder=true — refusing to seal atom"
    cat > "$OUT" <<JSON
{
  "witness_class": "PLACEHOLDER_REFUSED",
  "witnessed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "manifest_sha256": "$SHA",
  "signature": null,
  "method": "refused",
  "reason": "cosign not installed AND .build-anything.json#cosign.signing.refuse_placeholder=true; install cosign OR set refuse_placeholder=false (dev only) to seal"
}
JSON
    exit 1
  fi
  log_step witness "cosign not installed — writing PLACEHOLDER_NOT_FOR_PROD (LAW-17 gap surfaced)"
  cat > "$OUT" <<JSON
{
  "witness_class": "PLACEHOLDER_NOT_FOR_PROD",
  "witness": "local-placeholder",
  "witnessed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "manifest_sha256": "$SHA",
  "signature": null,
  "certificate": null,
  "method": "none",
  "note": "LAW-17 NOT satisfied — install cosign (brew install cosign) and re-run for keyless OIDC signature. Set cosign.signing.refuse_placeholder=true in .build-anything.json to make this an error."
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
if [[ "$REFUSE_PLACEHOLDER" == "true" ]]; then
  log_step witness "FATAL cosign installed but no signing method available AND refuse_placeholder=true — refusing to seal"
  cat > "$OUT" <<JSON
{
  "witness_class": "PLACEHOLDER_REFUSED",
  "witnessed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "manifest_sha256": "$SHA",
  "signature": null,
  "method": "refused",
  "reason": "no key_path OR keyless-OIDC available AND .build-anything.json#cosign.signing.refuse_placeholder=true; configure cosign.signing.key_path OR enable keyless (CI/COSIGN_EXPERIMENTAL=1) to seal"
}
JSON
  exit 1
fi
log_step witness "no signing method available — writing PLACEHOLDER_NOT_FOR_PROD (local-dev)"
cat > "$OUT" <<JSON
{
  "witness_class": "PLACEHOLDER_NOT_FOR_PROD",
  "witness": "local-dev",
  "witnessed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "manifest_sha256": "$SHA",
  "signature": null,
  "method": "local-dev (set cosign.signing.key_path in .build-anything.json OR COSIGN_KEYLESS=1 + CI/COSIGN_EXPERIMENTAL=1 for keyless OR COSIGN_KEY env for key-based)",
  "note": "LAW-17 satisfied at SHA level only — production MUST enable keyless OIDC OR provide cosign.signing.key_path. Set cosign.signing.refuse_placeholder=true to make this an error."
}
JSON
exit 0
