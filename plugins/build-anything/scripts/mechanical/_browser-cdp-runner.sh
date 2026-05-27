#!/usr/bin/env bash
# _browser-cdp-runner.sh — default CDP journey runner for e2e-browser.sh
#
# Args: <binary_path> <journeys_dir> <driver> <startup_timeout_s>
#
# Walks journeys_dir, launches binary with CDP debugging port, drives each
# journey via curl against the protocol, prints [Passed]/[Failed] lines that
# e2e-browser.sh parses.
#
# Supported driver: "cdp" only. For "webdriver" the atom MUST provide
# browser.run_cmd (geckodriver / safaridriver / tauri-driver are external).
#
# Journey shape (JSON):
#   {
#     "name": "load-homepage",
#     "url": "https://example.com",
#     "wait_ms": 2000,
#     "assertions": [
#       { "type": "title_contains", "value": "Example" },
#       { "type": "url_matches", "value": "example.com" }
#     ]
#   }

set -uo pipefail

BINARY="$1"
JOURNEYS_DIR="$2"
DRIVER="${3:-cdp}"
TIMEOUT="${4:-30}"

if [[ "$DRIVER" != "cdp" ]]; then
  echo "[Failed] _browser-cdp-runner only supports driver=cdp; got driver=$DRIVER" >&2
  echo "Atoms using webdriver/safaridriver/tauri-driver must set browser.run_cmd in .build-anything.json" >&2
  exit 2
fi

# Pick an unused port near 9222
PORT=9222
USER_DATA_DIR=$(mktemp -d -t browser-cdp-XXXXXX)
cleanup() {
  if [[ -n "${BROWSER_PID:-}" ]]; then
    kill -9 "$BROWSER_PID" 2>/dev/null || true
  fi
  rm -rf "$USER_DATA_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Launch browser headless with CDP enabled
"$BINARY" \
  --remote-debugging-port=$PORT \
  --headless=new \
  --no-sandbox \
  --disable-gpu \
  --user-data-dir="$USER_DATA_DIR" \
  about:blank \
  >/dev/null 2>&1 &
BROWSER_PID=$!

# Wait for /json/version to respond
ready=0
for _ in $(seq 1 "$TIMEOUT"); do
  if curl -sf "http://localhost:$PORT/json/version" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done

if [[ "$ready" -ne 1 ]]; then
  echo "[Failed] browser did not expose CDP at localhost:$PORT within ${TIMEOUT}s" >&2
  exit 1
fi

# Get an inspector target (browser tab)
TARGET_JSON=$(curl -sf "http://localhost:$PORT/json" || echo '[]')
WS_URL=$(echo "$TARGET_JSON" | jq -r '.[0].webSocketDebuggerUrl // empty')

if [[ -z "$WS_URL" ]]; then
  echo "[Failed] no CDP target available (browser launched but no tab)" >&2
  exit 1
fi

# Without a websocket client we use the simpler HTTP-side helpers:
# Page.navigate is invoked by creating a new tab via PUT /json/new?<url>.
# Assertions are checked via the same /json endpoint + page evaluation.
# This is a best-effort CDP fallback that does not require external deps.

pass=0
fail=0

run_journey() {
  local file="$1"
  local name url wait_ms
  name=$(jq -r '.name // "unnamed"' "$file" 2>/dev/null)
  url=$(jq -r '.url // empty' "$file" 2>/dev/null)
  wait_ms=$(jq -r '.wait_ms // 1500' "$file" 2>/dev/null)

  if [[ -z "$url" ]]; then
    echo "[Failed] $name (no url declared)"
    fail=$((fail + 1))
    return
  fi

  # Open URL in a new tab via CDP HTTP shim
  local new_tab_resp
  new_tab_resp=$(curl -sf -X PUT "http://localhost:$PORT/json/new?$(printf '%s' "$url" | jq -Rr '@uri')" || echo '{}')
  local target_id
  target_id=$(echo "$new_tab_resp" | jq -r '.id // empty')

  if [[ -z "$target_id" ]]; then
    echo "[Failed] $name (failed to open tab for $url)"
    fail=$((fail + 1))
    return
  fi

  # Wait for page to settle
  sleep "$(awk -v ms="$wait_ms" 'BEGIN { printf "%.2f", ms/1000 }')"

  # Refetch target state (title + url populate after navigation)
  local target_state
  target_state=$(curl -sf "http://localhost:$PORT/json" | jq -r --arg id "$target_id" '.[] | select(.id == $id)')

  local actual_title actual_url
  actual_title=$(echo "$target_state" | jq -r '.title // ""')
  actual_url=$(echo "$target_state" | jq -r '.url // ""')

  # Walk assertions
  local failed_assertion=""
  local assertion_count
  assertion_count=$(jq -r '.assertions | length // 0' "$file" 2>/dev/null)

  if [[ "$assertion_count" -eq 0 ]]; then
    failed_assertion="no assertions declared (journey must assert something — empty assertions = vacuous)"
  else
    local i=0
    while [[ "$i" -lt "$assertion_count" ]]; do
      local atype avalue
      atype=$(jq -r ".assertions[$i].type" "$file")
      avalue=$(jq -r ".assertions[$i].value" "$file")
      case "$atype" in
        title_contains)
          [[ "$actual_title" == *"$avalue"* ]] || failed_assertion="title_contains: '$avalue' not in '$actual_title'"
          ;;
        title_matches)
          [[ "$actual_title" =~ $avalue ]] || failed_assertion="title_matches: '$actual_title' does not match /$avalue/"
          ;;
        url_contains)
          [[ "$actual_url" == *"$avalue"* ]] || failed_assertion="url_contains: '$avalue' not in '$actual_url'"
          ;;
        url_matches)
          [[ "$actual_url" =~ $avalue ]] || failed_assertion="url_matches: '$actual_url' does not match /$avalue/"
          ;;
        *)
          failed_assertion="unknown assertion type: $atype"
          ;;
      esac
      [[ -n "$failed_assertion" ]] && break
      i=$((i + 1))
    done
  fi

  # Close the tab regardless
  curl -sf "http://localhost:$PORT/json/close/$target_id" >/dev/null 2>&1 || true

  if [[ -n "$failed_assertion" ]]; then
    echo "[Failed] $name ($failed_assertion)"
    fail=$((fail + 1))
  else
    echo "[Passed] $name"
    pass=$((pass + 1))
  fi
}

while IFS= read -r -d '' jf; do
  run_journey "$jf"
done < <(find "$JOURNEYS_DIR" -type f -name "*.json" -print0)

echo "$pass passed, $fail failed"
[[ "$fail" -gt 0 ]] && exit 1
exit 0
