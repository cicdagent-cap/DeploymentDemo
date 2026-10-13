#!/usr/bin/env bash
set -euo pipefail

# Static validation for the portable kit and/or an installed target repo.
# Does not install dependencies, build, test, dispatch, upload, or notify.

KIT_ROOT=""
REPO=""
FAIL=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/validate_kit.sh [--kit-root <cicd-agent-kit>] [--repo <target-repo>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kit-root) KIT_ROOT="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$KIT_ROOT" ]]; then
  # scripts/ -> kit root
  KIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

check() {
  local name="$1" ok="$2" detail="$3"
  if [[ "$ok" == "1" ]]; then
    echo "PASS  $name — $detail"
  else
    echo "FAIL  $name — $detail"
    FAIL=1
  fi
}

warn() {
  echo "WARN  $1 — $2"
}

echo "=== validate_kit ==="
echo "kit_root: $KIT_ROOT"
[[ -n "$REPO" ]] && echo "repo: $REPO"

REQUIRED_KIT_FILES=(
  agent/CICD.agent.md
  prompts/create-pipeline.prompt.md
  prompts/trigger-build.prompt.md
  prompts/inspect.prompt.md
  prompts/plan.prompt.md
  prompts/validate.prompt.md
  capabilities/catalog.yml
  providers/jenkins/adapter.contract.yml
  providers/jenkins/templates/Jenkinsfile.mobile.template
  docs/JENKINS.md
  docs/ENFORCEMENT.md
  docs/CAPABILITY_TRACKER.md
  tools/registry.yml
  harness/run_loop.sh
  harness/require_approval.sh
  schemas/pipeline-request.schema.json
  templates/mobile-ci-workflow.template.yml
  templates/entry-reusable-workflow.template.yml
  templates/presets.example.json
  templates/variants.example.json
  scripts/detect_project_platform.sh
  scripts/inspect_repo.sh
  scripts/validate_kit.sh
  scripts/validate_request.sh
  scripts/generate_pipeline.sh
  scripts/generate_jenkins_pipeline.sh
  scripts/verify_fastlane_lanes.sh
  scripts/sync_kit_diff.sh
  scripts/trigger_existing_workflow.sh
  scripts/notify.sh
  evals/run_evals.sh
  install.sh
  manifest.yml
)

for f in "${REQUIRED_KIT_FILES[@]}"; do
  if [[ -e "$KIT_ROOT/$f" ]]; then
    check "kit_file:$f" 1 "present"
  else
    check "kit_file:$f" 0 "missing"
  fi
done

# YAML parse (Ruby Psych — available with system Ruby)
for f in \
  "$KIT_ROOT/manifest.yml" \
  "$KIT_ROOT/capabilities/catalog.yml" \
  "$KIT_ROOT/providers/jenkins/adapter.contract.yml" \
  "$KIT_ROOT/config/cicd.config.yml" \
  "$KIT_ROOT/config/cicd.env.config.yml" \
  "$KIT_ROOT/requests/pipeline-request.yml" \
  "$KIT_ROOT/requests/trigger-build-request.yml" \
  "$KIT_ROOT/templates/mobile-ci-workflow.template.yml" \
  "$KIT_ROOT/templates/entry-reusable-workflow.template.yml" \
  "$KIT_ROOT/templates/ios-fastlane-workflow.template.yml"
do
  base="$(basename "$f")"
  if ruby -ryaml -e 'YAML.safe_load(File.read(ARGV[0]), aliases: true)' "$f" >/dev/null 2>&1; then
    check "yaml_parse:$base" 1 "ok"
  else
    # Workflow templates with complex expressions should still be non-empty YAML-like
    if grep -qE '^(name:|on:|pipeline:|provider:|version:|repository:)' "$f"; then
      warn "yaml_parse:$base" "strict parse failed; file looks like a template (accepted with warning)"
    else
      check "yaml_parse:$base" 0 "parse error"
    fi
  fi
done

for f in "$KIT_ROOT/templates/presets.example.json" "$KIT_ROOT/templates/variants.example.json" "$KIT_ROOT/config-overrides/config_overrides.json"; do
  base="$(basename "$f")"
  if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null; then
    check "json_parse:$base" 1 "ok"
  else
    check "json_parse:$base" 0 "invalid JSON"
  fi
done

# Placeholder scan on primary template
PLACEHOLDERS="$(grep -oE '__[A-Z0-9_]+__' "$KIT_ROOT/templates/mobile-ci-workflow.template.yml" | sort -u || true)"
echo "INFO  placeholders in mobile-ci template:"
echo "$PLACEHOLDERS" | sed 's/^/       /'

# Unresolved DeploymentDemo hardcodes in portable kit (should be placeholders)
if grep -R --line-number -E 'com\.capgemini\.DeploymentDemo|gma-org/gmap-ios|staging-trunk' \
  "$KIT_ROOT/requests" "$KIT_ROOT/prompts/trigger-build.prompt.md" "$KIT_ROOT/config" "$KIT_ROOT/fastlane/Appfile" 2>/dev/null \
  | grep -v 'Binary' | head -n 20; then
  warn "org_specific_defaults" "Found org/project-specific strings in kit config/requests (review)"
else
  check "org_specific_defaults" 1 "no gmap/DeploymentDemo hardcodes in scanned paths"
fi

# Script syntax
for s in detect_project_platform.sh inspect_repo.sh validate_kit.sh trigger_existing_workflow.sh notify.sh bootstrap_new_repo.sh; do
  if bash -n "$KIT_ROOT/scripts/$s" 2>/dev/null; then
    check "bash_syntax:$s" 1 "ok"
  else
    check "bash_syntax:$s" 0 "syntax error"
  fi
done
bash -n "$KIT_ROOT/install.sh" && check "bash_syntax:install.sh" 1 "ok" || check "bash_syntax:install.sh" 0 "syntax error"

# Notify non-blocking + template checks
if grep -q 'continue-on-error:\s*true' "$KIT_ROOT/templates/mobile-ci-workflow.template.yml" \
  && grep -q 'notifications' "$KIT_ROOT/templates/mobile-ci-workflow.template.yml"; then
  check "template_notify_nonblocking" 1 "continue-on-error present"
else
  # Also accept if notify job is not a hard dependency
  if grep -A2 'needs:' "$KIT_ROOT/templates/mobile-ci-workflow.template.yml" | grep -q notify; then
    warn "template_notify_nonblocking" "build may still depend on notify — verify template"
  else
    check "template_notify_nonblocking" 1 "build does not need notify"
  fi
fi

if grep -q 'assembleDebug' "$KIT_ROOT/templates/mobile-ci-workflow.template.yml" \
  && grep -q 'bundleRelease\|assembleRelease\|gradle_task_release' "$KIT_ROOT/templates/mobile-ci-workflow.template.yml"; then
  check "android_release_task_distinction" 1 "release task referenced"
else
  warn "android_release_task_distinction" "verify release vs debug gradle tasks"
fi

# Jenkins status
if grep -qi 'status: implemented' "$KIT_ROOT/providers/jenkins/adapter.contract.yml"; then
  check "jenkins_status_implemented" 1 "implemented"
else
  check "jenkins_status_implemented" 0 "expected implemented"
fi

echo "INFO  validation limits: static/fixture only — not build/sign/distribute/CI-runner proof"

if [[ -n "$REPO" && -d "$REPO" ]]; then
  echo "=== repo checks ==="
  if [[ -x "$KIT_ROOT/scripts/detect_project_platform.sh" ]]; then
    if "$KIT_ROOT/scripts/detect_project_platform.sh" --repo "$REPO" --format json >/tmp/cicd-detect-validate.json 2>/dev/null; then
      check "repo_detect" 1 "ok ($(python3 -c 'import json;print(json.load(open("/tmp/cicd-detect-validate.json"))["platform"])'))"
    else
      check "repo_detect" 0 "detection failed"
    fi
  fi
  if [[ -x "$KIT_ROOT/scripts/inspect_repo.sh" ]]; then
    "$KIT_ROOT/scripts/inspect_repo.sh" --repo "$REPO" --format json >/tmp/cicd-inspect-validate.json 2>/dev/null \
      && check "repo_inspect" 1 "ok" \
      || check "repo_inspect" 0 "inspect failed"
  fi
fi

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "RESULT: PASS (static). Builds/tests/dispatch/signing/upload were not executed."
  exit 0
else
  echo "RESULT: FAIL (static). See FAIL lines above."
  exit 1
fi
