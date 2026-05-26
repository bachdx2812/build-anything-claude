#!/usr/bin/env bash
# stack-fitness-check.sh — Stage 1.D GATE-STACK (v8.5)
#
# Purpose: prevent the skill from generating mismatched stacks. Two layers:
#   (1) infra-capability presence per product type (v8.3+)
#   (2) tier alignment: declared stack vs declared scale_tier/cost/team (v8.5)
#
# Why: v8.3 audit (yt-build-from-scratch) shipped a "youtube clone" backed by
# SQLite + multer-disk. Mechanical gates passed. Product was unshippable.
# v8.5 audit: skills produced MVP stacks for production briefs because
# fitness was tier-agnostic. Now tier-aware.
#
# Resolution order for fitness block:
#   1. intent.declared.scale_tier set AND catalog has scale_tiers[tier] → tier block
#   2. else → flat stack_fitness block (backwards-compat for unknown tier)
#
# Tier block fields (v8.5):
#   - required_capabilities[]       — capability slugs (same as flat)
#   - recommended_capabilities[]    — advisory, not gated
#   - disqualified_packages[]       — tier-specific package blacklist (additive)
#   - cost_band.{min,max}_usd_month — minimum/maximum infra cost envelope
#   - team_size_max                 — max team size for which tier is sized
#
# Tier checks (only if tier block resolved AND intent fields present):
#   - cost.monthly_usd_ceiling < cost_band.min_usd_month → FAIL (under-budgeted)
#   - team.size > team_size_max (not null)               → FAIL (tier too small)
#   - team.ops_maturity rank < tier.ops_maturity_floor   → FAIL (team can't ops)
#
# LAW-F6: no vacuous PASS. If no product_type can be resolved →
# N/A_PENDING_REVIEWER, not PASS.
# LAW-CL-95: every verdict carries confidence + ambiguities[].

set -euo pipefail

ATOM_DIR=""
PROJECT_ROOT=""
CATALOG="$(dirname "$0")/feature-catalog.json"

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
OUT="$ATOM_DIR/gate-spec/stack-fitness.json"
mkdir -p "$(dirname "$OUT")"

log() { echo "[$(date -u +%H:%M:%S)] [stack-fit] $*" >&2; }

emit_na() {
  local reason="$1"
  local reason_json
  reason_json=$(printf '%s' "$reason" | jq -Rs .)
  cat > "$OUT" <<JSON
{
  "gate": "GATE-STACK",
  "passed": null,
  "verdict": "N/A_PENDING_REVIEWER",
  "reason": $reason_json,
  "confidence": 0,
  "ambiguities": [$reason_json],
  "review_required": true,
  "schema_version": "ubs-v8.5-stack",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

emit_fail() {
  local product_type="$1" tier="$2" missing_caps="$3" violations="$4" tier_checks="$5"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-STACK",
  "passed": false,
  "verdict": "FAIL",
  "reason": "declared stack misaligned with product type / scale tier",
  "product_type": "$product_type",
  "tier": "$tier",
  "missing_capabilities": $missing_caps,
  "disqualified_violations": $violations,
  "tier_checks": $tier_checks,
  "confidence": 100,
  "ambiguities": [],
  "schema_version": "ubs-v8.5-stack",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 1
}

emit_pass() {
  local product_type="$1" tier="$2" satisfied="$3" tier_checks="$4"
  cat > "$OUT" <<JSON
{
  "gate": "GATE-STACK",
  "passed": true,
  "verdict": "PASS",
  "product_type": "$product_type",
  "tier": "$tier",
  "satisfied_capabilities": $satisfied,
  "tier_checks": $tier_checks,
  "confidence": 100,
  "ambiguities": [],
  "schema_version": "ubs-v8.5-stack",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  exit 0
}

# ── Resolve product_type ──────────────────────────────────────────
PRODUCT_TYPE=""
SCALE_TIER=""
COST_CEILING=""
TEAM_SIZE=""
OPS_MATURITY=""

if [[ -f "$ATOM_DIR/intent/verdict.json" ]]; then
  PRODUCT_TYPE=$(jq -r '.declared.product_type // empty' "$ATOM_DIR/intent/verdict.json" 2>/dev/null || true)
  SCALE_TIER=$(jq -r '.declared.scale_tier // empty' "$ATOM_DIR/intent/verdict.json" 2>/dev/null || true)
  COST_CEILING=$(jq -r '.declared.cost.monthly_usd_ceiling // empty' "$ATOM_DIR/intent/verdict.json" 2>/dev/null || true)
  TEAM_SIZE=$(jq -r '.declared.team.size // empty' "$ATOM_DIR/intent/verdict.json" 2>/dev/null || true)
  OPS_MATURITY=$(jq -r '.declared.team.ops_maturity // empty' "$ATOM_DIR/intent/verdict.json" 2>/dev/null || true)
fi
if [[ -z "$PRODUCT_TYPE" && -f "$ATOM_DIR/gate-spec/product-feature-coverage.json" ]]; then
  PRODUCT_TYPE=$(jq -r '.product_type // empty' "$ATOM_DIR/gate-spec/product-feature-coverage.json" 2>/dev/null || true)
fi

if [[ -z "$PRODUCT_TYPE" || "$PRODUCT_TYPE" == "null" ]]; then
  emit_na "no product_type resolved from intent/verdict.json or gate-spec/product-feature-coverage.json — cannot pick fitness profile"
fi

if [[ ! -f "$CATALOG" ]]; then
  emit_na "feature catalog missing at $CATALOG"
fi

# Normalize product type: try exact, then stripped suffixes, then prefix overlap.
resolve_catalog_key() {
  local t="$1" lc
  lc=$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')
  if jq -e --arg t "$lc" '.[$t].stack_fitness' "$CATALOG" >/dev/null 2>&1; then echo "$lc"; return; fi
  local stripped
  stripped=$(printf '%s' "$lc" | sed -E 's/-(mvp|lite|basic|prototype|poc|demo|toy|simple|minimal|v[0-9]+)$//')
  if [[ "$stripped" != "$lc" ]] && jq -e --arg t "$stripped" '.[$t].stack_fitness' "$CATALOG" >/dev/null 2>&1; then
    echo "$stripped"; return
  fi
  while IFS= read -r k; do
    [[ "$k" == "_stack_fitness_capabilities" ]] && continue
    [[ "$k" == "_scale_tiers_meta" ]] && continue
    if [[ "$lc" == "$k"* || "$k" == "$lc"* ]]; then echo "$k"; return; fi
  done < <(jq -r 'keys[]' "$CATALOG")
  return 1
}

CATALOG_KEY=$(resolve_catalog_key "$PRODUCT_TYPE" || true)
if [[ -z "$CATALOG_KEY" ]]; then
  emit_na "no stack_fitness entry matched for product_type=$PRODUCT_TYPE (tried exact, suffix-stripped, prefix-overlap)"
fi

# ── Resolve fitness block: tier-aware vs flat fallback ────────────
TIER_RESOLVED="default"
if [[ -n "$SCALE_TIER" && "$SCALE_TIER" != "null" ]]; then
  if jq -e --arg t "$CATALOG_KEY" --arg tier "$SCALE_TIER" '.[$t].scale_tiers[$tier]' "$CATALOG" >/dev/null 2>&1; then
    TIER_RESOLVED="$SCALE_TIER"
  fi
fi

log "product_type=$PRODUCT_TYPE → catalog key=$CATALOG_KEY  tier=$TIER_RESOLVED"

if [[ "$TIER_RESOLVED" == "default" ]]; then
  REQUIRED=$(jq -r --arg t "$CATALOG_KEY" '.[$t].stack_fitness.required_capabilities[]?' "$CATALOG" 2>/dev/null)
  TIER_DISQUAL_PKGS=""
  TIER_COST_MIN=""
  TIER_COST_MAX=""
  TIER_TEAM_MAX=""
  TIER_OPS_FLOOR=""
else
  REQUIRED=$(jq -r --arg t "$CATALOG_KEY" --arg tier "$TIER_RESOLVED" '.[$t].scale_tiers[$tier].required_capabilities[]?' "$CATALOG" 2>/dev/null)
  TIER_DISQUAL_PKGS=$(jq -r --arg t "$CATALOG_KEY" --arg tier "$TIER_RESOLVED" '.[$t].scale_tiers[$tier].disqualified_packages[]?' "$CATALOG" 2>/dev/null)
  TIER_COST_MIN=$(jq -r --arg t "$CATALOG_KEY" --arg tier "$TIER_RESOLVED" '.[$t].scale_tiers[$tier].cost_band.min_usd_month // empty' "$CATALOG" 2>/dev/null)
  TIER_COST_MAX=$(jq -r --arg t "$CATALOG_KEY" --arg tier "$TIER_RESOLVED" '.[$t].scale_tiers[$tier].cost_band.max_usd_month // empty' "$CATALOG" 2>/dev/null)
  TIER_TEAM_MAX=$(jq -r --arg t "$CATALOG_KEY" --arg tier "$TIER_RESOLVED" '.[$t].scale_tiers[$tier].team_size_max' "$CATALOG" 2>/dev/null)
  TIER_OPS_FLOOR=$(jq -r --arg tier "$TIER_RESOLVED" '._scale_tiers_meta.tiers[$tier].ops_maturity_floor // empty' "$CATALOG" 2>/dev/null)
fi

# ── Load config ───────────────────────────────────────────────────
CONFIG_JSON='{}'
[[ -f "$CONFIG" ]] && CONFIG_JSON=$(cat "$CONFIG")

# ── Detect package files for disqualified-package scan ────────────
PKG_DUMP=""
[[ -f "$PROJECT_ROOT/package.json" ]]      && PKG_DUMP+=$'\n'$(jq -r '.dependencies // {}, .devDependencies // {} | keys[]?' "$PROJECT_ROOT/package.json" 2>/dev/null || true)
[[ -f "$PROJECT_ROOT/requirements.txt" ]]  && PKG_DUMP+=$'\n'$(cat "$PROJECT_ROOT/requirements.txt" 2>/dev/null || true)
[[ -f "$PROJECT_ROOT/pyproject.toml" ]]    && PKG_DUMP+=$'\n'$(grep -E '^[a-zA-Z]' "$PROJECT_ROOT/pyproject.toml" 2>/dev/null || true)
[[ -f "$PROJECT_ROOT/go.mod" ]]            && PKG_DUMP+=$'\n'$(grep -E '^\s+[a-zA-Z]' "$PROJECT_ROOT/go.mod" 2>/dev/null || true)
[[ -f "$PROJECT_ROOT/Cargo.toml" ]]        && PKG_DUMP+=$'\n'$(grep -E '^[a-zA-Z]' "$PROJECT_ROOT/Cargo.toml" 2>/dev/null || true)
# stack.* declarations in config also feed the scan so a YAML/JSON-declared package shows up.
PKG_DUMP+=$'\n'$(jq -r '.. | strings' <<<"$CONFIG_JSON" 2>/dev/null || true)
PKG_DUMP_LC=$(printf '%s' "$PKG_DUMP" | tr '[:upper:]' '[:lower:]')

SRC_PATHS=$(jq -r '[
  .scope.paths[]? ,
  .scope.bootstrap_glob[]?,
  .stack.dir // empty
] | map(select(length>0)) | unique | .[]' <<<"$CONFIG_JSON" 2>/dev/null || true)

# ── Check each required capability ────────────────────────────────
SATISFIED=()
MISSING=()
VIOLATIONS=()

check_capability() {
  local cap="$1"
  local def
  def=$(jq -c --arg c "$cap" '._stack_fitness_capabilities[$c] // empty' "$CATALOG")
  if [[ -z "$def" || "$def" == "null" ]]; then
    MISSING+=("$cap (no capability definition in catalog)")
    return
  fi

  local declared=""
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    declared=$(jq -r --arg k "$key" 'getpath($k | split("."))? // empty' <<<"$CONFIG_JSON" 2>/dev/null)
    [[ -n "$declared" && "$declared" != "null" ]] && break
  done < <(jq -r '.satisfies_keys[]?' <<<"$def")

  local accept_match="false" disqualified_match=""
  if [[ -n "$declared" && "$declared" != "null" ]]; then
    declared_lc=$(printf '%s' "$declared" | tr '[:upper:]' '[:lower:]')
    while IFS= read -r v; do
      [[ -z "$v" ]] && continue
      v_lc=$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')
      if [[ "$declared_lc" == "$v_lc" ]]; then accept_match="true"; break; fi
    done < <(jq -r '.accept_values[]?' <<<"$def")

    while IFS= read -r v; do
      [[ -z "$v" ]] && continue
      v_lc=$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')
      if [[ "$declared_lc" == "$v_lc" ]]; then disqualified_match="$v"; break; fi
    done < <(jq -r '.disqualified_values[]?' <<<"$def")
  fi

  local bad_pkg=""
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    pkg_lc=$(printf '%s' "$pkg" | tr '[:upper:]' '[:lower:]')
    if echo "$PKG_DUMP_LC" | grep -qF "$pkg_lc"; then bad_pkg="$pkg"; break; fi
  done < <(jq -r '.disqualified_packages[]?' <<<"$def")

  local bad_col=""
  while IFS= read -r col; do
    [[ -z "$col" ]] && continue
    if find "$PROJECT_ROOT" -maxdepth 4 \( -name '*.sql' -o -name 'schema*' -o -name 'migrations' -type d \) 2>/dev/null \
       | xargs grep -lEi "\b${col}\b" 2>/dev/null | head -1 | grep -q .; then
      bad_col="$col"; break
    fi
  done < <(jq -r '.disqualified_schema_columns[]?' <<<"$def")

  if [[ -n "$bad_pkg" ]]; then
    VIOLATIONS+=("$cap: disqualified package '$bad_pkg' in dependencies")
    MISSING+=("$cap")
  elif [[ -n "$bad_col" ]]; then
    VIOLATIONS+=("$cap: disqualified column '$bad_col' in schema")
    MISSING+=("$cap")
  elif [[ -n "$disqualified_match" ]]; then
    VIOLATIONS+=("$cap: declared '$declared' is in disqualified_values")
    MISSING+=("$cap")
  elif [[ "$accept_match" == "true" ]]; then
    SATISFIED+=("$cap=$declared")
  elif [[ -z "$declared" || "$declared" == "null" ]]; then
    MISSING+=("$cap (no declaration found under satisfies_keys)")
  else
    MISSING+=("$cap (declared '$declared' not in accept_values)")
  fi
}

while IFS= read -r cap; do
  [[ -z "$cap" ]] && continue
  check_capability "$cap"
done <<<"$REQUIRED"

# ── Tier-specific disqualified package scan ───────────────────────
if [[ -n "$TIER_DISQUAL_PKGS" ]]; then
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    pkg_lc=$(printf '%s' "$pkg" | tr '[:upper:]' '[:lower:]')
    if echo "$PKG_DUMP_LC" | grep -qF "$pkg_lc"; then
      VIOLATIONS+=("tier-disqualified package '$pkg' present for tier '$TIER_RESOLVED'")
      MISSING+=("tier_disqualified:$pkg")
    fi
  done <<<"$TIER_DISQUAL_PKGS"
fi

# ── Tier alignment checks (cost / team / ops_maturity) ────────────
TIER_CHECK_FAILS=()

ops_rank() {
  case "$1" in
    solo)       echo 1 ;;
    small)      echo 2 ;;
    medium)     echo 3 ;;
    enterprise) echo 4 ;;
    *)          echo 0 ;;
  esac
}

if [[ "$TIER_RESOLVED" != "default" ]]; then
  # Cost ceiling vs tier minimum
  if [[ -n "$COST_CEILING" && "$COST_CEILING" != "null" && -n "$TIER_COST_MIN" && "$TIER_COST_MIN" != "null" ]]; then
    if [[ "$COST_CEILING" -lt "$TIER_COST_MIN" ]]; then
      TIER_CHECK_FAILS+=("cost ceiling \$${COST_CEILING}/mo below tier '$TIER_RESOLVED' minimum \$${TIER_COST_MIN}/mo — under-budgeted for tier")
    fi
  fi

  # Team size vs tier max
  if [[ -n "$TEAM_SIZE" && "$TEAM_SIZE" != "null" && -n "$TIER_TEAM_MAX" && "$TIER_TEAM_MAX" != "null" ]]; then
    if [[ "$TEAM_SIZE" -gt "$TIER_TEAM_MAX" ]]; then
      TIER_CHECK_FAILS+=("team size $TEAM_SIZE exceeds tier '$TIER_RESOLVED' max $TIER_TEAM_MAX — pick higher tier")
    fi
  fi

  # Ops maturity vs floor
  if [[ -n "$OPS_MATURITY" && "$OPS_MATURITY" != "null" && -n "$TIER_OPS_FLOOR" && "$TIER_OPS_FLOOR" != "null" ]]; then
    OPS_R=$(ops_rank "$OPS_MATURITY")
    FLOOR_R=$(ops_rank "$TIER_OPS_FLOOR")
    if [[ "$OPS_R" -lt "$FLOOR_R" ]]; then
      TIER_CHECK_FAILS+=("team ops_maturity '$OPS_MATURITY' below tier '$TIER_RESOLVED' floor '$TIER_OPS_FLOOR' — team cannot operate this tier")
    fi
  fi
fi

# ── Emit verdict ──────────────────────────────────────────────────
SATISFIED_JSON=$(printf '%s\n' "${SATISFIED[@]:-}" | jq -R . | jq -s 'map(select(length>0))')
MISSING_JSON=$(printf '%s\n' "${MISSING[@]:-}" | jq -R . | jq -s 'map(select(length>0))')
VIOLATIONS_JSON=$(printf '%s\n' "${VIOLATIONS[@]:-}" | jq -R . | jq -s 'map(select(length>0))')
TIER_CHECKS_JSON=$(printf '%s\n' "${TIER_CHECK_FAILS[@]:-}" | jq -R . | jq -s 'map(select(length>0))')

if [[ ${#MISSING[@]} -gt 0 || ${#TIER_CHECK_FAILS[@]} -gt 0 ]]; then
  log "FAIL: product=$PRODUCT_TYPE tier=$TIER_RESOLVED missing=${#MISSING[@]} violations=${#VIOLATIONS[@]} tier_check_fails=${#TIER_CHECK_FAILS[@]}"
  emit_fail "$PRODUCT_TYPE" "$TIER_RESOLVED" "$MISSING_JSON" "$VIOLATIONS_JSON" "$TIER_CHECKS_JSON"
fi

log "PASS: product=$PRODUCT_TYPE tier=$TIER_RESOLVED satisfied=${#SATISFIED[@]}"
emit_pass "$PRODUCT_TYPE" "$TIER_RESOLVED" "$SATISFIED_JSON" "$TIER_CHECKS_JSON"
