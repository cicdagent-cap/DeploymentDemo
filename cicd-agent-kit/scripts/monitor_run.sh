#!/usr/bin/env bash
set -euo pipefail
# Monitor a GitHub Actions run; normalize queued/running/failed/cancelled/timed_out/success.

RUN_URL_OR_ID="${1:-}"
REPO="${2:-}"
TIMEOUT="${CICD_MONITOR_TIMEOUT_SECONDS:-3600}"
POLL="${CICD_MONITOR_POLL_SECONDS:-10}"

if [[ -z "$RUN_URL_OR_ID" ]]; then
  echo "Usage: monitor_run.sh <run-url-or-id> [owner/repo]"
  exit 1
fi
if ! command -v gh >/dev/null; then
  echo '{"status":"blocked","reason":"gh_cli_missing"}'
  exit 4
fi

RUN_ID="$RUN_URL_OR_ID"
if [[ "$RUN_URL_OR_ID" =~ /actions/runs/([0-9]+) ]]; then
  RUN_ID="${BASH_REMATCH[1]}"
  if [[ -z "$REPO" && "$RUN_URL_OR_ID" =~ github.com/([^/]+/[^/]+)/actions/runs/ ]]; then
    REPO="${BASH_REMATCH[1]}"
  fi
fi

ARGS=(gh run view "$RUN_ID" --json status,conclusion,url,databaseId,headBranch,name,displayTitle)
[[ -n "$REPO" ]] && ARGS+=(--repo "$REPO")

START="$(date +%s)"
while true; do
  set +e
  JSON="$("${ARGS[@]}" 2>/dev/null)"
  CODE=$?
  set -e
  if [[ "$CODE" -ne 0 || -z "$JSON" ]]; then
    echo '{"normalized_status":"failed","status":"error","reason":"run_not_found"}'
    exit 1
  fi

  NORM="$(python3 - "$JSON" "$START" "$TIMEOUT" <<'PY'
import json, sys, time
raw, start, timeout = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
d = json.loads(raw)
status = (d.get("status") or "").lower()
conclusion = (d.get("conclusion") or "") or None
elapsed = int(time.time()) - start
normalized = "running"
if status in ("queued", "waiting", "requested", "pending"):
    normalized = "queued"
elif status in ("in_progress", "running"):
    normalized = "running"
elif status == "completed":
    c = (conclusion or "").lower()
    if c == "success":
        normalized = "success"
    elif c == "cancelled":
        normalized = "cancelled"
    elif c in ("failure", "timed_out"):
        normalized = "failed" if c == "failure" else "timed_out"
    elif c == "skipped":
        normalized = "failed"
    else:
        normalized = "failed"
if elapsed >= timeout and normalized in ("queued", "running"):
    normalized = "timed_out"
print(json.dumps({
  "normalized_status": normalized,
  "status": status,
  "conclusion": conclusion,
  "url": d.get("url"),
  "id": d.get("databaseId"),
  "name": d.get("name"),
  "displayTitle": d.get("displayTitle"),
  "elapsed_seconds": elapsed,
}))
PY
)"

  NSTATUS="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["normalized_status"])' "$NORM")"
  case "$NSTATUS" in
    success|failed|cancelled|timed_out)
      echo "$NORM" | python3 -m json.tool
      [[ "$NSTATUS" == "success" ]] && exit 0 || exit 1
      ;;
  esac
  sleep "$POLL"
done
