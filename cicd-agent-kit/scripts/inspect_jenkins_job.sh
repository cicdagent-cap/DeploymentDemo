#!/usr/bin/env bash
set -euo pipefail
# Inspect Jenkins job parameters via API when configured; always supports local Jenkinsfile analysis.

REPO="."
JOB_URL="${JENKINS_JOB_URL:-}"
MODE="auto" # auto|file|api

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --job-url) JOB_URL="${2:-}"; shift 2 ;;
    --mode) MODE="${2:-}"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done
REPO="$(cd "$REPO" && pwd)"

FILE_JSON="$(python3 - "$REPO" <<'PY'
import json, re, sys
from pathlib import Path
repo = Path(sys.argv[1])
files = sorted([p.relative_to(repo).as_posix() for p in repo.glob("Jenkinsfile*")])
params = []
cred_ids = []
agent_labels = []
for rel in files:
    text = (repo / rel).read_text(errors="ignore")
    params += re.findall(r"(?:choice|string|booleanParam)\(\s*name:\s*'([^']+)'", text)
    cred_ids += re.findall(r"credentials\('([^']+)'\)", text)
    agent_labels += re.findall(r"label\s+'([^']+)'", text)
    agent_labels += re.findall(r"label\('([^']+)'\)", text)
print(json.dumps({
  "mode": "file",
  "jenkinsfiles": files,
  "parameters": sorted(set(params)),
  "credential_ids": sorted(set(cred_ids)),
  "agent_labels": sorted(set(agent_labels)),
  "status": "ok" if files else "no_jenkinsfile",
}))
PY
)"

if [[ "$MODE" == "file" || -z "$JOB_URL" ]]; then
  echo "$FILE_JSON"
  exit 0
fi

# API mode
if [[ -z "${JENKINS_USER:-}" || -z "${JENKINS_TOKEN:-}" ]]; then
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); d["api"]={"status":"blocked","reason":"missing_JENKINS_USER_or_JENKINS_TOKEN"}; print(json.dumps(d, indent=2))' "$FILE_JSON"
  exit 0
fi

set +e
API_OUT="$(curl --fail --silent --show-error -u "${JENKINS_USER}:${JENKINS_TOKEN}" "${JOB_URL%/}/api/json?tree=name,property\\[parameterDefinitions\\[name,type,defaultParameterValue\\[value\\],choices\\]\\]" 2>&1)"
CODE=$?
set -e
if [[ "$CODE" -ne 0 ]]; then
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); d["api"]={"status":"error","detail":sys.argv[2][:500]}; print(json.dumps(d, indent=2))' "$FILE_JSON" "$API_OUT"
  exit 1
fi
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); d["api"]=json.loads(sys.argv[2]); d["mode"]="api+file"; print(json.dumps(d, indent=2))' "$FILE_JSON" "$API_OUT"
