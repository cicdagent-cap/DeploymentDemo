#!/usr/bin/env bash
set -euo pipefail
# GitHub Actions dispatch with kit approval + duplicate/release guards.
# Limitations: duplicate/in-flight detection is a title-based heuristic
# (displayTitle/name vs preset) — not exact workflow-input equality.
# Identical successful distribution runs are also blocked unless CICD_ALLOW_REDISPATCH=1.

KIT_ROOT="$("$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve_kit_home.sh")"
ENVIRONMENT="${CICD_DISPATCH_ENVIRONMENT:-}"
DESTINATION="${CICD_DISPATCH_DESTINATION:-artifacts-only}"

# Remove silent bypass: unscoped dispatch requires explicit host token + flag.
if [[ ! -x "$KIT_ROOT/harness/require_approval.sh" ]]; then
  echo "APPROVAL_DENIED: harness/require_approval.sh missing after install — refusing dispatch." >&2
  exit 2
fi
if [[ "${CICD_ALLOW_UNSCOPED_DISPATCH:-}" == "1" ]]; then
  if [[ -z "${CICD_HOST_APPROVAL_TOKEN:-}" ]]; then
    echo "APPROVAL_DENIED: CICD_ALLOW_UNSCOPED_DISPATCH requires CICD_HOST_APPROVAL_TOKEN (host-bound)." >&2
    exit 2
  fi
else
  "$KIT_ROOT/harness/require_approval.sh" --action workflow_dispatch \
    --repo "${CICD_REPO_ROOT:-$(pwd)}" \
    --scope-file "${CICD_APPROVED_SCOPE_FILE:-}" \
    --environment "$ENVIRONMENT" \
    --destination "$DESTINATION" || exit 2
fi

LOCAL_ENV_FILE="${CICD_LOCAL_ENV_FILE:-.notification.local.env}"
if [ -f "$LOCAL_ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$LOCAL_ENV_FILE"
  set +a
fi

echo "Notification env: $([ -n "${TEAM_WEBHOOK_URL:-${TEAMS_WEBHOOK_URL:-}}" ] && echo configured || echo not_configured) (optional)"

TARGET="${1:-}"
REF="${2:-}"
shift 2 || true
if [ -z "$TARGET" ] || [ -z "$REF" ]; then
  echo "Usage: $0 <workflow-url> <branch> [input=value...]"
  exit 1
fi
command -v gh >/dev/null || { echo "Install GitHub CLI"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Run: gh auth login"; exit 1; }

if [[ "$TARGET" =~ github.com/([^/]+/[^/]+)/actions/workflows/([^/?#]+) ]]; then
  REPO="${BASH_REMATCH[1]}"
  WORKFLOW="${BASH_REMATCH[2]}"
else
  echo "Invalid workflow URL"; exit 1
fi

INPUT_ARGS=("$@")
PRESET_VALUE=""
for ARG in "${INPUT_ARGS[@]}"; do
  case "$ARG" in preset=*) PRESET_VALUE="${ARG#preset=}" ;; esac
done

# Block silent duplicate releases: active runs OR recent successful distribution-like presets
IS_RELEASEISH=0
if [[ "$DESTINATION" != "artifacts-only" && "$DESTINATION" != "none" && -n "$DESTINATION" ]]; then
  IS_RELEASEISH=1
fi
if [[ "$PRESET_VALUE" == Release-* || "$PRESET_VALUE" == *Release* ]]; then
  # Release preset alone is NOT proof of distribution; only treat as releaseish if destination says so
  :
fi

echo "Checking for recent runs (workflow=$WORKFLOW ref=$REF limit=30)..."
RUNS_JSON="$(gh run list --workflow "$WORKFLOW" --repo "$REPO" --limit 30 \
  --json databaseId,status,conclusion,headBranch,displayTitle,name,url,createdAt 2>/dev/null || echo '[]')"

DUP="$(
  PRESET_VALUE="$PRESET_VALUE" REF_NAME="$REF" IS_REL="$IS_RELEASEISH" ALLOW="${CICD_ALLOW_REDISPATCH:-0}" \
  RUNS_JSON="$RUNS_JSON" python3 - <<'PY'
import json, os
from datetime import datetime, timezone, timedelta
runs = json.loads(os.environ.get("RUNS_JSON") or "[]")
ref = os.environ["REF_NAME"]
preset = os.environ.get("PRESET_VALUE") or ""
is_rel = os.environ.get("IS_REL") == "1"
allow = os.environ.get("ALLOW") == "1"
active = {"pending", "in_progress", "queued", "waiting", "requested"}
now = datetime.now(timezone.utc)
for run in runs:
    if run.get("headBranch") != ref:
        continue
    title = f"{run.get('displayTitle') or ''} {run.get('name') or ''}"
    if run.get("status") in active:
        if not preset or preset in title or True:
            # Block any active run on the same branch to prevent stampede.
            print(run.get("url") or "")
            raise SystemExit
    if is_rel and not allow and (run.get("conclusion") or "").lower() == "success":
        if preset and preset not in title:
            continue
        created = run.get("createdAt")
        try:
            ts = datetime.fromisoformat(created.replace("Z", "+00:00"))
        except Exception:
            continue
        if now - ts < timedelta(hours=2):
            print(run.get("url") or "")
            raise SystemExit
PY
)"

if [ -n "$DUP" ]; then
  echo "Skipping dispatch to prevent duplicate/in-flight run."
  echo "Existing run: $DUP"
  echo "Limitation: title-based input matching is best-effort. Set CICD_ALLOW_REDISPATCH=1 only with new approval if intentional."
  exit 0
fi

COMMAND=(gh workflow run "$WORKFLOW" --repo "$REPO" --ref "$REF")
for ARG in "${INPUT_ARGS[@]}"; do COMMAND+=(-f "$ARG"); done

echo "Triggering workflow dispatch (real dispatch; not a dry-run)..."
set +e
OUTPUT="$("${COMMAND[@]}" 2>&1)"
CODE=$?
set -e
echo "$OUTPUT"
[[ "$CODE" -eq 0 ]] || exit "$CODE"

RUN_URL="$(echo "$OUTPUT" | grep -Eo 'https://github.com/[^[:space:]]+/actions/runs/[0-9]+' | tail -n1 || true)"
CORRELATION="cli_output"
if [ -z "$RUN_URL" ]; then
  CORRELATION="poll_fallback"
  for _ in 1 2 3 4 5 6; do
    sleep 2
    RUN_URL="$(gh run list --workflow "$WORKFLOW" --repo "$REPO" --branch "$REF" --limit 5 \
      --json url,createdAt --jq 'sort_by(.createdAt) | reverse | .[0].url // empty' 2>/dev/null || true)"
    [[ -n "$RUN_URL" ]] && break
  done
fi

if [ -n "$RUN_URL" ]; then
  echo "Build triggered successfully"
  echo "Run URL: $RUN_URL"
  echo "Correlation: $CORRELATION"
else
  echo "Dispatch accepted; correlation unavailable — use gh run list"
fi
