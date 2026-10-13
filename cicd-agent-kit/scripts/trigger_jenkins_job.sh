#!/usr/bin/env bash
set -euo pipefail

JOB_URL="${1:-${JENKINS_JOB_URL:-}}"
shift || true
KIT_ROOT="$("$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve_kit_home.sh")"
SCOPE_FILE="${CICD_APPROVED_SCOPE_FILE:-}"
DRY_RUN=0

ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope-file) SCOPE_FILE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --job-url) JOB_URL="${2:-}"; shift 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

[[ -n "$JOB_URL" ]] || { echo "Usage: trigger_jenkins_job.sh <job-url> [key=value...] [--scope-file f] [--dry-run]"; exit 1; }

if [[ "$DRY_RUN" -eq 0 ]]; then
  "$KIT_ROOT/harness/require_approval.sh" --action jenkins_dispatch \
    --repo "${CICD_REPO_ROOT:-$(pwd)}" \
    --scope-file "${SCOPE_FILE:?scope required for jenkins_dispatch}" \
    --environment "${CICD_DISPATCH_ENVIRONMENT:-}" \
    --destination "${CICD_DISPATCH_DESTINATION:-artifacts-only}"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "{\"status\":\"dry_run\",\"job_url\":\"$JOB_URL\",\"params\":$(printf '%s\n' "${ARGS[@]}" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')}"
  exit 0
fi

if [[ -z "${JENKINS_USER:-}" || -z "${JENKINS_TOKEN:-}" ]]; then
  echo '{"status":"blocked","reason":"missing_JENKINS_USER_or_JENKINS_TOKEN"}'
  exit 4
fi

# Crumb
CRUMB_JSON="$(curl --fail --silent --show-error -u "${JENKINS_USER}:${JENKINS_TOKEN}" "${JOB_URL%%/job/*}/crumbIssuer/api/json" 2>/dev/null || true)"
CRUMB_FIELD="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1] or "{}"); print(d.get("crumbRequestField",""))' "$CRUMB_JSON")"
CRUMB_VAL="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1] or "{}"); print(d.get("crumb",""))' "$CRUMB_JSON")"

FORM=()
for kv in "${ARGS[@]+"${ARGS[@]}"}"; do
  FORM+=(--data-urlencode "$kv")
done

HDR=(-u "${JENKINS_USER}:${JENKINS_TOKEN}")
[[ -n "$CRUMB_FIELD" && -n "$CRUMB_VAL" ]] && HDR+=(-H "${CRUMB_FIELD}: ${CRUMB_VAL}")

set +e
RESP="$(curl --fail --silent --show-error -D /tmp/cicd-jenkins-headers.txt "${HDR[@]}" \
  -X POST "${FORM[@]}" "${JOB_URL%/}/buildWithParameters" 2>&1)"
CODE=$?
set -e
QUEUE="$(grep -i '^Location:' /tmp/cicd-jenkins-headers.txt 2>/dev/null | awk '{print $2}' | tr -d '\r' || true)"
if [[ "$CODE" -ne 0 ]]; then
  echo "{\"status\":\"failed\",\"detail\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1][:500]))' "$RESP")}"
  exit 1
fi
echo "{\"status\":\"queued\",\"queue_url\":\"$QUEUE\",\"job_url\":\"$JOB_URL\",\"note\":\"Monitor with monitor_jenkins_build.sh; check prior success before retrying.\"}"
