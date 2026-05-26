#!/usr/bin/env bash
# ci-gate-seal-check.sh — GATE-27 (v8.1).
# Verifies the default branch is protected AND that gates GATE-10..28 are required-status-checks.
# Without this, AL-4 self-heal can merge to main without ever running the gates. Worst hole.
# Contract: 0 = protection ON + all required checks present + admins enforced; 1 = any gap.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step ci-seal "starting"

REPO=$(cfg "cloud.github.repo" "")            # "owner/repo"
BRANCH=$(cfg "cloud.github.branch" "main")
REQUIRED_JSON=$(cfg "cloud.github.required_checks" "[]")

if [[ -z "$REPO" || "$REPO" == "null" ]]; then
  log_step ci-seal "no github repo configured — N/A_PENDING_REVIEWER"
  emit_na_pending "GATE-27" "ci-gate-seal.json" "no cloud.github.repo configured; reviewer must wire owner/repo OR mark atom as non-deployed"
  exit 0
fi
if [[ "$REQUIRED_JSON" == "[]" || "$REQUIRED_JSON" == "null" ]]; then
  emit_na_pending "GATE-27" "ci-gate-seal.json" "no required_checks configured; reviewer must list gates expected on default branch"
  exit 0
fi

require_tool_or_na "gh" "GATE-27" "ci-gate-seal.json"

log_step ci-seal "$REPO branch=$BRANCH"
PROT=$(gh api "repos/$REPO/branches/$BRANCH/protection" 2>/dev/null || echo "{}")
if [[ "$PROT" == "{}" ]] || ! echo "$PROT" | jq -e '.required_status_checks' >/dev/null 2>&1; then
  emit_evidence "GATE-27" false "ci-gate-seal.json" \
    "{\"repo\":\"$REPO\",\"branch\":\"$BRANCH\",\"protection\":false,\"reason\":\"branch protection not configured or gh lacks scope\"}"
  log_step ci-seal "FAIL no protection or no scope"; exit 1
fi

ENFORCE_ADMINS=$(echo "$PROT" | jq -r '.enforce_admins.enabled // false')
STRICT=$(echo "$PROT" | jq -r '.required_status_checks.strict // false')
HAVE_CHECKS=$(echo "$PROT" | jq -c '[.required_status_checks.checks[]?.context // .required_status_checks.contexts[]?]')

MISSING="[]"
while IFS= read -r WANTED; do
  if ! echo "$HAVE_CHECKS" | jq -e --arg w "$WANTED" 'index($w)' >/dev/null 2>&1; then
    MISSING=$(jq -c --arg w "$WANTED" '. + [$w]' <<< "$MISSING")
  fi
done < <( jq -r '.[]' <<< "$REQUIRED_JSON" )

N_MISSING=$(jq 'length' <<< "$MISSING")
FAIL=0
[[ "$ENFORCE_ADMINS" != "true" ]] && FAIL=$((FAIL+1))
[[ "$STRICT" != "true" ]]        && FAIL=$((FAIL+1))
[[ "$N_MISSING" -gt 0 ]]         && FAIL=$((FAIL+1))

PASSED=$([ "$FAIL" -eq 0 ] && echo true || echo false)
emit_evidence "GATE-27" "$PASSED" "ci-gate-seal.json" \
  "{\"repo\":\"$REPO\",\"branch\":\"$BRANCH\",\"enforce_admins\":$ENFORCE_ADMINS,\"strict\":$STRICT,\"required\":$REQUIRED_JSON,\"have\":$HAVE_CHECKS,\"missing\":$MISSING}"

if [[ "$PASSED" == "true" ]]; then log_step ci-seal "PASS"; exit 0
else log_step ci-seal "FAIL enforce_admins=$ENFORCE_ADMINS strict=$STRICT missing_checks=$N_MISSING — main is mergeable without gates"; exit 1
fi
