#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib_kit_paths.sh"
KIT_ROOT="$CICD_KIT_HOME"
FAIL=0

check() { if [[ "$2" == 1 ]]; then echo "PASS  $1"; else echo "FAIL  $1 — $3"; FAIL=1; fi; }

TEMPLATE="$KIT_ROOT/providers/jenkins/templates/Jenkinsfile.mobile.template"
[[ -f "$TEMPLATE" ]] && check "jenkins_template" 1 || check "jenkins_template" 0 "missing"
for s in inspect_jenkins_job.sh trigger_jenkins_job.sh monitor_jenkins_build.sh generate_jenkins_pipeline.sh; do
  bash -n "$(cicd_script "$s")" && check "syntax:$s" 1 || check "syntax:$s" 0 "syntax"
done

# Contract status should now be implemented for generation/inspect/trigger scripts
if grep -q 'status: implemented' "$KIT_ROOT/providers/jenkins/adapter.contract.yml"; then
  check "contract_status_implemented" 1
else
  check "contract_status_implemented" 0 "adapter.contract.yml not flipped to implemented"
fi

# Local jenkinsfile validation if present
if compgen -G "$REPO/Jenkinsfile*" >/dev/null; then
  "$(cicd_script inspect_jenkins_job.sh)" --repo "$REPO" --mode file >/tmp/cicd-jenkins-inspect.json
  check "local_jenkins_inspect" 1
else
  echo "INFO  no Jenkinsfile in repo (ok for generation-only validation)"
fi

echo
[[ "$FAIL" -eq 0 ]] && echo "RESULT: PASS (jenkins static)" && exit 0 || { echo "RESULT: FAIL"; exit 1; }
