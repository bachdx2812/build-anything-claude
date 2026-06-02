#!/usr/bin/env bash
# e2e-semantic-floor-check.sh — Stage 5 GATE-E2E-SEM (v8.8)
#
# Catches the audit's §11.1 / §16.4 class: E2E "passed" but proved nothing.
#   §11.1  Playwright tests ran green against STUBS — the suite booted, every
#          spec passed, yet nothing real was asserted.
#   §16.4  A tautology slipped through — e.g. `expect(url).toBe(sameUrl)` is
#          trivially true and asserts no product behaviour. Journeys were
#          "covered" by filename match alone; the body asserted nothing
#          specific to the journey.
#
# GATE-25-E2E (e2e-playwright.sh) BOOTS the stack and runs Playwright — it
# proves the suite is GREEN. It cannot prove the suite is MEANINGFUL: a green
# tautology still passes. This gate is the static complement. It NEVER boots
# anything (no node, no playwright, pure grep) so it stays meta-testable on a
# bare runner. It confronts each DECLARED journey with its test file(s) and
# FAILs when a journey asserts nothing specific:
#   FINDING-NO-SEMANTIC  — journey declares zero semantic_assertions[]
#                          (tautology risk: nothing specific is required).
#   FINDING-NO-FILE      — journey has no matching test file under e2e.root.
#   FINDING-MISSING-ASRT — a declared semantic assertion string is absent from
#                          the journey's matched test file(s).
#   FINDING-NO-KEYWORD   — the matched test file(s) carry no assertion keyword
#                          at all (expect(|assert|.should|toBe|...): a body that
#                          executes but never asserts is a tautology.
#
# Inputs (.build-anything.json):
#   project_type            (frontend | mixed | ... — gate only triggers on UI)
#   e2e.enabled             (bool)
#   e2e.root                (default "tests/e2e")
#   e2e.journeys[]          [{name, semantic_assertions:[ "<substring>", ... ]}]
#
# Trigger / N/A (LAW-F6 — never silent PASS):
#   e2e.enabled != true OR project_type ∉ {frontend,mixed} OR no journeys
#     → N/A_PENDING_REVIEWER.
#   e2e.root dir missing (declared journeys, no tests) → FAIL.
# LAW-CL-95: confidence + ambiguities[].

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_common.sh"

ATOM_DIR=""; PROJECT_ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --atom-dir)     ATOM_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done
: "${ATOM_DIR:?--atom-dir required}"
: "${PROJECT_ROOT:=$(pwd)}"
export ATOM_DIR PROJECT_ROOT
CONFIG="$PROJECT_ROOT/.build-anything.json"
OUT="$ATOM_DIR/gate-mechanical/e2e-semantic.json"
mkdir -p "$(dirname "$OUT")"

log() { echo "[$(date -u +%H:%M:%S)] [e2e-sem] $*" >&2; }

emit_na() {
  local reason="$1" rj; rj=$(printf '%s' "$reason" | jq -Rs .)
  cat > "$OUT" <<JSON
{ "gate": "GATE-E2E-SEM", "passed": null, "verdict": "N/A_PENDING_REVIEWER",
  "reason": $rj, "confidence": 0, "ambiguities": [$rj], "review_required": true,
  "schema_version": "ubs-v8.8-e2e-sem", "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)" }
JSON
  exit 0
}
emit_fail() {
  local findings="$1" reason="$2" rj; rj=$(printf '%s' "$reason" | jq -Rs .)
  cat > "$OUT" <<JSON
{ "gate": "GATE-E2E-SEM", "passed": false, "verdict": "FAIL",
  "reason": $rj, "findings": $findings, "confidence": 100, "ambiguities": [],
  "schema_version": "ubs-v8.8-e2e-sem", "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)" }
JSON
  exit 1
}
emit_pass() {
  local verified="$1"
  cat > "$OUT" <<JSON
{ "gate": "GATE-E2E-SEM", "passed": true, "verdict": "PASS",
  "journeys_verified": $verified, "confidence": 100, "ambiguities": [],
  "schema_version": "ubs-v8.8-e2e-sem", "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)" }
JSON
  exit 0
}

# ── Read config (direct jq — no boot, no cfg helper dep) ───────────────
[[ -f "$CONFIG" ]] || emit_na "no .build-anything.json at $CONFIG — nothing to verify (declare e2e.journeys[] with semantic_assertions[])"

PROJECT_TYPE=$(jq -r '.project_type // "backend"' "$CONFIG" 2>/dev/null || echo "backend")
E2E_ENABLED=$(jq -r '.e2e.enabled // false' "$CONFIG" 2>/dev/null || echo "false")

# ── Trigger gate (LAW-F6) ──────────────────────────────────────────────
if [[ "$E2E_ENABLED" != "true" ]]; then
  emit_na "e2e.enabled != true (project_type=$PROJECT_TYPE) — E2E semantic floor not in scope; reviewer must confirm no UI journeys"
fi
case "$PROJECT_TYPE" in
  frontend|mixed) : ;;
  *) emit_na "project_type=$PROJECT_TYPE has no UI surface — E2E semantic floor applies to frontend|mixed only" ;;
esac

JOURNEY_COUNT=$(jq '(.e2e.journeys // []) | length' "$CONFIG" 2>/dev/null || echo 0)
if [[ "$JOURNEY_COUNT" -eq 0 ]]; then
  emit_na "e2e.enabled=true but no e2e.journeys[] declared — nothing to assert against (declare journeys with semantic_assertions[])"
fi

# ── Resolve e2e.root; missing dir with declared journeys = FAIL ────────
E2E_ROOT=$(jq -r '.e2e.root // "tests/e2e"' "$CONFIG" 2>/dev/null || echo "tests/e2e")
[[ "$E2E_ROOT" = /* ]] || E2E_ROOT="$PROJECT_ROOT/$E2E_ROOT"
if [[ ! -d "$E2E_ROOT" ]]; then
  FJSON=$(printf '%s' "e2e.root not found: ${E2E_ROOT#"$PROJECT_ROOT"/} — $JOURNEY_COUNT journey(s) declared but no E2E tests on disk" | jq -R . | jq -s .)
  emit_fail "$FJSON" "declared E2E journeys but e2e.root directory is missing (tests never written)"
fi

# Discover candidate test files once (mirror e2e-playwright.sh discovery set).
TEST_FILES=$(find "$E2E_ROOT" -type f \
  \( -name '*.spec.ts' -o -name '*.spec.js' -o -name '*.test.ts' -o -name '*.test.js' \
     -o -name '*.e2e.ts' -o -name '*.e2e.js' \) 2>/dev/null || true)

# Assertion-keyword regex — a body that asserts SOMETHING (vs a bare tautology
# with no assertion call at all).
ASRT_KEYWORD='expect\(|assert|\.should|toBe|toEqual|toHaveText|toContain|toHaveURL'

# ── Per-journey static verification ────────────────────────────────────
FINDINGS=()
VERIFIED=0
for i in $(seq 0 $((JOURNEY_COUNT - 1))); do
  jname=$(jq -r ".e2e.journeys[$i].name // empty" "$CONFIG" 2>/dev/null || true)
  [[ -z "$jname" ]] && continue
  jslug=$(printf '%s' "$jname" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

  # Locate matching test file(s): filename contains slug OR content mentions name.
  MATCHED=()
  while IFS= read -r tf; do
    [[ -z "$tf" ]] && continue
    base_lc=$(basename "$tf" | tr '[:upper:]' '[:lower:]')
    if printf '%s' "$base_lc" | grep -qF "$jslug" 2>/dev/null; then
      MATCHED+=("$tf"); continue
    fi
    if grep -qiF "$jname" "$tf" 2>/dev/null; then
      MATCHED+=("$tf")
    fi
  done <<< "$TEST_FILES"

  if [[ ${#MATCHED[@]} -eq 0 ]]; then
    FINDINGS+=("journey '$jname' has no matching test file under ${E2E_ROOT#"$PROJECT_ROOT"/}")
    continue
  fi

  # REQUIRE >=1 declared semantic_assertions[] — empty/absent = tautology risk.
  SEM_COUNT=$(jq "(.e2e.journeys[$i].semantic_assertions // []) | length" "$CONFIG" 2>/dev/null || echo 0)
  if [[ "$SEM_COUNT" -eq 0 ]]; then
    FINDINGS+=("journey '$jname' declares no semantic assertion (tautology risk)")
    continue
  fi

  # Each declared assertion substring must appear (grep -F) in matched file(s).
  JOURNEY_OK=1
  while IFS= read -r asrt; do
    [[ -z "$asrt" ]] && continue
    found=0
    for tf in "${MATCHED[@]}"; do
      if grep -qF -- "$asrt" "$tf" 2>/dev/null; then found=1; break; fi
    done
    if [[ "$found" -eq 0 ]]; then
      FINDINGS+=("journey '$jname' test missing assertion: $asrt")
      JOURNEY_OK=0
    fi
  done < <(jq -r ".e2e.journeys[$i].semantic_assertions[]? // empty" "$CONFIG" 2>/dev/null || true)

  # Matched file(s) must carry >=1 generic assertion keyword.
  kw_found=0
  for tf in "${MATCHED[@]}"; do
    if grep -qE "$ASRT_KEYWORD" "$tf" 2>/dev/null; then kw_found=1; break; fi
  done
  if [[ "$kw_found" -eq 0 ]]; then
    FINDINGS+=("journey '$jname' test has no assertion keyword (tautology)")
    JOURNEY_OK=0
  fi

  [[ "$JOURNEY_OK" -eq 1 ]] && VERIFIED=$((VERIFIED + 1))
done

if [[ ${#FINDINGS[@]} -gt 0 ]]; then
  FJSON=$(printf '%s\n' "${FINDINGS[@]}" | jq -R . | jq -s 'map(select(length>0))')
  log "FAIL: ${#FINDINGS[@]} finding(s) across $JOURNEY_COUNT declared journey(s)"
  emit_fail "$FJSON" "declared E2E journey asserts nothing specific (tautology / filename-only coverage)"
fi

log "PASS: $VERIFIED declared journey(s) assert their semantic floor"
emit_pass "$VERIFIED"
