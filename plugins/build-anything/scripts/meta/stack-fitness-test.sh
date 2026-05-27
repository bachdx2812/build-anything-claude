#!/usr/bin/env bash
# stack-fitness-test.sh — meta-gate for GATE-STACK (v8.4 Stage 1.D).
#
# Asserts the stack-fitness gate correctly:
#   1. FAILs when a "serious" product type (youtube-clone) is paired with a
#      toy stack (sqlite + multer + no transcode/cdn/streaming).
#   2. PASSes when the same product is paired with an honest stack
#      (postgres + s3 + ffmpeg-worker + cloudfront + hls).
#   3. PASSes (trivially) when product type has empty required_capabilities
#      (todo-app).
#   4. Returns N/A_PENDING_REVIEWER for a product type not in the catalog.
#   5. Resolves fuzzy product names (youtube-clone-mvp → youtube-clone).
#
# Why this exists: GATE-STACK is the v8.4 fix for the v8.3 audit finding
# where a youtube-clone shipped on better-sqlite3+multer and every downstream
# gate passed because the upload pipeline was stubbed. Without this regression,
# a future skill edit could silently break the disqualification logic and the
# whole hardening collapses back to "tests stubbed, manifest sealed, product
# unshippable". LAW-F6 generalised to the skill itself.
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE_SCRIPT="$SKILL_ROOT/scripts/spec/stack-fitness-check.sh"
CATALOG="$SKILL_ROOT/scripts/spec/feature-catalog.json"

OUT_BASE="$(mktemp -d -t stack-fit-meta-XXXXXX)"
SUMMARY="$OUT_BASE/summary.json"
declare -a CASES_PASSED CASES_FAILED

log() { echo "[meta:stack-fit] $*" >&2; }

if [[ ! -x "$GATE_SCRIPT" ]]; then
  log "FATAL: gate script not executable: $GATE_SCRIPT"
  exit 2
fi
if [[ ! -f "$CATALOG" ]]; then
  log "FATAL: catalog missing: $CATALOG"
  exit 2
fi

# ── Build a fixture ────────────────────────────────────────────────
# $1 case name, $2 product_type, $3 config json, $4 package.json contents (or "")
mk_case() {
  local name="$1" pt="$2" cfg="$3" pkg="$4"
  local case_dir="$OUT_BASE/$name"
  local atom_dir="$case_dir/atom"
  mkdir -p "$atom_dir/intent" "$atom_dir/gate-spec"
  cat > "$atom_dir/intent/verdict.json" <<EOF
{ "declared": { "product_type": "$pt" }, "next_action": "READY", "confidence": 100 }
EOF
  printf '%s' "$cfg" > "$case_dir/.build-anything.json"
  if [[ -n "$pkg" ]]; then
    printf '%s' "$pkg" > "$case_dir/package.json"
  fi
  echo "$case_dir"
}

# v8.5: case with scale_tier + cost in intent
# $1 name, $2 pt, $3 tier, $4 cost_ceiling, $5 cfg, $6 pkg
mk_case_v85() {
  local name="$1" pt="$2" tier="$3" cost="$4" cfg="$5" pkg="$6"
  local case_dir="$OUT_BASE/$name"
  local atom_dir="$case_dir/atom"
  mkdir -p "$atom_dir/intent" "$atom_dir/gate-spec"
  cat > "$atom_dir/intent/verdict.json" <<EOF
{
  "declared": {
    "product_type": "$pt",
    "scale_tier": "$tier",
    "cost": { "monthly_usd_ceiling": $cost, "currency": "USD" }
  },
  "next_action": "READY",
  "confidence": 100
}
EOF
  printf '%s' "$cfg" > "$case_dir/.build-anything.json"
  if [[ -n "$pkg" ]]; then
    printf '%s' "$pkg" > "$case_dir/package.json"
  fi
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

  local verdict_file="$atom_dir/gate-spec/stack-fitness.json"
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

# ── Case 1: serious product on toy stack → FAIL ────────────────────
TOY_CFG='{
  "scope": { "mode": "atom_on_existing", "paths": [], "bootstrap_glob": ["src"] },
  "stack": {
    "lang": "node",
    "database": "sqlite",
    "media_storage": "local-disk"
  }
}'
TOY_PKG='{
  "name": "yt-toy",
  "dependencies": {
    "express": "^4",
    "better-sqlite3": "^11",
    "multer": "^1"
  }
}'
CD=$(mk_case "1_toy_serious" "youtube-clone" "$TOY_CFG" "$TOY_PKG")
run_case "1_toy_serious" "$CD" "FAIL" "1"

# ── Case 2: serious product on honest stack → PASS ─────────────────
HONEST_CFG='{
  "scope": { "mode": "atom_on_existing", "paths": [], "bootstrap_glob": ["src"] },
  "stack": {
    "lang": "node",
    "database": "postgres",
    "media_storage": "s3",
    "transcode": "ffmpeg-worker",
    "cdn": "cloudfront",
    "streaming_protocol": "hls"
  }
}'
HONEST_PKG='{
  "name": "yt-honest",
  "dependencies": {
    "express": "^4",
    "pg": "^8",
    "@aws-sdk/client-s3": "^3",
    "aws-cloudfront-sign": "^3"
  }
}'
CD=$(mk_case "2_honest_serious" "youtube-clone" "$HONEST_CFG" "$HONEST_PKG")
run_case "2_honest_serious" "$CD" "PASS" "0"

# ── Case 3: trivial product (todo-app) → PASS regardless of stack ──
TRIVIAL_CFG='{
  "scope": { "mode": "atom_on_existing", "paths": [], "bootstrap_glob": ["src"] },
  "stack": { "lang": "node", "database": "sqlite" }
}'
CD=$(mk_case "3_trivial" "todo-app" "$TRIVIAL_CFG" "")
run_case "3_trivial" "$CD" "PASS" "0"

# ── Case 4: novel product (not in catalog) → N/A_PENDING_REVIEWER ──
NOVEL_CFG='{
  "scope": { "mode": "atom_on_existing", "paths": [], "bootstrap_glob": ["src"] },
  "stack": { "lang": "node" }
}'
CD=$(mk_case "4_novel" "quantum-llama-bistro-saas" "$NOVEL_CFG" "")
run_case "4_novel" "$CD" "N/A_PENDING_REVIEWER" "0"

# ── Case 5: fuzzy match (youtube-clone-mvp → youtube-clone) → FAIL on toy ──
CD=$(mk_case "5_fuzzy_suffix" "youtube-clone-mvp" "$TOY_CFG" "$TOY_PKG")
run_case "5_fuzzy_suffix" "$CD" "FAIL" "1"

# ── v8.5: tier-aware fixtures ──────────────────────────────────────

# Stack honest enough to satisfy growth-tier youtube-clone capabilities.
GROWTH_FULL_CFG='{
  "scope": { "mode": "atom_on_existing", "bootstrap_glob": ["src"] },
  "stack": {
    "database": "postgres",
    "media_storage": "s3",
    "transcode": "ffmpeg-worker",
    "cdn": "cloudfront",
    "streaming_protocol": "hls",
    "cache": "redis"
  }
}'
GROWTH_FULL_PKG='{"dependencies": {"pg": "^8", "ioredis": "^5"}}'

# ── Case 6: v8.5 growth-tier match with ok cost → PASS ─────────────
CD=$(mk_case_v85 "6_v85_growth_ok" "youtube-clone" "growth" 1500 "$GROWTH_FULL_CFG" "$GROWTH_FULL_PKG")
run_case "6_v85_growth_ok" "$CD" "PASS" "0"

# ── Case 7: growth-tier stack but cost ceiling under tier min → FAIL ──
CD=$(mk_case_v85 "7_v85_cost_underbudget" "youtube-clone" "growth" 50 "$GROWTH_FULL_CFG" "$GROWTH_FULL_PKG")
run_case "7_v85_cost_underbudget" "$CD" "FAIL" "1"

# ── Case 8: scale-tier with tier-disqualified package present → FAIL ──
SCALE_CFG='{
  "scope": { "mode": "atom_on_existing", "bootstrap_glob": ["src"] },
  "stack": {
    "database": "postgres",
    "media_storage": "s3",
    "transcode": "ffmpeg-worker",
    "cdn": "cloudfront",
    "streaming_protocol": "hls",
    "cache": "redis",
    "search": "elasticsearch",
    "image_pipeline": "sharp+queue"
  }
}'
SCALE_PKG='{"dependencies": {"pg": "^8", "cloudinary-all-in-one": "^1.0"}}'
CD=$(mk_case_v85 "8_v85_tier_disqualified_pkg" "youtube-clone" "scale" 10000 "$SCALE_CFG" "$SCALE_PKG")
run_case "8_v85_tier_disqualified_pkg" "$CD" "FAIL" "1"

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
    meta_gate: "stack-fitness-test",
    schema_version: "ubs-v8.5-meta",
    timestamp: $ts,
    cases_total: $total,
    cases_pass: $pass,
    cases_fail: $fail,
    cases_passed: $passed,
    cases_failed: $failed,
    verdict: (if $fail == 0 then "PASS" else "FAIL" end),
    interpretation: (if $fail == 0
      then "GATE-STACK correctly disqualifies toy stacks and passes honest ones — v8.4 invariant holds"
      else "GATE-STACK regressed — one or more fixtures returned unexpected verdict"
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
