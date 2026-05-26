#!/usr/bin/env bash
# bmad-prd-test.sh — meta-gate for GATE-PRD (Stage 1.B BMAD-method).
#
# Asserts the bmad-prd gate correctly:
#   1. FAILs when no PRD artefacts exist (empty atom).
#   2. PASSes single-persona when only prd.md exists with all required
#      sections having body lines (Vision, MVP Scope, Acceptance Criteria).
#   3. PASSes multi-persona when prd.md + architecture.md + ux-spec.md
#      all exist with required sections + body.
#   4. FAILs when a required section is a stub (header present, no body)
#      — LAW-F6 vacuous-PASS guard at the artefact level.
#   5. FAILs multi-persona when prd.md OK but architecture.md missing the
#      "Data model" section body.
#
# Why this exists: Stage 1.B is where v8.2 grew BMAD multi-persona coverage.
# The v8.4 correction pivoted from `npx bmad-method run` (nonexistent) to
# method-not-invocation: persona prompts under references/personas/ +
# Task-tool dispatch. The gate is the only thing that verifies the dispatch
# actually produced artefacts. Without this regression, a future skill edit
# could relax the section-body check and the whole multi-persona discipline
# collapses to "header-only stubs accepted".
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE_SCRIPT="$SKILL_ROOT/scripts/spec/bmad-prd-gate.sh"

OUT_BASE="$(mktemp -d -t bmad-prd-meta-XXXXXX)"
SUMMARY="$OUT_BASE/summary.json"
declare -a CASES_PASSED CASES_FAILED

log() { echo "[meta:bmad-prd] $*" >&2; }

if [[ ! -x "$GATE_SCRIPT" ]]; then
  log "FATAL: gate script not executable: $GATE_SCRIPT"
  exit 2
fi

mk_atom() {
  local name="$1"
  local atom_dir="$OUT_BASE/$name/atom"
  mkdir -p "$atom_dir/intent" "$atom_dir/gate-spec"
  cat > "$atom_dir/intent/verdict.json" <<EOF
{ "declared": { "product_type": "todo-app" }, "next_action": "READY", "confidence": 100 }
EOF
  echo "$atom_dir"
}

run_case() {
  local name="$1" atom_dir="$2" expected_verdict="$3" expected_rc="$4"
  log "case=$name expect=verdict:$expected_verdict rc:$expected_rc"

  set +e
  bash "$GATE_SCRIPT" --atom-dir "$atom_dir" --project-root "$(dirname "$atom_dir")" \
    >"$atom_dir/stdout" 2>"$atom_dir/stderr"
  local actual_rc=$?
  set -e

  local verdict_file="$atom_dir/gate-spec/bmad-prd.json"
  if [[ ! -f "$verdict_file" ]]; then
    log "  -> FAIL: no verdict file emitted"
    CASES_FAILED+=("$name(no-verdict-file)")
    return
  fi

  local actual_verdict
  actual_verdict=$(jq -r '.verdict' "$verdict_file" 2>/dev/null)

  if [[ "$actual_verdict" == "$expected_verdict" && "$actual_rc" == "$expected_rc" ]]; then
    log "  -> PASS"
    CASES_PASSED+=("$name")
  else
    log "  -> FAIL: got verdict=$actual_verdict rc=$actual_rc"
    log "       file: $verdict_file"
    jq -c '.' "$verdict_file" 2>/dev/null | sed 's/^/         /' >&2 || true
    CASES_FAILED+=("$name(verdict=$actual_verdict,rc=$actual_rc)")
  fi
}

# ── Case 1: empty atom → FAIL ───────────────────────────────────────
ATOM=$(mk_atom "1_empty")
run_case "1_empty" "$ATOM" "FAIL" "1"

# ── Case 2: single-persona PRD complete → PASS ──────────────────────
ATOM=$(mk_atom "2_single_ok")
cat > "$ATOM/prd.md" <<'MD'
# PRD — todo demo

## Vision
A minimal todo app for one user. Local only.

## MVP Scope
1. Add todo, mark done, delete.

## Acceptance Criteria
- POST /todos returns 201
- DELETE /todos/:id returns 204
MD
run_case "2_single_ok" "$ATOM" "PASS" "0"

# ── Case 3: multi-persona all three artefacts complete → PASS ───────
ATOM=$(mk_atom "3_multi_ok")
cat > "$ATOM/prd.md" <<'MD'
# PRD — youtube-clone-mvp

## Vision
Upload and stream short videos.

## MVP Scope
1. Upload video (research:product-features-youtube-clone.md L42)
2. Play video stream

## Acceptance Criteria
- POST /videos returns 202 with upload URL
- GET /videos/:id returns HLS manifest
MD
cat > "$ATOM/architecture.md" <<'MD'
# Architecture — youtube-clone-mvp

## Stack
language: node
database: postgres
media_storage: s3
transcode: ffmpeg-worker

## Components
1. api (node) — request routing
2. transcoder (ffmpeg-worker) — async transcode

## Data model
video(id PK, uploader_id, status, hls_manifest_url)
MD
cat > "$ATOM/ux-spec.md" <<'MD'
# UX — youtube-clone-mvp

## Page inventory
1. /upload — purpose: file pick + submit, journey J-01
2. /watch/:id — purpose: player, journey J-02

## Per-page UX
### /upload
- empty: drop-zone with hint
- loading: progress bar
- error: inline retry
- success: redirect to /watch/:id

## Accessibility
- keyboard: tab order upload-area → submit
- focus: returns to drop-zone on error
- contrast: WCAG-AA on all CTAs
MD
run_case "3_multi_ok" "$ATOM" "PASS" "0"

# ── Case 4: stub section (header but no body) → FAIL ────────────────
ATOM=$(mk_atom "4_stub_section")
cat > "$ATOM/prd.md" <<'MD'
# PRD — stub

## Vision
Real vision body line.

## MVP Scope

## Acceptance Criteria
- HTTP 200 on /
MD
run_case "4_stub_section" "$ATOM" "FAIL" "1"

# ── Case 5: multi-persona, arch missing Data model body → FAIL ─────
ATOM=$(mk_atom "5_arch_incomplete")
cat > "$ATOM/prd.md" <<'MD'
# PRD — partial

## Vision
v
## MVP Scope
m
## Acceptance Criteria
a
MD
cat > "$ATOM/architecture.md" <<'MD'
# Architecture — partial

## Stack
language: node

## Components
1. api

## Data model
MD
cat > "$ATOM/ux-spec.md" <<'MD'
# UX — partial

## Page inventory
1. /

## Per-page UX
### /
- empty: hello

## Accessibility
- keyboard nav present
MD
run_case "5_arch_incomplete" "$ATOM" "FAIL" "1"

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
    meta_gate: "bmad-prd-test",
    schema_version: "ubs-v8.4-meta",
    timestamp: $ts,
    cases_total: $total,
    cases_pass: $pass,
    cases_fail: $fail,
    cases_passed: $passed,
    cases_failed: $failed,
    verdict: (if $fail == 0 then "PASS" else "FAIL" end),
    interpretation: (if $fail == 0
      then "GATE-PRD correctly enforces BMAD-method artefact body presence — v8.4 invariant holds"
      else "GATE-PRD regressed — one or more fixtures returned unexpected verdict"
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
