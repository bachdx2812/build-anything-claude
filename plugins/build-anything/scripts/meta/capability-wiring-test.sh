#!/usr/bin/env bash
# capability-wiring-test.sh — meta-gate for GATE-WIRE-STACK (v8.8 Stage 1.D).
#
# Asserts the capability-wiring gate correctly distinguishes DECLARED from WIRED:
#   1. FAIL  — repo HAS a surface (package.json + source) but the declared
#              capabilities leave NO footprint (the mandarin/§6 shape: stack
#              declared honest, internal/ai empty, no SDK in deps).
#   2. PASS  — every required capability has a real dependency/source footprint.
#   3. PASS  — trivial product (todo-app) with no required capabilities.
#   4. N/A   — no dependency manifest AND no source at all (Stage 4 not reached);
#              the gate must NOT FAIL a build that never produced a wiring surface.
#
# Why this exists: GATE-STACK (text) passed the mandarin build while
# internal/ai/ was empty and no AI SDK was in go.mod. GATE-WIRE-STACK is the
# v8.8 fix. Without this regression a future edit could collapse wiring back to
# a declaration check and the audit's core finding would silently return.
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE_SCRIPT="$SKILL_ROOT/scripts/spec/capability-wiring-check.sh"

OUT_BASE="$(mktemp -d -t cap-wire-meta-XXXXXX)"
declare -a CASES_PASSED CASES_FAILED

log() { echo "[meta:cap-wire] $*" >&2; }

[[ -f "$GATE_SCRIPT" ]] || { log "FATAL: gate script missing: $GATE_SCRIPT"; exit 2; }

# setup <name> <product_type> <config-json> → echoes case_dir (with intent + config)
setup() {
  local name="$1" pt="$2" cfg="$3"
  local case_dir="$OUT_BASE/$name"
  local atom_dir="$case_dir/atom"
  mkdir -p "$atom_dir/intent" "$atom_dir/gate-spec"
  cat > "$atom_dir/intent/verdict.json" <<EOF
{ "declared": { "product_type": "$pt" }, "next_action": "READY", "confidence": 100 }
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
  local verdict_file="$atom_dir/gate-spec/capability-wiring.json"
  if [[ ! -f "$verdict_file" ]]; then
    log "  -> FAIL: no verdict file"; CASES_FAILED+=("$name(no-verdict)"); return
  fi
  local actual_verdict
  actual_verdict=$(jq -r '.verdict' "$verdict_file" 2>/dev/null)
  if [[ "$actual_verdict" == "$expected_verdict" && "$actual_rc" == "$expected_rc" ]]; then
    log "  -> PASS"; CASES_PASSED+=("$name")
  else
    log "  -> FAIL: got verdict=$actual_verdict rc=$actual_rc"
    jq -c '{verdict,unwired_capabilities,wired_capabilities,reason}' "$verdict_file" 2>/dev/null | sed 's/^/       /' >&2 || true
    CASES_FAILED+=("$name(verdict=$actual_verdict,rc=$actual_rc)")
  fi
}

# Honest declaration — GATE-STACK would PASS this; the question is whether it's WIRED.
YT_CFG='{
  "scope": { "mode": "atom_on_existing", "bootstrap_glob": ["src"] },
  "stack": {
    "media_storage": "s3",
    "transcode": "ffmpeg-worker",
    "cdn": "cloudfront",
    "streaming_protocol": "hls",
    "database": "postgres"
  }
}'

# ── Case 1: declared-but-NOT-wired → FAIL (the §6 mandarin shape) ──────
CD=$(setup "1_declared_not_wired" "youtube-clone" "$YT_CFG")
printf '%s' '{"name":"yt","dependencies":{"express":"^4"}}' > "$CD/package.json"
mkdir -p "$CD/src"
printf '%s\n' 'console.log("hello world")' > "$CD/src/app.js"
run_case "1_declared_not_wired" "$CD" "FAIL" "1"

# ── Case 2: fully wired → PASS ─────────────────────────────────────────
CD=$(setup "2_fully_wired" "youtube-clone" "$YT_CFG")
printf '%s' '{"name":"yt","dependencies":{"@aws-sdk/client-s3":"^3","bullmq":"^5","pg":"^8","aws-cloudfront-sign":"^3"}}' > "$CD/package.json"
mkdir -p "$CD/src"
printf '%s\n' 'import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";' > "$CD/src/storage.js"
printf '%s\n' 'import { Queue } from "bullmq"; // transcode_worker queue' > "$CD/src/queue.js"
printf '%s\n' 'const dsn = "postgres://localhost:5432/app"; // postgresql writer' > "$CD/src/db.js"
printf '%s\n' 'const cdnBase = "https://d111.cloudfront.net";' > "$CD/src/cdn.js"
printf '%s\n' 'const master = "stream/master.m3u8"; // hls playlist' > "$CD/src/stream.js"
run_case "2_fully_wired" "$CD" "PASS" "0"

# ── Case 3: trivial product (no required caps) → PASS ──────────────────
CD=$(setup "3_trivial_todo" "todo-app" '{"scope":{"bootstrap_glob":["src"]},"stack":{"database":"sqlite"}}')
printf '%s' '{"name":"todo","dependencies":{"express":"^4"}}' > "$CD/package.json"
run_case "3_trivial_todo" "$CD" "PASS" "0"

# ── Case 4: no wiring surface (Stage 4 not reached) → N/A, not FAIL ────
CD=$(setup "4_no_surface" "youtube-clone" "$YT_CFG")
run_case "4_no_surface" "$CD" "N/A_PENDING_REVIEWER" "0"

# ── Case 5: ai-app hyperscale, multi-provider AI DECLARED but UNWIRED → FAIL ──
# This is the exact mandarin §16.1 shape: multi_provider_ai declared, internal/ai
# empty, zero SDKs. GATE-STACK (text) would pass the declaration; WIRE-STACK FAILs.
AI_CFG='{
  "scope": { "mode": "atom_on_existing", "bootstrap_glob": ["src"] },
  "stack": { "ai": "openai", "database": "postgres", "cache": "redis", "queue": "bullmq" },
  "ai": { "providers": "openai+anthropic" }
}'
CD=$(setup "5_ai_multi_unwired" "ai-app" "$AI_CFG")
cat > "$CD/atom/intent/verdict.json" <<'EOF'
{ "declared": { "product_type": "ai-app", "scale_tier": "hyperscale" }, "next_action": "READY", "confidence": 100 }
EOF
printf '%s' '{"name":"ai","dependencies":{"express":"^4"}}' > "$CD/package.json"
mkdir -p "$CD/src"; printf '%s\n' 'console.log("hello")' > "$CD/src/app.js"
run_case "5_ai_multi_unwired" "$CD" "FAIL" "1"

# ── Case 6: ai-app hyperscale, fully wired incl 2 AI providers → PASS ──
CD=$(setup "6_ai_multi_wired" "ai-app" "$AI_CFG")
cat > "$CD/atom/intent/verdict.json" <<'EOF'
{ "declared": { "product_type": "ai-app", "scale_tier": "hyperscale" }, "next_action": "READY", "confidence": 100 }
EOF
printf '%s' '{"name":"ai","dependencies":{"openai":"^4","@anthropic-ai/sdk":"^0.27","pg":"^8","ioredis":"^5","bullmq":"^5"}}' > "$CD/package.json"
mkdir -p "$CD/src"
printf '%s\n' 'import OpenAI from "openai"; const c = new OpenAI(); export const a = (m) => c.chat.completions.create({messages:m});' > "$CD/src/openai.js"
printf '%s\n' 'import Anthropic from "@anthropic-ai/sdk"; const x = new Anthropic(); export const b = (m) => x.messages.create(m);' > "$CD/src/anthropic.js"
printf '%s\n' 'export class Provider {} export const fallback = [a, b]; // provider fallback chain' > "$CD/src/provider.js"
printf '%s\n' 'const dsn = "postgres://localhost:5432/app"; // postgresql writer' > "$CD/src/db.js"
printf '%s\n' 'import { Queue } from "bullmq"; const redisUrl = "redis://localhost"; // fanout + cache' > "$CD/src/queue.js"
run_case "6_ai_multi_wired" "$CD" "PASS" "0"

# ── Aggregate ──────────────────────────────────────────────────────────
if [[ ${#CASES_FAILED[@]} -gt 0 ]]; then
  log "FAILED cases:"; for c in "${CASES_FAILED[@]}"; do log "  - $c"; done
  log "summary: pass=${#CASES_PASSED[@]} fail=${#CASES_FAILED[@]} verdict=FAIL"
  exit 1
fi
log "summary: pass=${#CASES_PASSED[@]} fail=0 verdict=PASS"
exit 0
