#!/usr/bin/env bash
# _common.sh — shared helpers for /build-anything backend integrity scripts.
# Provides: db_url, db_query, http_call, fixture_jwt, emit_evidence, require_test_db.

set -euo pipefail

# ── Atom / project args ────────────────────────────────────────────
atom_dir_from_args() {
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
  EVIDENCE_DIR="$ATOM_DIR/gate-backend"
  mkdir -p "$EVIDENCE_DIR"
  export ATOM_DIR PROJECT_ROOT EVIDENCE_DIR
}

# ── Config reader ──────────────────────────────────────────────────
cfg() {
  local key="$1" default="${2:-}"
  local f="$PROJECT_ROOT/.build-anything.json"
  if [[ -f "$f" ]]; then
    jq -r --arg k "$key" --arg d "$default" \
      '. as $r | ($k | split(".")) as $p | reduce $p[] as $s ($r; .[$s] // null) // $d' "$f"
  else
    echo "$default"
  fi
}

# ── DB connection ──────────────────────────────────────────────────
# Refuses production. LAW-04 hard rule: TEST DB only.
# v8.3: when called with <gate-id> <out-file>, emits N/A_PENDING_REVIEWER on
# missing env (not vacuous FAIL/silent-drop). Production check is still FATAL.
require_test_db() {
  local gate="${1:-}" out="${2:-}"
  local url_env; url_env=$(cfg "backend.db.url_env" "TEST_DB_URL")
  DB_URL="${!url_env:-}"
  if [[ -z "$DB_URL" ]]; then
    if [[ -n "$gate" && -n "$out" ]]; then
      emit_na_pending "$gate" "$out" "env var '$url_env' not set — gate requires a real test database; reviewer must provision OR mark gate not-applicable"
      exit 0
    fi
    echo "FATAL: env var '$url_env' not set. Refusing to run against unknown DB." >&2; exit 127
  fi
  if echo "$DB_URL" | grep -qE "(prod|production|live)"; then
    echo "FATAL: DB_URL appears to be production. LAW-04 hard refusal." >&2; exit 4
  fi
  DB_DRIVER=$(cfg "backend.db.driver" "postgres")
  export DB_URL DB_DRIVER
}

# ── DB query (driver-aware) ────────────────────────────────────────
db_query() {
  local sql="$1"
  case "$DB_DRIVER" in
    postgres) psql "$DB_URL" -At -F $'\t' -c "$sql" ;;
    mysql)    mysql --batch --raw --skip-column-names -e "$sql" "$DB_URL" ;;
    sqlite)
      # accept either plain file path OR sqlite:// URL form
      local path="${DB_URL#sqlite://}"; path="${path#//}"
      sqlite3 "$path" "$sql" ;;
    *) echo "FATAL: unsupported driver $DB_DRIVER" >&2; exit 1 ;;
  esac
}

# ── HTTP helpers ───────────────────────────────────────────────────
# http_call <method> <path> <jwt> <body-json>
http_call() {
  local method="$1" path="$2" jwt="${3:-}" body="${4:-}"
  local base; base=$(cfg "backend.api_base_url" "http://localhost:3000")
  local auth=()
  [[ -n "$jwt" ]] && auth=(-H "Authorization: Bearer $jwt")
  local data=()
  [[ -n "$body" ]] && data=(-H "Content-Type: application/json" -d "$body")
  curl -sS -o /tmp/.ba-resp.json -w "%{http_code}" -X "$method" "${auth[@]}" "${data[@]}" "${base}${path}"
}

# ── Tenant fixture JWT ─────────────────────────────────────────────
fixture_jwt() {
  local who="$1"   # tenant_a | tenant_b | etc.
  local env_var; env_var=$(cfg "backend.tenant_fixtures.${who}.user_jwt_env" "")
  [[ -z "$env_var" ]] && { echo "FATAL: no JWT env for $who" >&2; exit 1; }
  echo "${!env_var}"
}

# ── Evidence emission ──────────────────────────────────────────────
# LAW-CL-95 — backend integrity verdicts always carry a confidence (100 by default;
# concrete DB query / HTTP assertion in hand) and an ambiguities list (empty when
# the test actually ran).
emit_evidence() {
  local gate="$1" passed="$2" out="$3"
  local extra="${4:-}"
  local confidence="${5:-100}"
  local ambiguities="${6:-[]}"
  [[ -z "$extra" ]] && extra='{}'
  cat > "$EVIDENCE_DIR/$out" <<JSON
{
  "gate": "$gate",
  "passed": $passed,
  "verdict": $(if [[ "$passed" == "true" ]]; then echo '"PASS"'; else echo '"FAIL"'; fi),
  "evidence": $extra,
  "confidence": $confidence,
  "ambiguities": $ambiguities,
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project": "$(basename "$PROJECT_ROOT")"
}
JSON
}

# F6 fix — when config is empty, do NOT claim PASS. Emit N/A_PENDING_REVIEWER
# verdict so orchestrator aggregates separately and reviewer must explicitly accept.
# LAW-CL-95 — N/A means confidence=0; the reason is the (single) declared ambiguity.
emit_na_pending() {
  local gate="$1" out="$2" reason="${3:-no config}"
  local reason_json
  reason_json=$(printf '%s' "$reason" | jq -Rs . 2>/dev/null || printf '"%s"' "$reason")
  cat > "$EVIDENCE_DIR/$out" <<JSON
{
  "gate": "$gate",
  "passed": null,
  "verdict": "N/A_PENDING_REVIEWER",
  "reason": "$reason",
  "confidence": 0,
  "ambiguities": [$reason_json],
  "review_required": true,
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project": "$(basename "$PROJECT_ROOT")"
}
JSON
}

log_step() { echo "[$(date -u +%H:%M:%S)] [$1] $2" >&2; }
log_fatal() { echo "FATAL: $*" >&2; exit 1; }
