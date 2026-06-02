#!/usr/bin/env bash
# auth-roundtrip-test.sh — GATE-AUTH-RT (v8.8).
#
# Audit §11.2: a live login returned 401 IMMEDIATELY after a successful
# register, and it was never caught because the suite logged in with a
# PRE-SEEDED fixture user instead of doing a fresh register→login in the
# SAME test. GATE-AUTH-RT is the regression: it registers a brand-new
# random account, then logs in with the SAME credentials — the roundtrip
# the audit proved was missing.
#
# Steps (all via curl -s -o body -w '%{http_code}'):
#   1. mint a random email + password
#   2. POST register      → HARD FAIL if not 2xx OR no token in body
#   3. POST login (same)  → HARD FAIL if not 2xx OR no token  ← THE §11.2 catch
#   4. POST login (wrong pw)  → HARD FAIL if status not in {401,403}
#   5. POST login (unknown email) → SOFT finding if 401 (audit §11.3: semantic,
#      not a security hole). HARD FAIL only when backend.auth.strict_taxonomy.
#
# Reachability: if base_url is not reachable AT ALL → N/A_PENDING_REVIEWER
# (mirror the cloud gates' stance — never FAIL a build whose stack isn't
# booted). The meta-test boots its own mock so it is always reachable.
#
# LAW-F6: backend.auth absent → N/A_PENDING_REVIEWER, never silent PASS.
# LAW-CL-95: confidence + ambiguities[] on every verdict.
# Contract: stdout integer (# hard findings) + JSON evidence file. 0 PASS/NA, 1 FAIL.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step auth-rt "starting"

OUT="$EVIDENCE_DIR/auth-roundtrip.json"
GATE="GATE-AUTH-RT"
SCHEMA="ubs-v8.8-auth-rt"

# ── Emitters (self-contained: carry schema_version + the gate-specific shape) ──
emit_na() {
  local reason="$1" reason_json
  reason_json=$(printf '%s' "$reason" | jq -Rs .)
  cat > "$OUT" <<JSON
{
  "gate": "$GATE",
  "passed": null,
  "verdict": "N/A_PENDING_REVIEWER",
  "reason": $reason_json,
  "confidence": 0,
  "ambiguities": [$reason_json],
  "review_required": true,
  "schema_version": "$SCHEMA",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project": "$(basename "$PROJECT_ROOT")"
}
JSON
  exit 0
}

# emit_verdict <passed:true|false> <findings-json-array> <ambiguities-json-array> <evidence-json-object>
emit_verdict() {
  local passed="$1" findings="$2" ambiguities="$3" evidence="$4"
  local verdict confidence
  if [[ "$passed" == "true" ]]; then verdict='"PASS"'; else verdict='"FAIL"'; fi
  # confidence: 100 — concrete HTTP roundtrip in hand (live register→login executed).
  confidence=100
  cat > "$OUT" <<JSON
{
  "gate": "$GATE",
  "passed": $passed,
  "verdict": $verdict,
  "findings": $findings,
  "evidence": $evidence,
  "confidence": $confidence,
  "ambiguities": $ambiguities,
  "schema_version": "$SCHEMA",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project": "$(basename "$PROJECT_ROOT")"
}
JSON
}

# ── Config ────────────────────────────────────────────────────────────
AUTH_JSON=$(cfg "backend.auth" "{}")
if [[ "$AUTH_JSON" == "{}" || "$AUTH_JSON" == "null" || -z "$AUTH_JSON" ]]; then
  log_step auth-rt "no backend.auth configured — N/A_PENDING_REVIEWER (F6 fix)"
  emit_na "no backend.auth configured; reviewer must verify atom has no register/login surface OR add backend.auth {base_url,register_path,login_path}"
fi

BASE=$(echo "$AUTH_JSON"      | jq -r '.base_url // empty')
REGISTER_PATH=$(echo "$AUTH_JSON" | jq -r '.register_path // "/register"')
LOGIN_PATH=$(echo "$AUTH_JSON"    | jq -r '.login_path // "/login"')
EMAIL_FIELD=$(echo "$AUTH_JSON"   | jq -r '.email_field // "email"')
PASSWORD_FIELD=$(echo "$AUTH_JSON" | jq -r '.password_field // "password"')
TOKEN_FIELD=$(echo "$AUTH_JSON"   | jq -r '.token_field // "access_token"')
STRICT_TAXONOMY=$(echo "$AUTH_JSON" | jq -r '.strict_taxonomy // false')

[[ -z "$BASE" || "$BASE" == "null" ]] && emit_na "backend.auth.base_url missing; reviewer must declare the running auth service base_url"

log_step auth-rt "base=$BASE register=$REGISTER_PATH login=$LOGIN_PATH strict_taxonomy=$STRICT_TAXONOMY"

# ── Connectivity probe (reachability stance — mirror cloud gates) ──────
# Could-not-connect == N/A, never FAIL (the stack may simply not be booted).
# Detect via curl's EXIT CODE (non-zero on connection failure / timeout) rather
# than the printed body: on a refused port curl prints "000" AND exits non-zero,
# and `$(... || echo 000)` would otherwise concatenate to "000000".
BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT
set +e
PROBE=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 "$BASE" 2>/dev/null)
PROBE_RC=$?
set -e
if [[ "$PROBE_RC" -ne 0 || "$PROBE" == "000" ]]; then
  log_step auth-rt "base_url $BASE not reachable (curl rc=$PROBE_RC http=$PROBE) — N/A_PENDING_REVIEWER"
  emit_na "auth service not reachable at $BASE (connection failed, curl rc=$PROBE_RC); reviewer must boot the stack OR mark gate not-applicable"
fi

# ── HTTP helper: POST JSON {email,password}, capture status + body ─────
# Sets globals: RT_STATUS, RT_BODY. Uses configurable field names.
post_creds() {
  local path="$1" email="$2" password="$3"
  local payload rc
  payload=$(jq -nc --arg ef "$EMAIL_FIELD" --arg e "$email" --arg pf "$PASSWORD_FIELD" --arg p "$password" \
    '{($ef): $e, ($pf): $p}')
  set +e
  RT_STATUS=$(curl -s -o "$BODY_FILE" -w '%{http_code}' \
    -H "Content-Type: application/json" \
    -X POST -d "$payload" "$BASE$path" 2>/dev/null)
  rc=$?
  set -e
  # Normalize a connection failure to a single sentinel (curl prints 000 + non-zero rc).
  [[ "$rc" -ne 0 ]] && RT_STATUS="000"
  RT_BODY=$(cat "$BODY_FILE" 2>/dev/null || echo "")
}

is_2xx() { [[ "$1" =~ ^2[0-9][0-9]$ ]]; }

# token present in JSON body under TOKEN_FIELD (non-empty, non-null)?
has_token() {
  local body="$1" tok
  tok=$(printf '%s' "$body" | jq -r --arg f "$TOKEN_FIELD" '.[$f] // empty' 2>/dev/null || echo "")
  [[ -n "$tok" && "$tok" != "null" ]]
}

# ── Findings accumulation ──────────────────────────────────────────────
FINDINGS="[]"
AMBIGUITIES="[]"
HARD_FAILS=0

add_finding() {
  # add_finding <step> <severity:HARD|SOFT|OK> <status> <detail>
  local step="$1" sev="$2" status="$3" detail="$4"
  FINDINGS=$(jq -c \
    --arg s "$step" --arg sev "$sev" --arg st "$status" --arg d "$detail" \
    '. + [{step:$s, severity:$sev, status:$st, detail:$d}]' <<< "$FINDINGS")
  # NOTE: keep this an explicit `if` (not `[[ ]] && ...`) — under `set -e` a
  # trailing failed `[[ ]]` as the last command would return non-zero and abort.
  if [[ "$sev" == "HARD" ]]; then
    HARD_FAILS=$((HARD_FAILS+1))
  fi
  return 0
}

add_ambiguity() {
  local note="$1"
  AMBIGUITIES=$(jq -c --arg n "$note" '. + [$n]' <<< "$AMBIGUITIES")
  return 0
}

# ── Step 1: mint random credentials ────────────────────────────────────
RT_EMAIL="rt-${RANDOM}-${RANDOM}@example.com"
RT_PASSWORD="Rt!${RANDOM}${RANDOM}aZ9"
log_step auth-rt "minted email=$RT_EMAIL"

# ── Step 2: register ────────────────────────────────────────────────────
post_creds "$REGISTER_PATH" "$RT_EMAIL" "$RT_PASSWORD"
REG_STATUS="$RT_STATUS"
if ! is_2xx "$REG_STATUS"; then
  add_finding "register" "HARD" "$REG_STATUS" "register did not return 2xx (got $REG_STATUS) for fresh account"
elif ! has_token "$RT_BODY"; then
  add_finding "register" "HARD" "$REG_STATUS" "register returned $REG_STATUS but no '$TOKEN_FIELD' token in body"
else
  add_finding "register" "OK" "$REG_STATUS" "fresh account registered, token present"
fi

# ── Step 3: login with SAME credentials — THE roundtrip (§11.2 catch) ──
post_creds "$LOGIN_PATH" "$RT_EMAIL" "$RT_PASSWORD"
LOGIN_STATUS="$RT_STATUS"
if ! is_2xx "$LOGIN_STATUS"; then
  add_finding "login_roundtrip" "HARD" "$LOGIN_STATUS" \
    "login FAILED ($LOGIN_STATUS) immediately after a successful register with the SAME credentials — the §11.2 defect (register→login roundtrip broken)"
elif ! has_token "$RT_BODY"; then
  add_finding "login_roundtrip" "HARD" "$LOGIN_STATUS" \
    "login returned $LOGIN_STATUS but no '$TOKEN_FIELD' token — roundtrip did not yield a session"
else
  add_finding "login_roundtrip" "OK" "$LOGIN_STATUS" "register→login roundtrip succeeded with same credentials"
fi

# ── Step 4: login with WRONG password → must be 401/403 ────────────────
post_creds "$LOGIN_PATH" "$RT_EMAIL" "wrong-${RT_PASSWORD}-x"
WRONG_STATUS="$RT_STATUS"
if [[ "$WRONG_STATUS" == "401" || "$WRONG_STATUS" == "403" ]]; then
  add_finding "login_wrong_password" "OK" "$WRONG_STATUS" "wrong password correctly rejected"
else
  add_finding "login_wrong_password" "HARD" "$WRONG_STATUS" \
    "wrong password did NOT yield 401/403 (got $WRONG_STATUS) — auth accepts bad credentials"
fi

# ── Step 5: login with NONEXISTENT email → taxonomy check ──────────────
NX_EMAIL="rt-nonexistent-${RANDOM}-${RANDOM}@example.com"
post_creds "$LOGIN_PATH" "$NX_EMAIL" "$RT_PASSWORD"
NX_STATUS="$RT_STATUS"
if [[ "$STRICT_TAXONOMY" == "true" ]]; then
  # strict: a nonexistent user must be distinguishable — require 404 or 422.
  if [[ "$NX_STATUS" == "404" || "$NX_STATUS" == "422" ]]; then
    add_finding "login_nonexistent_email" "OK" "$NX_STATUS" "nonexistent email returns 404/422 (strict taxonomy satisfied)"
  else
    add_finding "login_nonexistent_email" "HARD" "$NX_STATUS" \
      "strict_taxonomy: nonexistent email must return 404/422, got $NX_STATUS"
  fi
else
  # lenient (default): 401-for-nonexistent is a SOFT semantic finding (§11.3),
  # not a security failure. Other 4xx (404/422) is fine. 2xx/5xx is a hard bug.
  if [[ "$NX_STATUS" == "401" ]]; then
    add_finding "login_nonexistent_email" "SOFT" "$NX_STATUS" \
      "nonexistent email returns 401 (§11.3: semantic, not a security hole — register/login distinguishability could be improved with 404/422)"
    add_ambiguity "nonexistent-email login returns 401 not 404/422 (audit §11.3 — semantic taxonomy, non-blocking; set backend.auth.strict_taxonomy=true to enforce)"
  elif [[ "$NX_STATUS" =~ ^4[0-9][0-9]$ ]]; then
    add_finding "login_nonexistent_email" "OK" "$NX_STATUS" "nonexistent email rejected with $NX_STATUS"
  else
    add_finding "login_nonexistent_email" "HARD" "$NX_STATUS" \
      "nonexistent email yielded $NX_STATUS (expected a 4xx rejection) — login does not reject unknown accounts"
  fi
fi

# ── Verdict ─────────────────────────────────────────────────────────────
EVIDENCE=$(jq -nc \
  --arg base "$BASE" \
  --arg rp "$REGISTER_PATH" --arg lp "$LOGIN_PATH" \
  --arg reg "$REG_STATUS" --arg lr "$LOGIN_STATUS" --arg wp "$WRONG_STATUS" --arg nx "$NX_STATUS" \
  --argjson strict "$STRICT_TAXONOMY" \
  --argjson hard "$HARD_FAILS" \
  '{base_url:$base, register_path:$rp, login_path:$lp,
    status_register:$reg, status_login_roundtrip:$lr,
    status_login_wrong_password:$wp, status_login_nonexistent:$nx,
    strict_taxonomy:$strict, hard_findings:$hard}')

# stdout contract: integer count of hard findings (lower = better; threshold 0).
echo "$HARD_FAILS"

if [[ "$HARD_FAILS" -eq 0 ]]; then
  emit_verdict "true" "$FINDINGS" "$AMBIGUITIES" "$EVIDENCE"
  log_step auth-rt "PASS (register→login roundtrip ok; hard=0)"
  exit 0
else
  emit_verdict "false" "$FINDINGS" "$AMBIGUITIES" "$EVIDENCE"
  log_step auth-rt "FAIL $HARD_FAILS hard finding(s) — register→login roundtrip broken or auth misbehaves"
  exit 1
fi
