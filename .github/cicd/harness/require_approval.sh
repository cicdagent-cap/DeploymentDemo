#!/usr/bin/env bash
set -euo pipefail
# Kit-enforced approval gate for mutating/remote tools.
# Independent host boundary only if the agent cannot access or mint
# CICD_HOST_APPROVAL_TOKEN (or equivalent). External path / issuer label alone
# does not prevent manufactured approval. See docs/ENFORCEMENT.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/common.sh"

ACTION=""
REPO_ROOT=""
PATH_REL=""
ENVIRONMENT=""
DESTINATION=""
PROPOSAL_HASH=""
SCOPE_FILE="${CICD_APPROVED_SCOPE_FILE:-}"

usage() {
  cat <<'EOF'
Usage:
  harness/require_approval.sh --action <action> [--repo <path>] [--path <rel>] \
    [--environment <env>] [--destination <dest>] [--proposal-hash <sha>] \
    [--scope-file <yml|json>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action) ACTION="${2:-}"; shift 2 ;;
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --path) PATH_REL="${2:-}"; shift 2 ;;
    --environment) ENVIRONMENT="${2:-}"; shift 2 ;;
    --destination) DESTINATION="${2:-}"; shift 2 ;;
    --proposal-hash) PROPOSAL_HASH="${2:-}"; shift 2 ;;
    --scope-file) SCOPE_FILE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "$ACTION" ]] || { echo "action required" >&2; exit 1; }

# Fail closed: unknown actions are denied (no silent pass-through).
case "$ACTION" in
  apply_patch|generate_pipeline|workflow_dispatch|jenkins_dispatch|notification|install_dependencies|local_build|local_test|upload_distribution|commit|push|remote_settings)
    ;;
  inspect|detect|validate|recommend|propose|sync_diff|monitor|checkpoint|eval)
    exit 0
    ;;
  *)
    echo "APPROVAL_DENIED: unknown action '$ACTION' (fail-closed)" >&2
    exit 2
    ;;
esac

if [[ -z "$SCOPE_FILE" || ! -f "$SCOPE_FILE" ]]; then
  echo "APPROVAL_DENIED: no approved scope file for action '$ACTION'." >&2
  exit 2
fi

REPO_ROOT="${REPO_ROOT:-$(pwd)}"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

# Reject agent-writable in-repo scopes unless host explicitly allows.
SCOPE_REAL="$(cd "$(dirname "$SCOPE_FILE")" && pwd)/$(basename "$SCOPE_FILE")"
if [[ "$SCOPE_REAL" == "$REPO_ROOT"/* && "${CICD_ALLOW_REPO_SCOPE:-}" != "1" ]]; then
  echo "APPROVAL_DENIED: scope file lives inside target repo ($SCOPE_REAL). Host must place scope outside the repo or set CICD_ALLOW_REPO_SCOPE=1 (weakens boundary)." >&2
  exit 2
fi

export CICD_CHECK_ENVIRONMENT="$ENVIRONMENT"
export CICD_CHECK_DESTINATION="$DESTINATION"
export CICD_CHECK_PROPOSAL_HASH="$PROPOSAL_HASH"
export CICD_HOST_APPROVAL_TOKEN="${CICD_HOST_APPROVAL_TOKEN:-}"

python3 - "$SCOPE_FILE" "$ACTION" "$REPO_ROOT" "$PATH_REL" <<'PY'
import json, os, sys, subprocess
from datetime import datetime, timezone
from pathlib import Path

scope_path, action, repo, path_rel = sys.argv[1:5]
text = Path(scope_path).read_text()
try:
    out = subprocess.check_output(
        ["ruby", "-ryaml", "-rjson", "-e", "print JSON.generate(YAML.safe_load(STDIN.read, aliases: true) || {})"],
        input=text.encode(),
    )
    scope = json.loads(out.decode())
except Exception as e:
    print(f"APPROVAL_DENIED: cannot parse scope file: {e}", file=sys.stderr)
    sys.exit(2)

issuer = (scope.get("issuer") or "").lower()
if issuer not in ("human", "host"):
    print("APPROVAL_DENIED: issuer must be 'human' or 'host' (agent-manufactured scopes rejected)", file=sys.stderr)
    sys.exit(2)

host_token = os.environ.get("CICD_HOST_APPROVAL_TOKEN") or ""
if host_token:
    if scope.get("host_token") != host_token:
        print("APPROVAL_DENIED: host_token mismatch or missing (host-bound approval required)", file=sys.stderr)
        sys.exit(2)

actions = set(scope.get("actions") or [])
if action not in actions:
    print(f"APPROVAL_DENIED: action '{action}' not in {sorted(actions)}", file=sys.stderr)
    sys.exit(2)

expires = scope.get("expires_at")
if not expires:
    print("APPROVAL_DENIED: expires_at required", file=sys.stderr)
    sys.exit(2)
try:
    exp = datetime.fromisoformat(expires.replace("Z", "+00:00"))
    if datetime.now(timezone.utc) > exp:
        print(f"APPROVAL_DENIED: scope expired at {expires}", file=sys.stderr)
        sys.exit(2)
except Exception:
    print("APPROVAL_DENIED: invalid expires_at", file=sys.stderr)
    sys.exit(2)

scope_repo = os.path.realpath(scope.get("repo_root") or "")
if not scope_repo:
    print("APPROVAL_DENIED: repo_root required", file=sys.stderr)
    sys.exit(2)
if os.path.realpath(repo) != scope_repo:
    print(f"APPROVAL_DENIED: repo mismatch scope={scope_repo} actual={os.path.realpath(repo)}", file=sys.stderr)
    sys.exit(2)

# Optional head binding
scope_head = scope.get("repo_head")
if scope_head:
    try:
        head = subprocess.check_output(["git", "-C", repo, "rev-parse", "HEAD"], text=True).strip()
        if head != scope_head:
            print(f"APPROVAL_DENIED: stale repo_head scope={scope_head} actual={head}", file=sys.stderr)
            sys.exit(2)
    except Exception as e:
        print(f"APPROVAL_DENIED: cannot verify repo_head: {e}", file=sys.stderr)
        sys.exit(2)

env_needed = os.environ.get("CICD_CHECK_ENVIRONMENT") or ""
dest_needed = os.environ.get("CICD_CHECK_DESTINATION") or ""
if scope.get("environment") and env_needed and scope.get("environment") != env_needed:
    print(f"APPROVAL_DENIED: environment mismatch scope={scope.get('environment')} requested={env_needed}", file=sys.stderr)
    sys.exit(2)
if scope.get("destination") and dest_needed and scope.get("destination") != dest_needed:
    print(f"APPROVAL_DENIED: destination mismatch scope={scope.get('destination')} requested={dest_needed}", file=sys.stderr)
    sys.exit(2)
# If scope pins env/dest, caller must supply matching checks for mutating remote ops
if action in ("workflow_dispatch", "jenkins_dispatch", "upload_distribution", "generate_pipeline"):
    if scope.get("destination") and not dest_needed:
        print("APPROVAL_DENIED: scope pins destination but caller omitted --destination", file=sys.stderr)
        sys.exit(2)
    if scope.get("environment") and not env_needed:
        print("APPROVAL_DENIED: scope pins environment but caller omitted --environment", file=sys.stderr)
        sys.exit(2)

prop = os.environ.get("CICD_CHECK_PROPOSAL_HASH") or ""
if scope.get("proposal_hash"):
    if not prop:
        print("APPROVAL_DENIED: scope binds proposal_hash but caller omitted --proposal-hash", file=sys.stderr)
        sys.exit(2)
    if prop != scope.get("proposal_hash"):
        print("APPROVAL_DENIED: stale or unrelated proposal_hash", file=sys.stderr)
        sys.exit(2)

def norm_path(p: str) -> str:
    p = (p or "").replace("\\", "/")
    while p.startswith("./"):
        p = p[2:]
    return p

denied = scope.get("denied_paths") or []
allowed = scope.get("allowed_paths") or []

# Filesystem mutations require a path and allowed_paths
if action in ("apply_patch", "generate_pipeline") and not path_rel:
    print("APPROVAL_DENIED: --path required for filesystem mutation actions", file=sys.stderr)
    sys.exit(2)

if path_rel:
    n = norm_path(path_rel)
    for d in denied:
        dnorm = norm_path(d)
        prefix = dnorm.rstrip("*")
        if n == dnorm or (prefix and n.startswith(prefix)):
            print(f"APPROVAL_DENIED: path '{n}' is denied", file=sys.stderr)
            sys.exit(2)
    if action in ("apply_patch", "generate_pipeline"):
        if not allowed:
            print("APPROVAL_DENIED: allowed_paths required for filesystem mutations", file=sys.stderr)
            sys.exit(2)
        ok = False
        for a in allowed:
            anorm = norm_path(a)
            if anorm == "*":
                ok = True
                break
            prefix = anorm.rstrip("*")
            if n == anorm or (prefix and n.startswith(prefix)):
                ok = True
                break
        if not ok:
            print(f"APPROVAL_DENIED: path '{n}' not in allowed_paths", file=sys.stderr)
            sys.exit(2)

print("APPROVAL_OK")
sys.exit(0)
PY
