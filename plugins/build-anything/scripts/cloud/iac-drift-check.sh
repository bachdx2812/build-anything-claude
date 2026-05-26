#!/usr/bin/env bash
# iac-drift-check.sh — GATE-22 (v8.1).
# Detects manual cloud changes vs declared infra. Drift = ungoverned spend + surprise outages.
# Contract: 0 = no drift; 1 = drift detected; N/A if no IaC configured.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

atom_dir_from_args "$@"
log_step iac-drift "starting"

IAC_DIR=$(cfg "cloud.iac.dir" "")
IAC_KIND=$(cfg "cloud.iac.kind" "terraform")   # terraform | opentofu | pulumi
if [[ -z "$IAC_DIR" || "$IAC_DIR" == "null" ]]; then
  log_step iac-drift "no IaC dir configured — N/A_PENDING_REVIEWER"
  emit_na_pending "GATE-22" "iac-drift.json" "no cloud.iac.dir configured; reviewer must verify atom touches no cloud infra OR wire IaC"
  exit 0
fi

ABS_IAC="$PROJECT_ROOT/$IAC_DIR"
[[ ! -d "$ABS_IAC" ]] && { emit_na_pending "GATE-22" "iac-drift.json" "configured IaC dir '$IAC_DIR' missing — reviewer must fix path"; exit 0; }

case "$IAC_KIND" in
  terraform|opentofu)
    BIN=$([ "$IAC_KIND" = "opentofu" ] && echo "tofu" || echo "terraform")
    require_tool_or_na "$BIN" "GATE-22" "iac-drift.json"

    log_step iac-drift "$BIN init -input=false (silent)"
    ( cd "$ABS_IAC" && $BIN init -input=false -backend=false ) >/dev/null 2>&1 || {
      emit_evidence "GATE-22" false "iac-drift.json" "{\"error\":\"$BIN init failed\"}"
      log_step iac-drift "FAIL init"; exit 1; }

    log_step iac-drift "$BIN plan -detailed-exitcode"
    PLAN_OUT=$(mktemp)
    set +e
    ( cd "$ABS_IAC" && $BIN plan -detailed-exitcode -input=false -no-color ) > "$PLAN_OUT" 2>&1
    PLAN_EXIT=$?
    set -e
    # Detailed exit: 0=no changes, 2=changes detected (drift), 1=error
    DIFF_LINES=$(wc -l < "$PLAN_OUT" | tr -d ' ')
    SAMPLE=$(head -c 4000 "$PLAN_OUT" | jq -Rs .)
    rm -f "$PLAN_OUT"

    if [[ "$PLAN_EXIT" -eq 0 ]]; then
      emit_evidence "GATE-22" true "iac-drift.json" "{\"kind\":\"$IAC_KIND\",\"drift\":false,\"diff_lines\":$DIFF_LINES}"
      log_step iac-drift "PASS no drift"; exit 0
    elif [[ "$PLAN_EXIT" -eq 2 ]]; then
      emit_evidence "GATE-22" false "iac-drift.json" "{\"kind\":\"$IAC_KIND\",\"drift\":true,\"diff_lines\":$DIFF_LINES,\"plan_sample\":$SAMPLE}"
      log_step iac-drift "FAIL drift detected — apply or revert"; exit 1
    else
      emit_evidence "GATE-22" false "iac-drift.json" "{\"kind\":\"$IAC_KIND\",\"error\":\"plan exit $PLAN_EXIT\",\"sample\":$SAMPLE}"
      log_step iac-drift "FAIL plan error"; exit 1
    fi
    ;;
  pulumi)
    require_tool_or_na "pulumi" "GATE-22" "iac-drift.json"
    set +e
    PREVIEW=$( cd "$ABS_IAC" && pulumi preview --diff --non-interactive 2>&1 )
    PEXIT=$?
    set -e
    CHANGED=$(echo "$PREVIEW" | grep -cE '^\s*[~+\-]' || echo 0)
    SAMPLE=$(echo "$PREVIEW" | head -c 4000 | jq -Rs .)
    if [[ "$PEXIT" -eq 0 && "$CHANGED" -eq 0 ]]; then
      emit_evidence "GATE-22" true "iac-drift.json" "{\"kind\":\"pulumi\",\"drift\":false}"
      log_step iac-drift "PASS no drift"; exit 0
    else
      emit_evidence "GATE-22" false "iac-drift.json" "{\"kind\":\"pulumi\",\"drift\":true,\"changed_lines\":$CHANGED,\"sample\":$SAMPLE}"
      log_step iac-drift "FAIL drift detected"; exit 1
    fi
    ;;
  *)
    emit_na_pending "GATE-22" "iac-drift.json" "unknown cloud.iac.kind='$IAC_KIND'; supported: terraform|opentofu|pulumi"
    exit 0
    ;;
esac
