#!/usr/bin/env bash
set -euo pipefail
# Bounded execution loop driver: Inspect → Plan → Await approval → Apply → Validate → Report
# Dispatch/distribution are separate authorized scopes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/common.sh"

REPO="${CICD_REPO_ROOT:-}"
REQUEST=""
SCOPE_FILE="${CICD_APPROVED_SCOPE_FILE:-}"
PHASE_START="${CICD_PHASE:-inspect}"
MAX_TOOL_CALLS="${CICD_MAX_TOOL_CALLS:-40}"
MAX_RETRIES="${CICD_MAX_RETRIES:-2}"
TIMEOUT_SECONDS="${CICD_LOOP_TIMEOUT_SECONDS:-1800}"
DRY_RUN_GENERATE=1
TOOL_CALLS=0
START_TS="$(date +%s)"
CORR="$(cicd_correlation_id)"
export CICD_CORRELATION_ID="$CORR"
export CICD_TRACE_FILE="${CICD_TRACE_FILE:-$KIT_ROOT/state/trace-${CORR}.jsonl}"

usage() {
  cat <<'EOF'
Usage:
  harness/run_loop.sh --repo <path> --request <pipeline-request.yml> [--scope-file <approved-scope.yml>] [--phase inspect|plan|apply|validate|report] [--apply]

Default stops after plan/proposal unless --apply and a valid scope file authorizing generate_pipeline/apply_patch.
EOF
}

APPLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --request) REQUEST="${2:-}"; shift 2 ;;
    --scope-file) SCOPE_FILE="${2:-}"; export CICD_APPROVED_SCOPE_FILE="$SCOPE_FILE"; shift 2 ;;
    --phase) PHASE_START="${2:-}"; shift 2 ;;
    --apply) APPLY=1; DRY_RUN_GENERATE=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "$REPO" && -n "$REQUEST" ]] || { usage; exit 1; }
REPO="$(cd "$REPO" && pwd)"
export CICD_REPO_ROOT="$REPO"

bump() {
  TOOL_CALLS=$((TOOL_CALLS + 1))
  NOW="$(date +%s)"
  ELAPSED=$((NOW - START_TS))
  if [[ "$TOOL_CALLS" -gt "$MAX_TOOL_CALLS" ]]; then
    echo "STOP: max_tool_calls exceeded ($MAX_TOOL_CALLS)" >&2
    "$SCRIPT_DIR/trace.sh" stop "max_tool_calls" >/dev/null
    exit 3
  fi
  if [[ "$ELAPSED" -gt "$TIMEOUT_SECONDS" ]]; then
    echo "STOP: loop timeout exceeded (${TIMEOUT_SECONDS}s)" >&2
    "$SCRIPT_DIR/trace.sh" stop "timeout" >/dev/null
    exit 3
  fi
}

run_tool() {
  local name="$1"; shift
  bump
  "$SCRIPT_DIR/trace.sh" tool_start "$name" "$@" >/dev/null || true
  set +e
  OUT="$("$@" 2>&1)"
  CODE=$?
  set -e
  "$SCRIPT_DIR/trace.sh" tool_end "$name" "exit=$CODE" "$(printf '%s' "$OUT" | head -c 2000 | cicd_redact)" >/dev/null || true
  printf '%s\n' "$OUT"
  return "$CODE"
}

echo "correlation_id=$CORR"
"$SCRIPT_DIR/trace.sh" loop_start "phase=$PHASE_START" "repo=$REPO" >/dev/null

export CICD_PHASE=inspect
if [[ "$PHASE_START" == "inspect" || "$PHASE_START" == "plan" || "$PHASE_START" == "apply" || "$PHASE_START" == "validate" || "$PHASE_START" == "report" ]]; then
  :
fi

# INSPECT
if [[ "$PHASE_START" == "inspect" ]]; then
  run_tool inspect_repo "$KIT_ROOT/scripts/inspect_repo.sh" --repo "$REPO" --format json > "$KIT_ROOT/state/last-inspect-${CORR}.json"
  run_tool detect "$KIT_ROOT/scripts/detect_project_platform.sh" --repo "$REPO" --format json > "$KIT_ROOT/state/last-detect-${CORR}.json"
  CICD_PHASE=inspect CICD_GOAL="inspect" "$SCRIPT_DIR/checkpoint.sh" save "inspect-$CORR" < "$KIT_ROOT/state/last-inspect-${CORR}.json" >/dev/null
  PHASE_START=plan
fi

# PLAN
if [[ "$PHASE_START" == "plan" ]]; then
  run_tool validate_request "$KIT_ROOT/scripts/validate_request.sh" --request "$REQUEST" --repo "$REPO" || true
  run_tool recommend "$KIT_ROOT/scripts/recommend_pipeline_action.sh" --repo "$REPO" --request "$REQUEST" > "$KIT_ROOT/state/last-recommend-${CORR}.json"
  run_tool propose "$KIT_ROOT/scripts/propose_changes.sh" --repo "$REPO" --request "$REQUEST" --out "$KIT_ROOT/state/proposal-${CORR}.json"
  echo "AWAITING_APPROVAL: review $KIT_ROOT/state/proposal-${CORR}.json and provide approved-scope before --apply"
  CICD_PHASE=await_approval "$SCRIPT_DIR/checkpoint.sh" save "plan-$CORR" < "$KIT_ROOT/state/proposal-${CORR}.json" >/dev/null
  if [[ "$APPLY" -ne 1 ]]; then
    echo "phase=await_approval"
    exit 0
  fi
  PHASE_START=apply
fi

# APPLY
if [[ "$PHASE_START" == "apply" ]]; then
  [[ -n "$SCOPE_FILE" ]] || { echo "STOP: --scope-file required for apply"; exit 2; }
  PROVIDER="$(ruby -ryaml -e 'd=YAML.safe_load(File.read(ARGV[0]), aliases:true)||{}; puts d["provider"]||"github_actions"' "$REQUEST")"
  if [[ "$PROVIDER" == "jenkins" ]]; then
    run_tool generate_jenkins "$KIT_ROOT/scripts/generate_jenkins_pipeline.sh" --repo "$REPO" --request "$REQUEST" --scope-file "$SCOPE_FILE"
  else
    if [[ "$DRY_RUN_GENERATE" -eq 1 ]]; then
      run_tool generate "$KIT_ROOT/scripts/generate_pipeline.sh" --repo "$REPO" --request "$REQUEST" --scope-file "$SCOPE_FILE" --dry-run
    else
      run_tool generate "$KIT_ROOT/scripts/generate_pipeline.sh" --repo "$REPO" --request "$REQUEST" --scope-file "$SCOPE_FILE"
    fi
  fi
  PHASE_START=validate
fi

# VALIDATE
if [[ "$PHASE_START" == "validate" ]]; then
  run_tool validate_kit "$KIT_ROOT/scripts/validate_kit.sh" --kit-root "$KIT_ROOT" --repo "$REPO" || true
  run_tool validate_configuration "$KIT_ROOT/scripts/validate_configuration.sh" --request "$REQUEST" --repo "$REPO" || true
  PHASE_START=report
fi

# REPORT
echo "phase=report"
echo "correlation_id=$CORR"
echo "tool_calls=$TOOL_CALLS"
echo "trace_file=$CICD_TRACE_FILE"
echo "NOTE: workflow_dispatch / jenkins_dispatch / uploads / notifications require separate approved actions and were not run by this loop."
"$SCRIPT_DIR/trace.sh" loop_end "tool_calls=$TOOL_CALLS" >/dev/null
CICD_PHASE=report "$SCRIPT_DIR/checkpoint.sh" save "report-$CORR" <<< "{\"tool_calls\":$TOOL_CALLS}" >/dev/null
