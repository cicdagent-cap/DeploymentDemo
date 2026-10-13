#!/usr/bin/env bash
set -euo pipefail

KIT_ROOT="$("$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve_kit_home.sh")"
# Local/CI notify: require approval unless running inside GHA with notifications already gated by workflow.
if [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
  if [[ -x "$KIT_ROOT/harness/require_approval.sh" ]]; then
    "$KIT_ROOT/harness/require_approval.sh" --action notification \
      --repo "${CICD_REPO_ROOT:-$(pwd)}" \
      --scope-file "${CICD_APPROVED_SCOPE_FILE:-}" \
      --environment "${CICD_DISPATCH_ENVIRONMENT:-}" \
      --destination "${CICD_DISPATCH_DESTINATION:-}" || {
        echo "Notification blocked: approved scope action 'notification' required for local notify."
        exit 2
      }
  fi
fi

LOCAL_ENV_FILE="${CICD_LOCAL_ENV_FILE:-.notification.local.env}"
ENV_SOURCE=""

if [ -f "${LOCAL_ENV_FILE}" ]; then
  ENV_SOURCE="${LOCAL_ENV_FILE}"
elif [ -f "CI_CD_Project/.notification.local.env" ]; then
  ENV_SOURCE="CI_CD_Project/.notification.local.env"
fi

if [ -n "${ENV_SOURCE}" ]; then
  set -a
  # shellcheck disable=SC1090
  . "${ENV_SOURCE}"
  set +a
fi

STATUS="${1:-}"
RUN_URL="${2:-}"
BRANCH="${3:-}"
CHAT_PROVIDER="${CICD_CHAT_PROVIDER:-teams}"
TEAM_WEBHOOK_URL="${TEAM_WEBHOOK_URL:-${TEAMS_WEBHOOK_URL:-}}"

if [ -z "${STATUS}" ] || [ -z "${RUN_URL}" ]; then
  echo "Usage: $0 <status> <run-url> [branch]"
  exit 1
fi

if [ -z "${TEAM_WEBHOOK_URL}" ]; then
  echo "TEAM_WEBHOOK_URL/TEAMS_WEBHOOK_URL is not configured. Skipping notification (optional)."
  exit 0
fi

case "${STATUS}" in
  success) READABLE_STATUS="Build Successful" ;;
  failure) READABLE_STATUS="Build Failed" ;;
  cancelled) READABLE_STATUS="Build Cancelled" ;;
  skipped) READABLE_STATUS="Build Skipped" ;;
  triggered) READABLE_STATUS="Build Triggered" ;;
  *) READABLE_STATUS="Build Status: ${STATUS}" ;;
esac

if [[ "${TEAM_WEBHOOK_URL}" == *"powerplatform.com"* ]] || [[ "${TEAM_WEBHOOK_URL}" == *"powerautomate"* ]]; then
  CHAT_PROVIDER="powerautomate"
fi

PAYLOAD="$(STATUS="$STATUS" RUN_URL="$RUN_URL" BRANCH="$BRANCH" \
  READABLE_STATUS="$READABLE_STATUS" CHAT_PROVIDER="$CHAT_PROVIDER" python3 - <<'PY'
import json, os
status = os.environ["STATUS"]
run_url = os.environ["RUN_URL"]
branch = os.environ.get("BRANCH", "")
readable = os.environ["READABLE_STATUS"]
provider = os.environ["CHAT_PROVIDER"]
if branch:
    message = f"{readable} | Branch: {branch} | Run: {run_url}"
    text_field = f"Branch: {branch}\n\nRun URL: {run_url}"
else:
    message = f"{readable}. Run: {run_url}"
    text_field = f"Run URL: {run_url}"
if provider == "slack":
    payload = {"text": message}
elif provider == "powerautomate":
    payload = {
        "title": readable,
        "text": text_field,
        "message": message,
        "status": status,
        "branch": branch,
        "runUrl": run_url,
    }
elif provider == "teams":
    payload = {
        "@type": "MessageCard",
        "@context": "https://schema.org/extensions",
        "summary": readable,
        "title": readable,
        "text": text_field,
    }
else:
    payload = {"text": message}
print(json.dumps(payload))
PY
)"

curl --fail --silent --show-error \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}" \
  "${TEAM_WEBHOOK_URL}"

echo "Team notification sent: $READABLE_STATUS"
