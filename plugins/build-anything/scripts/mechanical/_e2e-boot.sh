#!/usr/bin/env bash
# _e2e-boot.sh — shared stack boot/wait/teardown for browser E2E gates (UBS v8.9).
#
# Sourced by e2e-multiclient.sh (GATE-RT-PROPAGATE) and e2e-call.sh (GATE-CALL).
# Reuses the boot contract e2e-playwright.sh established (same `e2e.*` config keys)
# so a build declares boot ONCE and every behavioral gate reuses it. DRY.
#
# Provides: e2e_wait_http_200, e2e_boot_stack, e2e_cleanup_spawned, $E2E_FRONTEND_URL.
# Requires cfg(), log_step() from _common.sh (caller sources _common.sh first).
# bash 3.2 compatible (macOS default).

E2E_SPAWNED_PIDS=()

# Kill every process this gate spawned. Caller installs the EXIT trap so it can
# still emit its own verdict JSON before teardown.
e2e_cleanup_spawned() {
  local pid
  for pid in "${E2E_SPAWNED_PIDS[@]:-}"; do
    [[ -n "$pid" ]] && kill -TERM "$pid" 2>/dev/null || true
  done
}

# e2e_wait_http_200 <url> <timeout_sec> <label> → rc 0 once 2xx/3xx, rc 1 on timeout.
e2e_wait_http_200() {
  local url="$1" timeout="$2" label="$3"
  local deadline=$(( $(date +%s) + timeout ))
  while [[ $(date +%s) -lt $deadline ]]; do
    if curl -sSf -o /dev/null "$url" 2>/dev/null; then
      log_step e2e "$label up ($url)"; return 0
    fi
    sleep 1
  done
  log_step e2e "$label NOT reachable within ${timeout}s ($url)"; return 1
}

# e2e_boot_stack <log_dir> → install frontend deps if missing, boot backend (when
# both e2e.backend_url + e2e.backend_boot_cmd declared) then frontend, each only if
# not already serving. Spawned PIDs accumulate in E2E_SPAWNED_PIDS for teardown.
# Sets/export E2E_FRONTEND_URL. Returns 1 if any boot target never becomes reachable.
e2e_boot_stack() {
  local log_dir="$1"; mkdir -p "$log_dir"
  local fe_dir be_boot fe_boot fe_url be_url boot_to
  fe_dir=$(cfg "e2e.frontend_dir" "$PROJECT_ROOT/frontend")
  be_boot=$(cfg "e2e.backend_boot_cmd" "")
  fe_boot=$(cfg "e2e.frontend_boot_cmd" "npm run dev")
  fe_url=$(cfg "e2e.frontend_url" "http://localhost:3000")
  be_url=$(cfg "e2e.backend_url" "")
  boot_to=$(cfg "e2e.boot_timeout_sec" "60")

  if [[ -d "$fe_dir" && ! -d "$fe_dir/node_modules" ]]; then
    log_step e2e "installing frontend deps (npm ci) in $fe_dir"
    ( cd "$fe_dir" && npm ci 2>&1 | tail -20 ) || return 1
  fi

  if [[ -n "$be_url" && -n "$be_boot" ]]; then
    if ! curl -sSf -o /dev/null "$be_url" 2>/dev/null; then
      log_step e2e "booting backend: $be_boot"
      ( cd "$PROJECT_ROOT" && eval "$be_boot" ) > "$log_dir/backend-boot.log" 2>&1 &
      E2E_SPAWNED_PIDS+=($!)
      e2e_wait_http_200 "$be_url" "$boot_to" "backend" || return 1
    fi
  fi

  if ! curl -sSf -o /dev/null "$fe_url" 2>/dev/null; then
    log_step e2e "booting frontend: $fe_boot"
    ( cd "$fe_dir" && eval "$fe_boot" ) > "$log_dir/frontend-boot.log" 2>&1 &
    E2E_SPAWNED_PIDS+=($!)
    e2e_wait_http_200 "$fe_url" "$boot_to" "frontend" || return 1
  fi

  E2E_FRONTEND_URL="$fe_url"; export E2E_FRONTEND_URL
  return 0
}
