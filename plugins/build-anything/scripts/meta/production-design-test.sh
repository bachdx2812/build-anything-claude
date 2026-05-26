#!/usr/bin/env bash
# production-design-test.sh — meta-gate for GATE-PROD-DESIGN (v8.5 Stage 1.D).
#
# Asserts the production-design gate correctly:
#   A. N/A_PENDING_REVIEWER when production-design.md is absent.
#   B. PASS when production-design.md has all 8 sections with valid content.
#   C. FAIL when a required section is missing.
#   D. FAIL when Capacity model body has no digits.
#   E. FAIL when Failure modes has <3 data rows.
#   F. FAIL when SLO targets section omits 'p95'.
#   G. FAIL when SLO targets section omits '%' and 'availability'.
#
# Why this exists: v8.5 introduces the production-design layer to force architects
# to articulate capacity/failure-modes/SLOs/tenancy/data-lifecycle/observability
# before code. Without this regression, a future skill edit could silently weaken
# the content checks (e.g. accept adjectives in Capacity model) and we'd ship MVP-
# thinking architectures dressed as production designs.
#
# Exit: 0 PASS, 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE_SCRIPT="$SKILL_ROOT/scripts/spec/production-design-gate.sh"

OUT_BASE="$(mktemp -d -t prod-design-meta-XXXXXX)"
SUMMARY="$OUT_BASE/summary.json"
declare -a CASES_PASSED CASES_FAILED

log() { echo "[meta:prod-design] $*" >&2; }

if [[ ! -x "$GATE_SCRIPT" ]]; then
  log "FATAL: gate script not executable: $GATE_SCRIPT"
  exit 2
fi

# Full valid production-design.md — used as base, modified per-case
VALID_DOC=$(cat <<'MD'
# Production design — fixture

## Capacity model
Target DAU: 50000. Peak RPS write: 200, read: 2000. Storage growth/mo: 8000 GB. Bandwidth/mo: 12 TB. Math: 50000 × 6 × 5 / 86400 ≈ 17 rps average; peak factor 12x.

## Failure modes
| Failure | Detection | Blast radius | Mitigation | Rollback |
|---------|-----------|--------------|------------|----------|
| Postgres primary down | SLO alert p95>5s | all writes | failover replica | restore from snapshot |
| Transcode queue saturated | queue-depth > 10k | new uploads | autoscale workers | drain + scale-out |
| CDN edge dropped | 5xx ratio > 1% | playback paths | failover to origin | revert DNS |

## Tenancy model
Single-tenant per region. No tenant column in current schema. Noisy-neighbor handled at infrastructure layer (separate clusters per major customer).

## Data lifecycle
Videos retained forever; uploads soft-deleted at 30 days then hard-deleted from S3. Backup cadence nightly RPO=24h, restore RTO=2h.

## SLO targets
p95 read latency < 300ms; p95 write < 800ms; availability target 99.9% monthly. Error budget burn rate alerts via prom + pagerduty. SLI source: histogram_quantile from app-pod metrics.

## Deployment topology
Containers on EKS multi-AZ. Rollback via image tag + ArgoCD blue-green. Migrations gated by feature flag; deploy frequency 5x/day; freeze on Fridays.

## Observability story
Logs to Loki, 30-day retention. Metrics in Prometheus + Grafana dashboards (per service). Traces in Tempo with 10% sample rate. Alerts via PagerDuty for SLO burn + 5xx > 1%.

## Boring-tech justification
Postgres over CockroachDB: capacity model shows 200 write RPS — single primary handles. Redis over Memcached: need streams for fanout queue. S3 over self-host: bandwidth at 12 TB/mo is cheaper on managed object store.
MD
)

# $1 name, $2 doc-content (or "" for absent), $3 expected verdict, $4 expected rc
run_case() {
  local name="$1" doc="$2" expected_verdict="$3" expected_rc="$4"
  local case_dir="$OUT_BASE/$name"
  local atom_dir="$case_dir/atom"
  mkdir -p "$atom_dir/gate-spec"

  if [[ -n "$doc" ]]; then
    printf '%s' "$doc" > "$atom_dir/production-design.md"
  fi

  log "case=$name expect=verdict:$expected_verdict rc:$expected_rc"

  set +e
  bash "$GATE_SCRIPT" --atom-dir "$atom_dir" --project-root "$case_dir" \
    >"$case_dir/stdout" 2>"$case_dir/stderr"
  local actual_rc=$?
  set -e

  local verdict_file="$atom_dir/gate-spec/prod-design.json"
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
    jq -c '.' "$verdict_file" 2>/dev/null | sed 's/^/         /' >&2 || true
    CASES_FAILED+=("$name(verdict=$actual_verdict,rc=$actual_rc)")
  fi
}

# ── Case A: absent → N/A ────────────────────────────────────────────
run_case "A_absent" "" "N/A_PENDING_REVIEWER" "0"

# ── Case B: full valid → PASS ───────────────────────────────────────
run_case "B_full_valid" "$VALID_DOC" "PASS" "0"

# ── Case C: missing Tenancy model section → FAIL ────────────────────
NO_TENANCY=$(echo "$VALID_DOC" | awk '
  BEGIN { skip=0 }
  /^## Tenancy model/ { skip=1; next }
  skip && /^## / { skip=0 }
  !skip { print }
')
run_case "C_missing_section" "$NO_TENANCY" "FAIL" "1"

# ── Case D: capacity model no digits → FAIL ─────────────────────────
NO_DIGITS=$(echo "$VALID_DOC" | awk '
  BEGIN { in_sec=0 }
  /^## Capacity model/ { print; print "Large traffic. High throughput. Plenty of storage. Bandwidth ample."; in_sec=1; next }
  in_sec && /^## / { in_sec=0; print; next }
  in_sec { next }
  { print }
')
run_case "D_capacity_no_digits" "$NO_DIGITS" "FAIL" "1"

# ── Case E: failure modes <3 rows → FAIL ───────────────────────────
ONE_ROW=$(echo "$VALID_DOC" | awk '
  BEGIN { in_sec=0 }
  /^## Failure modes/ {
    print
    print "| Failure | Detection | Blast radius | Mitigation | Rollback |"
    print "|---------|-----------|--------------|------------|----------|"
    print "| Postgres primary down | alert | writes | failover | restore |"
    in_sec=1; next
  }
  in_sec && /^## / { in_sec=0; print; next }
  in_sec { next }
  { print }
')
run_case "E_failure_too_few" "$ONE_ROW" "FAIL" "1"

# ── Case F: SLO targets missing p95 → FAIL ─────────────────────────
NO_P95=$(echo "$VALID_DOC" | awk '
  BEGIN { in_sec=0 }
  /^## SLO targets/ {
    print
    print "Availability target 99.9% monthly. Error budget burn rate alerts via prom + pagerduty."
    in_sec=1; next
  }
  in_sec && /^## / { in_sec=0; print; next }
  in_sec { next }
  { print }
')
run_case "F_slo_no_p95" "$NO_P95" "FAIL" "1"

# ── Case G: SLO targets missing % AND availability → FAIL ──────────
NO_AVAIL=$(echo "$VALID_DOC" | awk '
  BEGIN { in_sec=0 }
  /^## SLO targets/ {
    print
    print "p95 read latency 300ms. p95 write 800ms. Error budget burn rate alerts via prom."
    in_sec=1; next
  }
  in_sec && /^## / { in_sec=0; print; next }
  in_sec { next }
  { print }
')
run_case "G_slo_no_availability" "$NO_AVAIL" "FAIL" "1"

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
    meta_gate: "production-design-test",
    schema_version: "ubs-v8.5-meta",
    timestamp: $ts,
    cases_total: $total,
    cases_pass: $pass,
    cases_fail: $fail,
    cases_passed: $passed,
    cases_failed: $failed,
    verdict: (if $fail == 0 then "PASS" else "FAIL" end),
    interpretation: (if $fail == 0
      then "GATE-PROD-DESIGN correctly enforces section presence + content rules — v8.5 invariant holds"
      else "GATE-PROD-DESIGN regressed — one or more fixtures returned unexpected verdict"
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
