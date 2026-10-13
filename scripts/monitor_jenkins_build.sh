#!/usr/bin/env bash
set -euo pipefail

QUEUE_OR_BUILD_URL="${1:-}"
TIMEOUT="${CICD_MONITOR_TIMEOUT_SECONDS:-3600}"
POLL="${CICD_MONITOR_POLL_SECONDS:-10}"

[[ -n "$QUEUE_OR_BUILD_URL" ]] || { echo "Usage: monitor_jenkins_build.sh <queue-or-build-url>"; exit 1; }
[[ -n "${JENKINS_USER:-}" && -n "${JENKINS_TOKEN:-}" ]] || { echo '{"status":"blocked","reason":"missing_JENKINS_USER_or_JENKINS_TOKEN"}'; exit 4; }

START="$(date +%s)"
URL="$QUEUE_OR_BUILD_URL"

while true; do
  JSON="$(curl --fail --silent --show-error -u "${JENKINS_USER}:${JENKINS_TOKEN}" "${URL%/}/api/json" 2>/dev/null || true)"
  if [[ -z "$JSON" ]]; then
    echo '{"status":"error","reason":"not_found"}'
    exit 1
  fi
  # Queue item may include executable.url once started
  BUILD_URL="$(python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print((d.get("executable") or {}).get("url") or d.get("url") or "")' <<<"$JSON")"
  BUILDING="$(python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(str(d.get("building")).lower() if "building" in d else "queue")' <<<"$JSON")"
  RESULT="$(python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(d.get("result") or "")' <<<"$JSON")"

  if [[ "$BUILDING" == "false" && -n "$RESULT" ]]; then
    echo "{\"status\":\"completed\",\"result\":\"$RESULT\",\"url\":\"$BUILD_URL\"}"
    exit 0
  fi
  if [[ -n "$BUILD_URL" && "$URL" != "$BUILD_URL" && "$BUILDING" == "queue" ]]; then
    URL="$BUILD_URL"
  fi
  NOW="$(date +%s)"
  if [[ $((NOW - START)) -ge "$TIMEOUT" ]]; then
    echo "{\"status\":\"timeout\",\"url\":\"$URL\"}"
    exit 3
  fi
  sleep "$POLL"
done
