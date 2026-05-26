#!/usr/bin/env bash
# verify-manifest.sh — LAW-17 evidence manifest verification.
# Re-hashes every artifact in manifest.json, compares to stored sha256.
# Then re-hashes the manifest.json itself and compares to manifest.sha256.
# Exits 0 on full PASS, 1 on any mismatch.

set -euo pipefail

ATOM_PATH="${1:-}"
[[ -z "$ATOM_PATH" ]] && { echo "usage: verify-manifest.sh <atom_dir>" >&2; exit 2; }
[[ ! -d "$ATOM_PATH" ]] && { echo "FATAL: $ATOM_PATH is not a directory" >&2; exit 2; }

MANIFEST="$ATOM_PATH/manifest.json"
MANIFEST_HASH_FILE="$ATOM_PATH/manifest.sha256"
[[ ! -f "$MANIFEST" ]] && { echo "FATAL: manifest.json not found at $MANIFEST" >&2; exit 2; }
[[ ! -f "$MANIFEST_HASH_FILE" ]] && { echo "FATAL: manifest.sha256 not found" >&2; exit 2; }

echo "verify-manifest: $(basename "$ATOM_PATH")"

# Step 1 — verify each artifact in manifest matches its recorded sha
ART_FAIL=0
ART_TOTAL=0
while IFS=$'\t' read -r REL_PATH REC_SHA; do
  ART_TOTAL=$((ART_TOTAL+1))
  ABS="$ATOM_PATH/$REL_PATH"
  if [[ ! -f "$ABS" ]]; then
    echo "  $REL_PATH: FAIL (file missing)"
    ART_FAIL=$((ART_FAIL+1)); continue
  fi
  ACTUAL=$(shasum -a 256 "$ABS" 2>/dev/null | awk '{print $1}')
  if [[ "$ACTUAL" == "$REC_SHA" ]]; then
    echo "  $REL_PATH: PASS"
  else
    echo "  $REL_PATH: FAIL (sha mismatch: expected $REC_SHA got $ACTUAL)"
    ART_FAIL=$((ART_FAIL+1))
  fi
done < <( jq -r '.artifacts[] | [.path, .sha256] | @tsv' "$MANIFEST" )

# Step 2 — verify the manifest.json itself
REC_MANIFEST_SHA=$(cat "$MANIFEST_HASH_FILE" | tr -d '[:space:]')
ACTUAL_MANIFEST_SHA=$(shasum -a 256 "$MANIFEST" | awk '{print $1}')
if [[ "$REC_MANIFEST_SHA" == "$ACTUAL_MANIFEST_SHA" ]]; then
  echo "  manifest_sha256: PASS"
  MANIFEST_FAIL=0
else
  echo "  manifest_sha256: FAIL (expected $REC_MANIFEST_SHA got $ACTUAL_MANIFEST_SHA)"
  MANIFEST_FAIL=1
fi

# F5 fix — external witness check. manifest.sha256 self-signed = forgeable.
# Witness sources accepted (any one):
#   1. git notes --ref=ubs-evidence containing the manifest sha (signed by reviewer key)
#   2. .witness.txt with externally-provided signature of manifest sha
# Without a witness, manifest is "self-signed only" — flag CRITICAL.
WITNESS_OK=false
WITNESS_KIND="none"
if command -v git >/dev/null 2>&1 && ( cd "$ATOM_PATH" && git rev-parse --git-dir >/dev/null 2>&1 ); then
  NOTE=$( cd "$ATOM_PATH" && git notes --ref=ubs-evidence show HEAD 2>/dev/null || true )
  if [[ -n "$NOTE" ]] && echo "$NOTE" | grep -q "$ACTUAL_MANIFEST_SHA"; then
    WITNESS_OK=true; WITNESS_KIND="git-note"
  fi
fi
if [[ -f "$ATOM_PATH/.witness.txt" ]] && grep -q "$ACTUAL_MANIFEST_SHA" "$ATOM_PATH/.witness.txt"; then
  WITNESS_OK=true; WITNESS_KIND="external-file"
fi

if [[ "$WITNESS_OK" == "true" ]]; then
  echo "  witness: PASS ($WITNESS_KIND)"
  WITNESS_FAIL=0
else
  echo "  witness: FAIL (LAW-17 F5 — manifest.sha256 is self-signed only; no external attestation)"
  echo "  fix: write the manifest sha to a signed git note OR a .witness.txt file produced by a different actor"
  WITNESS_FAIL=1
fi

echo ""
if [[ "$ART_FAIL" -eq 0 && "$MANIFEST_FAIL" -eq 0 && "$WITNESS_FAIL" -eq 0 ]]; then
  echo "RESULT: PASS — manifest intact + externally witnessed ($ART_TOTAL artifacts, witness=$WITNESS_KIND)"
  exit 0
else
  echo "RESULT: FAIL — artifacts=$ART_FAIL/$ART_TOTAL seal=$([ $MANIFEST_FAIL -eq 0 ] && echo OK || echo BROKEN) witness=$([ $WITNESS_FAIL -eq 0 ] && echo OK || echo MISSING)"
  echo "RESULT: LAW-17 violation — atom retroactively HALT; actor AL demote to 0"
  exit 1
fi
