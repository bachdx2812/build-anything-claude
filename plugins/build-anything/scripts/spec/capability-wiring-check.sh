#!/usr/bin/env bash
# capability-wiring-check.sh — Stage 1.D GATE-WIRE-STACK (v8.8)
#
# Sibling of stack-fitness-check.sh (GATE-STACK). GATE-STACK asks "is the
# declared stack value in accept_values?" — a TEXT check on the declaration.
# GATE-WIRE-STACK asks the question the audit proved was missing: "does the
# declared capability leave a real FOOTPRINT in the built repo?".
#
# Audit §6 / §16.1: the mandarin build declared `multi_provider_ai` /
# media_storage=s3 etc. and GATE-STACK passed — but internal/ai/ was empty,
# no SDK was in go.mod, no upload code existed. Declaration ≠ implementation.
#
# Algorithm:
#   1. Resolve product_type + scale_tier → catalog key → required_capabilities[]
#      (same resolution as GATE-STACK; tier-aware).
#   2. For each required capability, gather candidate tokens:
#        - the value DECLARED under satisfies_keys (best signal), PLUS
#        - the capability's accept_values[] (generic tech-name hints), PLUS
#        - optional catalog `wiring.dep_packages[]` / `wiring.code_symbols[]`.
#   3. WIRED  := any token present as a dependency OR a source symbol
#                (footprint search EXCLUDES .build-anything.json — see adapters),
#                OR any `wiring.config_globs[]` matches a non-empty file.
#   4. min_impls (catalog `wiring.min_impls`, default 1): require ≥N distinct
#      wired tokens (catches "single provider where multi-provider was claimed").
#   5. Any required capability not wired → FAIL (declared_not_wired).
#
# LAW-F6: no product_type / no catalog entry / no dependency manifest AND no
# source at all → N/A_PENDING_REVIEWER, never silent PASS.
# LAW-CL-95: confidence + ambiguities[] on every verdict.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_wiring-lang-adapters.sh"

ATOM_DIR=""
PROJECT_ROOT=""
CATALOG="$SCRIPT_DIR/feature-catalog.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --atom-dir)     ATOM_DIR="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --catalog)      CATALOG="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${ATOM_DIR:?--atom-dir required}"
: "${PROJECT_ROOT:?--project-root required}"
CONFIG="$PROJECT_ROOT/.build-anything.json"
OUT="$ATOM_DIR/gate-spec/capability-wiring.json"
mkdir -p "$(dirname "$OUT")"

log() { echo "[$(date -u +%H:%M:%S)] [cap-wire] $*" >&2; }

emit_na() {
  local reason="$1" reason_json
  reason_json=$(printf '%s' "$reason" | jq -Rs .)
  cat > "$OUT" <<JSON
{
  "gate": "GATE-WIRE-STACK",
  "passed": null,
  "verdict": "N/A_PENDING_REVIEWER",
  "reason": $reason_json,
  "confidence": 0,
  "ambiguities": [$reason_json],
  "review_required": true,
  "schema_version": "ubs-v8.8-wire-stack",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

emit_fail() {
  local product_type="$1" tier="$2" unwired="$3" wired="$4"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-WIRE-STACK",
  "passed": false,
  "verdict": "FAIL",
  "reason": "required capability declared but not wired in built repo (no dependency, code symbol, or config artifact found)",
  "product_type": "$product_type",
  "tier": "$tier",
  "unwired_capabilities": $unwired,
  "wired_capabilities": $wired,
  "confidence": 100,
  "ambiguities": [],
  "schema_version": "ubs-v8.8-wire-stack",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 1
}

emit_pass() {
  local product_type="$1" tier="$2" wired="$3"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-WIRE-STACK",
  "passed": true,
  "verdict": "PASS",
  "product_type": "$product_type",
  "tier": "$tier",
  "wired_capabilities": $wired,
  "confidence": 100,
  "ambiguities": [],
  "schema_version": "ubs-v8.8-wire-stack",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

# ── Resolve product_type / tier (mirror of GATE-STACK) ────────────────
PRODUCT_TYPE=""
SCALE_TIER=""
if [[ -f "$ATOM_DIR/intent/verdict.json" ]]; then
  PRODUCT_TYPE=$(jq -r '.declared.product_type // empty' "$ATOM_DIR/intent/verdict.json" 2>/dev/null || true)
  SCALE_TIER=$(jq -r '.declared.scale_tier // empty' "$ATOM_DIR/intent/verdict.json" 2>/dev/null || true)
fi
if [[ -z "$PRODUCT_TYPE" && -f "$ATOM_DIR/gate-spec/product-feature-coverage.json" ]]; then
  PRODUCT_TYPE=$(jq -r '.product_type // empty' "$ATOM_DIR/gate-spec/product-feature-coverage.json" 2>/dev/null || true)
fi
[[ -z "$PRODUCT_TYPE" || "$PRODUCT_TYPE" == "null" ]] && emit_na "no product_type resolved — cannot pick capability profile"
[[ ! -f "$CATALOG" ]] && emit_na "feature catalog missing at $CATALOG"

resolve_catalog_key() {
  local t="$1" lc stripped k
  lc=$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')
  if jq -e --arg t "$lc" '.[$t].stack_fitness' "$CATALOG" >/dev/null 2>&1; then echo "$lc"; return; fi
  stripped=$(printf '%s' "$lc" | sed -E 's/-(mvp|lite|basic|prototype|poc|demo|toy|simple|minimal|v[0-9]+)$//')
  if [[ "$stripped" != "$lc" ]] && jq -e --arg t "$stripped" '.[$t].stack_fitness' "$CATALOG" >/dev/null 2>&1; then echo "$stripped"; return; fi
  while IFS= read -r k; do
    [[ "$k" == _* ]] && continue
    if [[ "$lc" == "$k"* || "$k" == "$lc"* ]]; then echo "$k"; return; fi
  done < <(jq -r 'keys[]' "$CATALOG")
  return 1
}

CATALOG_KEY=$(resolve_catalog_key "$PRODUCT_TYPE" || true)
[[ -z "$CATALOG_KEY" ]] && emit_na "no stack_fitness entry matched for product_type=$PRODUCT_TYPE"

# Tier-aware required_capabilities (mirror of GATE-STACK resolution)
TIER_RESOLVED="default"
if [[ -n "$SCALE_TIER" && "$SCALE_TIER" != "null" ]]; then
  if jq -e --arg t "$CATALOG_KEY" --arg tier "$SCALE_TIER" '.[$t].scale_tiers[$tier]' "$CATALOG" >/dev/null 2>&1; then
    TIER_RESOLVED="$SCALE_TIER"
  fi
fi
if [[ "$TIER_RESOLVED" == "default" ]]; then
  REQUIRED=$(jq -r --arg t "$CATALOG_KEY" '.[$t].stack_fitness.required_capabilities[]?' "$CATALOG" 2>/dev/null)
else
  REQUIRED=$(jq -r --arg t "$CATALOG_KEY" --arg tier "$TIER_RESOLVED" '.[$t].scale_tiers[$tier].required_capabilities[]?' "$CATALOG" 2>/dev/null)
fi

# ── v8.9 GATE-CALL trigger → realtime_media becomes a REQUIRED capability ──────
# Any of three independent triggers means a working call MUST be wired (a present
# but dead call button is the slack+notion audit failure):
#   (a) a call feature is DECLARED in feature_surface,
#   (b) chat-app archetype at scale/hyperscale (boss pick — big chat ⇒ calls),
#   (c) the BUILT UI exposes a call surface (call-surface-detect, ≥2 signal kinds).
# collab-docs is deliberately NOT in (b): notion-class docs have no calls; only a
# declared (a) or detected (c) call surface forces realtime_media there.
CALL_TRIGGER=""
FEATURES=""
[[ -f "$ATOM_DIR/intent/verdict.json" ]] && \
  FEATURES=$(jq -r '(.declared.feature_surface // [])[]? | if type=="object" then (.name // empty) else . end' \
    "$ATOM_DIR/intent/verdict.json" 2>/dev/null || true)
FEATURES="$FEATURES
$(jq -r '(.feature_surface // [])[]? | if type=="object" then (.name // empty) else . end' "$CONFIG" 2>/dev/null || true)"
if printf '%s' "$FEATURES" | grep -qiE 'huddle|voice[ /-]?call|video[ /-]?call|audio[ /-]?call|\bcalling\b|\bcalls\b|conferenc|video meeting|video chat|voice chat'; then
  CALL_TRIGGER="declared-call-feature"
fi
if [[ -z "$CALL_TRIGGER" && "$CATALOG_KEY" == "chat-app" ]]; then
  case "$SCALE_TIER" in scale|hyperscale) CALL_TRIGGER="chat-app@$SCALE_TIER" ;; esac
fi
if [[ -z "$CALL_TRIGGER" ]]; then
  bash "$SCRIPT_DIR/call-surface-detect.sh" --project-root "$PROJECT_ROOT" --atom-dir "$ATOM_DIR" >/dev/null 2>&1 || true
  if [[ -f "$ATOM_DIR/gate-spec/call-surface.json" ]]; then
    det=$(jq -r '.detected' "$ATOM_DIR/gate-spec/call-surface.json" 2>/dev/null || echo false)
    [[ "$det" == "true" ]] && CALL_TRIGGER="ui-detected-call-surface"
  fi
fi
if [[ -n "$CALL_TRIGGER" ]]; then
  if ! printf '%s\n' "$REQUIRED" | grep -qx "realtime_media"; then
    REQUIRED=$(printf '%s\nrealtime_media' "$REQUIRED")
  fi
  log "GATE-CALL trigger=$CALL_TRIGGER → realtime_media required"
fi

log "product=$PRODUCT_TYPE key=$CATALOG_KEY tier=$TIER_RESOLVED"

# ── LAW-F6 footprint-surface guard ────────────────────────────────────
# If the repo has NO dependency manifest AND NO source files at all, we cannot
# render a wiring verdict — emit N/A rather than FAIL the whole world (the build
# may not have reached Stage 4 yet). A repo with ANY manifest/source is fair game.
HAS_SURFACE=0
for f in package.json go.mod requirements.txt pyproject.toml Cargo.toml; do
  [[ -f "$PROJECT_ROOT/$f" ]] && HAS_SURFACE=1
done
for d in "$PROJECT_ROOT"/*/; do
  for f in package.json go.mod requirements.txt pyproject.toml Cargo.toml; do
    [[ -f "$d$f" ]] && HAS_SURFACE=1
  done
done
if [[ "$HAS_SURFACE" -eq 0 ]]; then
  if ! find "$PROJECT_ROOT" -type f \( -name '*.go' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.py' -o -name '*.rs' \) \
       -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -1 | grep -q .; then
    emit_na "no dependency manifest and no source files at $PROJECT_ROOT — build has not produced a wiring surface yet (Stage 4 not reached)"
  fi
fi

# ── Per-capability footprint check ────────────────────────────────────
CONFIG_JSON='{}'
[[ -f "$CONFIG" ]] && CONFIG_JSON=$(cat "$CONFIG")

WIRED=()
UNWIRED=()

# declared_value_for <capability> → echoes the value declared under any of the
# capability's satisfies_keys in .build-anything.json (empty if none).
declared_value_for() {
  local cap="$1" key declared
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    declared=$(jq -r --arg k "$key" 'getpath($k | split("."))? // empty' <<<"$CONFIG_JSON" 2>/dev/null || true)
    [[ -n "$declared" && "$declared" != "null" ]] && { echo "$declared"; return 0; }
  done < <(jq -r --arg c "$cap" '._stack_fitness_capabilities[$c].satisfies_keys[]?' "$CATALOG" 2>/dev/null)
  # No satisfies_key declared → empty is a valid answer. MUST return 0 explicitly:
  # the while-read loop ends on EOF (non-zero), which would otherwise abort the
  # `declared=$(declared_value_for …)` caller under `set -e` (only triggered when
  # a required capability is undeclared — e.g. ai-app caps the youtube fixtures never hit).
  return 0
}

check_capability_wiring() {
  local cap="$1"
  local def
  def=$(jq -c --arg c "$cap" '._stack_fitness_capabilities[$c] // empty' "$CATALOG")
  if [[ -z "$def" || "$def" == "null" ]]; then
    # No catalog definition → cannot derive search tokens. Defer to reviewer
    # (GATE-STACK already flags undefined caps); do not fabricate a verdict.
    UNWIRED+=("$cap (no capability definition — reviewer must supply wiring tokens)")
    return
  fi

  local min_impls
  min_impls=$(jq -r '.wiring.min_impls // 1' <<<"$def" 2>/dev/null || echo 1)
  [[ "$min_impls" =~ ^[0-9]+$ ]] || min_impls=1

  # Gather candidate tokens: declared value + accept_values + explicit wiring hints.
  local tokens=()
  local declared; declared=$(declared_value_for "$cap")
  [[ -n "$declared" ]] && tokens+=("$declared")
  while IFS= read -r v; do [[ -n "$v" ]] && tokens+=("$v"); done < <(jq -r '.accept_values[]?' <<<"$def" 2>/dev/null)
  while IFS= read -r v; do [[ -n "$v" ]] && tokens+=("$v"); done < <(jq -r '.wiring.dep_packages[]?, .wiring.code_symbols[]?' <<<"$def" 2>/dev/null)

  # Count distinct wired tokens (footprint = dep OR source symbol).
  local hits=0 hit_tokens=()
  local t
  for t in "${tokens[@]:-}"; do
    [[ -z "$t" ]] && continue
    # skip pure-punctuation / 1-char tokens to avoid substring false positives
    [[ "${#t}" -lt 2 ]] && continue
    if wiring_footprint_present "$PROJECT_ROOT" "$t"; then
      hits=$((hits+1)); hit_tokens+=("$t")
    fi
  done

  # config-glob footprint (counts toward wiring, not toward distinct impls).
  local glob_ok=0 g
  while IFS= read -r g; do
    [[ -z "$g" ]] && continue
    if wiring_path_glob_present "$PROJECT_ROOT" "$g"; then glob_ok=1; break; fi
  done < <(jq -r '.wiring.config_globs[]?' <<<"$def" 2>/dev/null)

  if [[ "$hits" -ge "$min_impls" ]]; then
    WIRED+=("$cap (impls=$hits via ${hit_tokens[*]:-?})")
  elif [[ "$glob_ok" -eq 1 && "$min_impls" -le 1 ]]; then
    WIRED+=("$cap (config-artifact)")
  elif [[ "$hits" -gt 0 && "$hits" -lt "$min_impls" ]]; then
    UNWIRED+=("$cap (only $hits impl(s) wired; tier requires ≥$min_impls — single-provider where multi was declared)")
  else
    local d_note=""
    [[ -n "$declared" ]] && d_note=" (declared '$declared' but no dependency/symbol/config footprint)"
    UNWIRED+=("$cap${d_note}")
  fi
}

while IFS= read -r cap; do
  [[ -z "$cap" ]] && continue
  check_capability_wiring "$cap"
done <<<"$REQUIRED"

WIRED_JSON=$(printf '%s\n' "${WIRED[@]:-}" | jq -R . | jq -s 'map(select(length>0))')
UNWIRED_JSON=$(printf '%s\n' "${UNWIRED[@]:-}" | jq -R . | jq -s 'map(select(length>0))')

if [[ ${#UNWIRED[@]} -gt 0 ]]; then
  log "FAIL: unwired=${#UNWIRED[@]} wired=${#WIRED[@]}"
  emit_fail "$PRODUCT_TYPE" "$TIER_RESOLVED" "$UNWIRED_JSON" "$WIRED_JSON"
fi

log "PASS: wired=${#WIRED[@]}"
emit_pass "$PRODUCT_TYPE" "$TIER_RESOLVED" "$WIRED_JSON"
