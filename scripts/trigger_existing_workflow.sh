#!/usr/bin/env bash
set -euo pipefail

LOCAL_ENV_FILE="${CICD_LOCAL_ENV_FILE:-.notification.local.env}"
ENV_SOURCE=""

if [ -f "$LOCAL_ENV_FILE" ]; then
  ENV_SOURCE="$LOCAL_ENV_FILE"
elif [ -f "CI_CD_Project/.notification.local.env" ]; then
  ENV_SOURCE="CI_CD_Project/.notification.local.env"
fi

if [ -n "$ENV_SOURCE" ]; then
  set -a
  . "$ENV_SOURCE"
  set +a
fi

if [ -n "${TEAM_WEBHOOK_URL:-${TEAMS_WEBHOOK_URL:-}}" ]; then
  echo "Environment: Configured via local file or GitHub"
else
  echo "Missing env setup"
  echo "Run: cp .env.example .notification.local.env"
fi

TARGET="${1:-}"
REF="${2:-}"

shift 2 || true

if [ -z "$TARGET" ] || [ -z "$REF" ]; then
  echo "Usage: $0 <workflow-url> <branch> [input=value...]"
  exit 1
fi

if ! command -v gh >/dev/null; then
  echo "Install GitHub CLI"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Run: gh auth login"
  exit 1
fi

# Extract repo + workflow file
if [[ "$TARGET" =~ github.com/([^/]+/[^/]+)/actions/workflows/([^/?#]+) ]]; then
  REPO="${BASH_REMATCH[1]}"
  WORKFLOW="${BASH_REMATCH[2]}"
else
  echo "Invalid workflow URL"
  exit 1
fi

# Check for recent pending/in-progress runs to prevent accidental double triggers
echo "Checking for recent runs..."
RECENT_RUNS=$(gh run list --workflow "$WORKFLOW" --repo "$REPO" --limit 5 --json status,createdAt,headBranch --jq ".[] | select(.headBranch==\"$REF\" and (.status==\"pending\" or .status==\"in_progress\" or .status==\"queued\"))" 2>/dev/null || echo "")

if [ -n "$RECENT_RUNS" ]; then
  echo "⚠️ A build for this workflow on branch '$REF' is already pending or in progress."
  echo "Skipping trigger to prevent duplicate builds."
  exit 0
fi

COMMAND=(gh workflow run "$WORKFLOW" --repo "$REPO" --ref "$REF")

for ARG in "$@"; do
  COMMAND+=(-f "$ARG")
done

echo "🚀 Triggering build..."
set +e
OUTPUT="$("${COMMAND[@]}" 2>&1)"
COMMAND_EXIT_CODE="$?"
set -e

echo "$OUTPUT"

if [ "$COMMAND_EXIT_CODE" -ne 0 ]; then
  exit "$COMMAND_EXIT_CODE"
fi

RUN_URL=$(echo "$OUTPUT" | grep -Eo 'https://github.com/.*/actions/runs/[0-9]+' | tail -n1 || true)

if [ -n "$RUN_URL" ]; then
  echo
  echo "✅ Build triggered successfully"
  echo "Run URL: $RUN_URL"

  # Best-effort notification at trigger time; completion is still handled by watcher.
  ./scripts/notify.sh "triggered" "$RUN_URL" "$REF" || true
else
  echo "⚠️ Could not extract run URL"
fi

# Background monitor
(
  sleep 5

  RUN_ID=$(echo "$RUN_URL" | grep -Eo '[0-9]+$')

  if [ -z "$RUN_ID" ]; then
    exit 0
  fi

  echo "🔍 Monitoring build..."

  gh run watch "$RUN_ID" --repo "$REPO" --exit-status >/dev/null 2>&1 || true

  STATUS=$(gh run view "$RUN_ID" --repo "$REPO" --json conclusion --jq '.conclusion')

  echo "Build status: $STATUS"

  ./scripts/notify.sh "$STATUS" "$RUN_URL" "$REF"

) >/dev/null 2>&1 &

echo "📡 Background monitoring started (team will be notified on completion)"
