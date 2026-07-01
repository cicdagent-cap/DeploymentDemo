#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV_FILE="${CICD_LOCAL_ENV_FILE:-.notification.local.env}"
ENV_SOURCE=""

if [ -f "${LOCAL_ENV_FILE}" ]; then
  ENV_SOURCE="${LOCAL_ENV_FILE}"
elif [ -f "CI_CD_Project/.notification.local.env" ]; then
  ENV_SOURCE="CI_CD_Project/.notification.local.env"
fi

if [ -n "${ENV_SOURCE}" ]; then
  set -a
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
  echo "TEAM_WEBHOOK_URL/TEAMS_WEBHOOK_URL is not configured. Skipping team notification."
  exit 0
fi

# Format status for readable message
case "${STATUS}" in
  success)
    READABLE_STATUS="✅ Build Successful"
    ;;
  failure)
    READABLE_STATUS="❌ Build Failed"
    ;;
  cancelled)
    READABLE_STATUS="⛔ Build Cancelled"
    ;;
  triggered)
    READABLE_STATUS="🚀 Build Triggered"
    ;;
  *)
    READABLE_STATUS="Build Status: ${STATUS}"
    ;;
esac

# Build message with branch if provided
if [ -n "${BRANCH}" ]; then
  MESSAGE="${READABLE_STATUS} | Branch: ${BRANCH} | Run: ${RUN_URL}"
  TEXT_FIELD="Branch: ${BRANCH}\n\nRun URL: ${RUN_URL}"
else
  MESSAGE="${READABLE_STATUS}. Run: ${RUN_URL}"
  TEXT_FIELD="Run URL: ${RUN_URL}"
fi

if [ "${CHAT_PROVIDER}" = "slack" ]; then
  PAYLOAD=$(printf '{"text":"%s"}' "${MESSAGE}")
elif [ "${CHAT_PROVIDER}" = "teams" ]; then
  PAYLOAD=$(printf '{"@type":"MessageCard","@context":"https://schema.org/extensions","summary":"%s","title":"%s","text":"%s"}' "${READABLE_STATUS}" "${READABLE_STATUS}" "${TEXT_FIELD}")
else
  PAYLOAD=$(printf '{"text":"%s"}' "${MESSAGE}")
fi

curl --fail --silent --show-error \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}" \
  "${TEAM_WEBHOOK_URL}"

echo "Team notification sent: $READABLE_STATUS"
