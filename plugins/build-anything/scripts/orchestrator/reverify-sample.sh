#!/usr/bin/env bash
# reverify-sample.sh — Stage 6 GATE-REVERIFY (v8.8 INDEPENDENT RE-VERIFICATION).
#
# Audit §1 / §16.7 core disease: "the build passes its OWN self-checks." Every
# verdict in manifest.json is SELF-PRODUCED by the same run that built the code —
# evidence is never independently re-executed, so a gate can record passed=true
# on the strength of a stale/cooked/optimistic run and nobody ever reproduces it.
#
# GATE-REVERIFY is the antibody: it takes a SAMPLE of gates the manifest recorded
# as PASS and INDEPENDENTLY RE-RUNS them. If a gate the manifest swore was PASS
# does NOT reproduce on a fresh, separate execution → self-attestation breach →
# FAIL. This is the one gate whose evidence is produced by re-running, not by
# trusting the build's own ledger.
#
# Algorithm:
#   1. Read .build-anything.json#reverify = { gates:[{gate_id,rerun_cmd}], full? }.
#      Absent / empty gates[] → N/A_PENDING_REVIEWER (LAW-F6: nothing declared to
#      re-verify, never a silent PASS).
#   2. Read recorded verdicts from $ATOM_DIR/manifest.json (.gates[id].passed).
#      No manifest → N/A_PENDING_REVIEWER (nothing built/recorded to re-verify yet).
#   3. Tier guard: if intent scale_tier == "hyperscale" AND reverify.full != true
#      AND the declared sample does NOT cover every gate the manifest recorded
#      passed=true → FAIL "sample incomplete" (hyperscale demands full re-verify,
#      a partial sample is an attestation hole).
#   4. For each declared gate: run rerun_cmd from PROJECT_ROOT (exit 0 = reproduces
#      PASS, non-zero = FAIL on re-run). Compare against the manifest's record:
#        - manifest passed==true BUT rerun rc!=0  → BREACH (the core catch).
#        - manifest passed==true AND rerun rc==0  → reproduced (ok).
#        - gate_id absent from manifest           → finding (declared, never recorded).
#   5. Any finding → FAIL (self_attestation_breach=true when a breach occurred).
#      Else PASS with reproduced[].
#
# LAW-CL-95: confidence + ambiguities[] on every verdict.

set -uo pipefail

ATOM_DIR=""
PROJECT_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --atom-dir)     ATOM_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${ATOM_DIR:?--atom-dir required}"
: "${PROJECT_ROOT:?--project-root required}"

CONFIG="$PROJECT_ROOT/.build-anything.json"
MANIFEST="$ATOM_DIR/manifest.json"
OUT="$ATOM_DIR/gate-reverify/reverify.json"
mkdir -p "$(dirname "$OUT")"

log() { echo "[$(date -u +%H:%M:%S)] [reverify] $*" >&2; }

emit_na() {
  local reason="$1" reason_json
  reason_json=$(printf '%s' "$reason" | jq -Rs .)
  cat > "$OUT" <<JSON
{
  "gate": "GATE-REVERIFY",
  "passed": null,
  "verdict": "N/A_PENDING_REVIEWER",
  "reason": $reason_json,
  "confidence": 0,
  "ambiguities": [$reason_json],
  "review_required": true,
  "schema_version": "ubs-v8.8-reverify",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

# emit_fail <findings-json-array> <reproduced-json-array> <breach 0|1> <tier>
emit_fail() {
  local findings="$1" reproduced="$2" breach="$3" tier="$4"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-REVERIFY",
  "passed": false,
  "verdict": "FAIL",
  "reason": "manifest verdicts did not reproduce on independent re-run (self-attestation breach: build trusted its own self-checks)",
  "scale_tier": "$tier",
  "self_attestation_breach": $( [[ "$breach" -eq 1 ]] && echo true || echo false ),
  "findings": $findings,
  "reproduced": $reproduced,
  "confidence": 100,
  "ambiguities": [],
  "schema_version": "ubs-v8.8-reverify",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 1
}

# emit_pass <reproduced-json-array> <tier>
emit_pass() {
  local reproduced="$1" tier="$2"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-REVERIFY",
  "passed": true,
  "verdict": "PASS",
  "scale_tier": "$tier",
  "self_attestation_breach": false,
  "reproduced": $reproduced,
  "confidence": 100,
  "ambiguities": [],
  "schema_version": "ubs-v8.8-reverify",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

# ── LAW-F6: need a reverify config with a non-empty gates[] ─────────────
[[ -f "$CONFIG" ]] || emit_na "no .build-anything.json at $PROJECT_ROOT — nothing declares which gates to independently re-verify"

REVERIFY_COUNT=$(jq -r '(.reverify.gates // []) | length' "$CONFIG" 2>/dev/null || echo 0)
[[ "$REVERIFY_COUNT" =~ ^[0-9]+$ ]] || REVERIFY_COUNT=0
[[ "$REVERIFY_COUNT" -eq 0 ]] && emit_na "reverify.gates absent or empty in .build-anything.json — no gates declared for independent re-verification"

# ── Need a manifest to re-verify AGAINST (the self-produced ledger) ────
[[ -f "$MANIFEST" ]] || emit_na "no manifest.json at $ATOM_DIR — nothing recorded to re-verify yet"

REVERIFY_FULL=$(jq -r '.reverify.full // false' "$CONFIG" 2>/dev/null || echo false)

# ── Resolve declared scale_tier (tier guard) ───────────────────────────
SCALE_TIER=""
if [[ -f "$ATOM_DIR/intent/verdict.json" ]]; then
  SCALE_TIER=$(jq -r '.declared.scale_tier // empty' "$ATOM_DIR/intent/verdict.json" 2>/dev/null || true)
fi
[[ "$SCALE_TIER" == "null" ]] && SCALE_TIER=""

log "reverify gates declared=$REVERIFY_COUNT full=$REVERIFY_FULL scale_tier=${SCALE_TIER:-<unset>}"

# ── Collect declared gate_ids (sample) and the manifest's passed=true set ──
SAMPLE_IDS=()
while IFS= read -r gid; do
  [[ -z "$gid" ]] && continue
  SAMPLE_IDS+=("$gid")
done < <(jq -r '.reverify.gates[].gate_id // empty' "$CONFIG" 2>/dev/null)

PASSED_IDS=()
while IFS= read -r gid; do
  [[ -z "$gid" ]] && continue
  PASSED_IDS+=("$gid")
done < <(jq -r '(.gates // {}) | to_entries[] | select(.value.passed == true) | .key' "$MANIFEST" 2>/dev/null)

# in_list <needle> <haystack...>
in_list() { local x="$1"; shift; local e; for e in "$@"; do [[ "$e" == "$x" ]] && return 0; done; return 1; }

FINDINGS=()
REPRODUCED=()
BREACH=0

# ── Tier guard: hyperscale + not-full + sample misses a passed gate → FAIL ──
if [[ "$SCALE_TIER" == "hyperscale" && "$REVERIFY_FULL" != "true" ]]; then
  MISSING=()
  for pid in "${PASSED_IDS[@]:-}"; do
    [[ -z "$pid" ]] && continue
    if ! in_list "$pid" "${SAMPLE_IDS[@]:-}"; then
      MISSING+=("$pid")
    fi
  done
  if [[ ${#MISSING[@]} -gt 0 ]]; then
    FINDINGS+=("hyperscale requires full re-verify; sample incomplete — uncovered passed gates: ${MISSING[*]}")
    log "tier guard FAIL: hyperscale sample misses ${#MISSING[@]} passed gate(s): ${MISSING[*]}"
  fi
fi

# ── Re-run each declared gate independently from PROJECT_ROOT ───────────
i=0
while [[ "$i" -lt "$REVERIFY_COUNT" ]]; do
  GID=$(jq -r --argjson i "$i" '.reverify.gates[$i].gate_id // empty' "$CONFIG" 2>/dev/null)
  CMD=$(jq -r --argjson i "$i" '.reverify.gates[$i].rerun_cmd // empty' "$CONFIG" 2>/dev/null)
  i=$((i+1))

  if [[ -z "$GID" ]]; then
    FINDINGS+=("reverify entry #$i missing gate_id")
    continue
  fi

  # What did the self-produced manifest record for this gate?
  RECORDED=$(jq -r --arg g "$GID" '.gates[$g].passed // "absent"' "$MANIFEST" 2>/dev/null || echo "absent")

  if [[ "$RECORDED" == "absent" || "$RECORDED" == "null" ]]; then
    FINDINGS+=("$GID: declared for reverify but absent from manifest")
    log "$GID: declared for reverify but absent from manifest"
    continue
  fi

  if [[ -z "$CMD" ]]; then
    FINDINGS+=("$GID: reverify entry missing rerun_cmd")
    continue
  fi

  # Independent re-execution. exit 0 = reproduces PASS, non-zero = FAIL on re-run.
  log "re-running $GID (recorded passed=$RECORDED): $CMD"
  set +e
  ( cd "$PROJECT_ROOT" && eval "$CMD" ) >/dev/null 2>&1
  RC=$?
  set -e 2>/dev/null || true

  if [[ "$RECORDED" == "true" ]]; then
    if [[ "$RC" -ne 0 ]]; then
      # THE CORE CATCH: manifest swore PASS, independent re-run says otherwise.
      FINDINGS+=("$GID: manifest says PASS but independent re-run FAILED (self-attestation breach)")
      BREACH=1
      log "BREACH $GID: manifest PASS but rerun rc=$RC"
    else
      REPRODUCED+=("$GID (manifest PASS reproduced; rerun rc=0)")
      log "$GID reproduced (rc=0)"
    fi
  else
    # Manifest recorded NOT-pass (false). Re-verification of PASS claims is the
    # job; a recorded non-PASS is not a breach regardless of re-run outcome.
    REPRODUCED+=("$GID (manifest recorded passed=$RECORDED; not a PASS claim — re-run rc=$RC, informational)")
    log "$GID recorded passed=$RECORDED (not a PASS claim); rerun rc=$RC informational"
  fi
done

# ── Render JSON arrays (bash 3.2 safe) ─────────────────────────────────
FINDINGS_JSON=$(printf '%s\n' "${FINDINGS[@]:-}" | jq -R . | jq -s 'map(select(length>0))')
REPRODUCED_JSON=$(printf '%s\n' "${REPRODUCED[@]:-}" | jq -R . | jq -s 'map(select(length>0))')

if [[ ${#FINDINGS[@]} -gt 0 ]]; then
  log "FAIL: findings=${#FINDINGS[@]} breach=$BREACH reproduced=${#REPRODUCED[@]}"
  emit_fail "$FINDINGS_JSON" "$REPRODUCED_JSON" "$BREACH" "${SCALE_TIER:-}"
fi

log "PASS: reproduced=${#REPRODUCED[@]} (no self-attestation breach)"
emit_pass "$REPRODUCED_JSON" "${SCALE_TIER:-}"
