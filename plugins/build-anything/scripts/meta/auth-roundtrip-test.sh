#!/usr/bin/env bash
# auth-roundtrip-test.sh — meta-gate for GATE-AUTH-RT (v8.8 Stage 5 / backend).
#
# Asserts the auth-roundtrip gate actually performs a FRESH register→login in
# the SAME run and FAILS when login is broken right after register:
#   1. PASS — honest auth server (register works, same creds log in).
#   2. FAIL — broken_login server: register 201 but EVERY login returns 401
#             (reproduces audit §11.2 — "cannot log in immediately after
#             registering", the bug a pre-seeded fixture would have masked).
#   3. N/A  — no backend.auth config (LAW-F6: never silent PASS).
#
# Why this exists: the audit's live login returned 401 right after register and
# was never caught because the suite logged in with a PRE-SEEDED fixture instead
# of a same-test register→login. GATE-AUTH-RT is the v8.8 fix. Without this
# regression a future edit could revert to fixture-only auth checks and §11.2
# would silently return — Case 2 here REPRODUCES the defect and demands FAIL.
#
# The mock auth server is booted in-process (python3 stdlib http.server), so the
# gate's reachability probe always succeeds for Cases 1 & 2.
#
# Exit: 0 PASS (all cases), 1 FAIL (skill regression), 2 harness error.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE_SCRIPT="$SKILL_ROOT/scripts/backend/auth-roundtrip-test.sh"

PORT=8731
MOCK_PY=""
MOCKPID=""
OUT_BASE="$(mktemp -d -t auth-rt-meta-XXXXXX)"
declare -a CASES_PASSED CASES_FAILED

log() { echo "[meta:auth-rt] $*" >&2; }

[[ -f "$GATE_SCRIPT" ]] || { log "FATAL: gate script missing: $GATE_SCRIPT"; exit 2; }
command -v python3 >/dev/null 2>&1 || { log "FATAL: python3 required for mock auth server"; exit 2; }

# ── Inline python3 mock auth server ────────────────────────────────────
# AUTH_MODE (env): honest | broken_login.
#   honest:       POST /register → 201 {access_token}; remembers email→password.
#                 POST /login → 200 {access_token} if email known AND pw matches;
#                               401 wrong pw; 404 unknown email.
#   broken_login: POST /register → 201 {access_token}; POST /login → ALWAYS 401
#                 (the §11.2 mandarin defect: cannot log in right after register).
write_mock() {
  MOCK_PY="$OUT_BASE/mock_auth_server.py"
  cat > "$MOCK_PY" <<'PYEOF'
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

AUTH_MODE = os.environ.get("AUTH_MODE", "honest")
REGISTERED = {}  # email -> password (module-level store)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # silence access log

    def _read_json(self):
        length = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            return json.loads(raw.decode("utf-8")) if raw else {}
        except Exception:
            return {}

    def _send(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        # Reachability probe target (gate curls base_url "/").
        self._send(200, {"status": "ok", "mode": AUTH_MODE})

    def do_POST(self):
        data = self._read_json()
        email = data.get("email")
        password = data.get("password")

        if self.path.rstrip("/") == "/register" or self.path == "/register":
            if email:
                REGISTERED[email] = password
            self._send(201, {"access_token": "t-register"})
            return

        if self.path.rstrip("/") == "/login" or self.path == "/login":
            if AUTH_MODE == "broken_login":
                # The §11.2 defect: login never works, even right after register.
                self._send(401, {"error": "invalid_credentials"})
                return
            # honest mode
            if email not in REGISTERED:
                self._send(404, {"error": "user_not_found"})
                return
            if REGISTERED[email] != password:
                self._send(401, {"error": "invalid_credentials"})
                return
            self._send(200, {"access_token": "t-login"})
            return

        self._send(404, {"error": "not_found"})


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8731
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
PYEOF
}

# ── Server lifecycle ────────────────────────────────────────────────────
kill_mock() {
  if [[ -n "$MOCKPID" ]] && kill -0 "$MOCKPID" 2>/dev/null; then
    kill "$MOCKPID" 2>/dev/null || true
    wait "$MOCKPID" 2>/dev/null || true
  fi
  MOCKPID=""
}

cleanup() {
  kill_mock
  # belt-and-suspenders: reap any stale listener we may have left on PORT
  if command -v lsof >/dev/null 2>&1; then
    local stale; stale=$(lsof -ti tcp:"$PORT" 2>/dev/null || true)
    [[ -n "$stale" ]] && kill $stale 2>/dev/null || true
  fi
}
trap cleanup EXIT

# start_mock <mode> — boots the mock under AUTH_MODE, waits until reachable.
start_mock() {
  local mode="$1"
  kill_mock
  # ensure the port is clear before we bind (kill stragglers from a prior case)
  if command -v lsof >/dev/null 2>&1; then
    local stale; stale=$(lsof -ti tcp:"$PORT" 2>/dev/null || true)
    [[ -n "$stale" ]] && { kill $stale 2>/dev/null || true; sleep 0.3; }
  fi
  AUTH_MODE="$mode" python3 "$MOCK_PY" "$PORT" >/dev/null 2>&1 &
  MOCKPID=$!
  # poll until reachable (or the process died)
  local i
  for i in $(seq 1 50); do
    if ! kill -0 "$MOCKPID" 2>/dev/null; then
      log "FATAL: mock server (mode=$mode) died during startup"; return 1
    fi
    if curl -s -o /dev/null --connect-timeout 1 "http://127.0.0.1:$PORT/" 2>/dev/null; then
      log "mock up mode=$mode pid=$MOCKPID port=$PORT"
      return 0
    fi
    sleep 0.1
  done
  log "FATAL: mock server (mode=$mode) not reachable after ~5s"
  return 1
}

# ── Case harness ────────────────────────────────────────────────────────
# setup <name> <config-json> → echoes case_dir (with config + empty atom dir)
setup() {
  local name="$1" cfg="$2"
  local case_dir="$OUT_BASE/$name"
  mkdir -p "$case_dir/atom/gate-backend"
  printf '%s' "$cfg" > "$case_dir/.build-anything.json"
  echo "$case_dir"
}

# run_case <name> <case_dir> <expected_verdict> <expected_rc>
run_case() {
  local name="$1" case_dir="$2" expected_verdict="$3" expected_rc="$4"
  local atom_dir="$case_dir/atom"
  log "case=$name expect=verdict:$expected_verdict rc:$expected_rc"
  set +e
  bash "$GATE_SCRIPT" --atom-dir "$atom_dir" --project-root "$case_dir" \
    >"$case_dir/stdout" 2>"$case_dir/stderr"
  local actual_rc=$?
  set -e
  local verdict_file="$atom_dir/gate-backend/auth-roundtrip.json"
  if [[ ! -f "$verdict_file" ]]; then
    log "  -> FAIL: no verdict file at $verdict_file"
    sed 's/^/       stderr: /' "$case_dir/stderr" 2>/dev/null | tail -5 >&2 || true
    CASES_FAILED+=("$name(no-verdict)"); return
  fi
  local actual_verdict
  actual_verdict=$(jq -r '.verdict' "$verdict_file" 2>/dev/null)
  if [[ "$actual_verdict" == "$expected_verdict" && "$actual_rc" == "$expected_rc" ]]; then
    log "  -> PASS"; CASES_PASSED+=("$name")
  else
    log "  -> FAIL: got verdict=$actual_verdict rc=$actual_rc"
    jq -c '{verdict,findings,ambiguities,evidence}' "$verdict_file" 2>/dev/null | sed 's/^/       /' >&2 || true
    CASES_FAILED+=("$name(verdict=$actual_verdict,rc=$actual_rc)")
  fi
}

write_mock

# Honest config shared by Cases 1 & 2 — the question is whether login works.
AUTH_CFG=$(jq -nc --arg base "http://127.0.0.1:$PORT" \
  '{backend: {auth: {base_url: $base, register_path: "/register", login_path: "/login"}}}')

# ── Case 1: honest server → PASS rc0 ───────────────────────────────────
start_mock "honest" || exit 2
CD=$(setup "1_honest" "$AUTH_CFG")
run_case "1_honest" "$CD" "PASS" "0"
kill_mock

# ── Case 2: broken_login server → FAIL rc1 (the §11.2 defect) ──────────
start_mock "broken_login" || exit 2
CD=$(setup "2_broken_login" "$AUTH_CFG")
run_case "2_broken_login" "$CD" "FAIL" "1"
kill_mock

# ── Case 3: no backend.auth config → N/A rc0 (no server needed) ────────
CD=$(setup "3_no_auth_config" '{"env":"test"}')
run_case "3_no_auth_config" "$CD" "N/A_PENDING_REVIEWER" "0"

# ── Aggregate ───────────────────────────────────────────────────────────
if [[ ${#CASES_FAILED[@]} -gt 0 ]]; then
  log "FAILED cases:"; for c in "${CASES_FAILED[@]}"; do log "  - $c"; done
  log "summary: pass=${#CASES_PASSED[@]} fail=${#CASES_FAILED[@]} verdict=FAIL"
  exit 1
fi
log "summary: pass=${#CASES_PASSED[@]} fail=0 verdict=PASS"
exit 0
