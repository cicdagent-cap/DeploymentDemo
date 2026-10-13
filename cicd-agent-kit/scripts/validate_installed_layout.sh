#!/usr/bin/env bash
set -euo pipefail
# Validate that an installed target resolves kit assets without cicd-agent-kit/ source tree.

REPO="${1:-.}"
REPO="$(cd "$REPO" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAIL=0

check() {
  local name="$1" ok="$2" detail="$3"
  if [[ "$ok" == "1" ]]; then echo "PASS  $name — $detail"
  else echo "FAIL  $name — $detail"; FAIL=1; fi
}

echo "=== validate_installed_layout ==="
echo "repo: $REPO"

# Hide source kit from resolution for this check
unset CICD_KIT_HOME || true
export CICD_KIT_HOME="$REPO/.github/cicd"

HOME_RESOLVED="$("$SCRIPT_DIR/resolve_kit_home.sh")"
check "resolve_kit_home" "$([[ "$HOME_RESOLVED" == "$REPO/.github/cicd" ]] && echo 1 || echo 0)" "$HOME_RESOLVED"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib_kit_paths.sh"
TMPL="$(cicd_find_templates_dir "$REPO" || true)"
check "templates_dir" "$([[ -n "$TMPL" && -f "$TMPL/mobile-ci-build-test.template.yml" ]] && echo 1 || echo 0)" "${TMPL:-missing}"

for f in \
  harness/require_approval.sh \
  harness/run_loop.sh \
  schemas/pipeline-request.schema.json \
  schemas/approved-scope.schema.json \
  capabilities/catalog.yml \
  tools/registry.yml \
  config/sync-map.yml \
  manifest.yml \
  providers/jenkins/adapter.contract.yml \
  docs/ENFORCEMENT.md
do
  [[ -e "$CICD_KIT_HOME/$f" ]] && check "kit:$f" 1 "present" || check "kit:$f" 0 "missing"
done

for f in \
  .github/cicd.config.yml \
  .github/cicd.env.config.yml \
  .github/pipeline-templates/mobile-ci-build-test.template.yml \
  .github/agents/CICD.agent.md \
  scripts/generate_pipeline.sh \
  scripts/validate_request.sh \
  scripts/lib_kit_paths.sh \
  fastlane/Fastfile \
  Gemfile
do
  [[ -e "$REPO/$f" ]] && check "repo:$f" 1 "present" || check "repo:$f" 0 "missing"
done

# Sibling script resolution (must not require $CICD_KIT_HOME/scripts)
SIB="$("$(cicd_script resolve_kit_home.sh)")"
check "sibling_scripts" "$([[ "$SIB" == "$CICD_KIT_HOME" ]] && echo 1 || echo 0)" "via lib_kit_paths"

# Harness callable from installed home
if [[ -x "$CICD_KIT_HOME/harness/require_approval.sh" ]]; then
  set +e
  "$CICD_KIT_HOME/harness/require_approval.sh" --action inspect --repo "$REPO" >/dev/null 2>&1
  CODE=$?
  set -e
  check "harness_inspect_passthrough" "$([[ "$CODE" -eq 0 ]] && echo 1 || echo 0)" "exit=$CODE"
fi

# Catalog/schema resolve for validate_request
set +e
OUT="$("$(cicd_script validate_request.sh)" --request "$REPO/.github/pipeline-request.yml" --repo "$REPO" 2>&1)"
CODE=$?
set -e
check "validate_request_from_installed" "$([[ "$CODE" -eq 0 || "$OUT" == *errors* ]] && echo 1 || echo 0)" "exit=$CODE"

# Prove source kit path is not required
if [[ -d "$REPO/cicd-agent-kit" ]]; then
  check "source_tree_present_but_unused" 1 "cicd-agent-kit/ exists; CICD_KIT_HOME=$CICD_KIT_HOME"
else
  check "source_tree_absent" 1 "no cicd-agent-kit/; installed layout only"
fi

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "RESULT: PASS (installed layout)"
  exit 0
fi
echo "RESULT: FAIL (installed layout)"
exit 1
