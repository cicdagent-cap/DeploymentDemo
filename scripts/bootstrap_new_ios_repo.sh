#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/bootstrap_new_ios_repo.sh <target-repo-path> [bundle-id]

Examples:
  ./scripts/bootstrap_new_ios_repo.sh /Users/me/projects/MyApp com.example.myapp
  ./scripts/bootstrap_new_ios_repo.sh ../MyApp

Notes:
  - Copies CI/CD starter kit into target repo.
  - Auto-detects first top-level *.xcodeproj and uses its name as default scheme.
  - Rewrites copied defaults (project/scheme/bundle id) in target files.
EOF
}

TARGET_REPO="${1:-}"
BUNDLE_ID="${2:-com.example.app}"

if [[ -z "$TARGET_REPO" ]]; then
  usage
  exit 1
fi

if [[ ! -d "$TARGET_REPO" ]]; then
  echo "Target path does not exist: $TARGET_REPO"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Detect Xcode project from target repo root.
PROJECT_PATH="$(find "$TARGET_REPO" -maxdepth 1 -type d -name '*.xcodeproj' | head -n1 || true)"
if [[ -z "$PROJECT_PATH" ]]; then
  echo "No top-level .xcodeproj found in target repo: $TARGET_REPO"
  echo "Create/open your iOS project first, then re-run this script."
  exit 1
fi

PROJECT_FILE="$(basename "$PROJECT_PATH")"
SCHEME="${PROJECT_FILE%.xcodeproj}"
CONFIGURATION="Debug"
TEST_DESTINATION="platform=iOS Simulator,name=iPhone 15"

mkdir -p "$TARGET_REPO/.github/agents"
mkdir -p "$TARGET_REPO/.github/prompts"
mkdir -p "$TARGET_REPO/.github/workflows"
mkdir -p "$TARGET_REPO/.github/pipeline-templates"
mkdir -p "$TARGET_REPO/.github/config-overrides"
mkdir -p "$TARGET_REPO/scripts"
mkdir -p "$TARGET_REPO/fastlane"

copy_file() {
  local src="$1"
  local dst="$2"
  cp "$src" "$dst"
}

# Core CI/CD agent + config
copy_file "$SOURCE_ROOT/.github/agents/CICD.agent.md" "$TARGET_REPO/.github/agents/CICD.agent.md"
copy_file "$SOURCE_ROOT/prompts/create-pipeline.prompt.md" "$TARGET_REPO/.github/prompts/create-pipeline.prompt.md"
copy_file "$SOURCE_ROOT/prompts/trigger-build.prompt.md" "$TARGET_REPO/.github/prompts/trigger-build.prompt.md"

# Sample workflow is optional for template-only starter kits.
if [[ -f "$SOURCE_ROOT/.github/workflows/ios-ci.yml" ]]; then
  copy_file "$SOURCE_ROOT/.github/workflows/ios-ci.yml" "$TARGET_REPO/.github/workflows/ios-ci.yml"
fi

copy_file "$SOURCE_ROOT/pipeline-templates/ios-fastlane-workflow.template.yml" "$TARGET_REPO/.github/pipeline-templates/ios-fastlane-workflow.template.yml"
copy_file "$SOURCE_ROOT/cicd.config.yml" "$TARGET_REPO/.github/cicd.config.yml"
copy_file "$SOURCE_ROOT/cicd.env.config.yml" "$TARGET_REPO/.github/cicd.env.config.yml"
copy_file "$SOURCE_ROOT/pipeline-request.yml" "$TARGET_REPO/.github/pipeline-request.yml"
copy_file "$SOURCE_ROOT/trigger-build-request.yml" "$TARGET_REPO/.github/trigger-build-request.yml"
copy_file "$SOURCE_ROOT/config-overrides/config_overrides.json" "$TARGET_REPO/.github/config-overrides/config_overrides.json"

# Scripts
copy_file "$SOURCE_ROOT/scripts/inspect_workflow_inputs.sh" "$TARGET_REPO/scripts/inspect_workflow_inputs.sh"
copy_file "$SOURCE_ROOT/scripts/trigger_existing_workflow.sh" "$TARGET_REPO/scripts/trigger_existing_workflow.sh"
copy_file "$SOURCE_ROOT/scripts/notify.sh" "$TARGET_REPO/scripts/notify.sh"
chmod +x "$TARGET_REPO/scripts/inspect_workflow_inputs.sh" "$TARGET_REPO/scripts/trigger_existing_workflow.sh" "$TARGET_REPO/scripts/notify.sh"

# Fastlane + env template
copy_file "$SOURCE_ROOT/Gemfile" "$TARGET_REPO/Gemfile"
copy_file "$SOURCE_ROOT/fastlane/Appfile" "$TARGET_REPO/fastlane/Appfile"
copy_file "$SOURCE_ROOT/fastlane/Fastfile" "$TARGET_REPO/fastlane/Fastfile"
copy_file "$SOURCE_ROOT/fastlane/Matchfile" "$TARGET_REPO/fastlane/Matchfile"
copy_file "$SOURCE_ROOT/fastlane/Pluginfile" "$TARGET_REPO/fastlane/Pluginfile"
copy_file "$SOURCE_ROOT/.env.example" "$TARGET_REPO/.env.example"
copy_file "$SOURCE_ROOT/CICD_HOT_RUN_SETUP.md" "$TARGET_REPO/CICD_HOT_RUN_SETUP.md"

replace_in_file() {
  local path="$1"
  local old="$2"
  local new="$3"
  ruby -e 'path, old, newv = ARGV; c = File.read(path); c2 = c.gsub(old, newv); File.write(path, c2)' "$path" "$old" "$new"
}

# Rewire copied defaults for target project.
replace_in_file "$TARGET_REPO/.github/cicd.env.config.yml" "CI_CD_Project.xcodeproj" "$PROJECT_FILE"
replace_in_file "$TARGET_REPO/.github/cicd.env.config.yml" "CI_CD_Project" "$SCHEME"
replace_in_file "$TARGET_REPO/.github/cicd.env.config.yml" "com.example.app" "$BUNDLE_ID"

replace_in_file "$TARGET_REPO/fastlane/Fastfile" "CI_CD_Project.xcodeproj" "$PROJECT_FILE"
replace_in_file "$TARGET_REPO/fastlane/Fastfile" "CI_CD_Project" "$SCHEME"
replace_in_file "$TARGET_REPO/fastlane/Fastfile" "cicd.xcodeproj" "$PROJECT_FILE"
replace_in_file "$TARGET_REPO/fastlane/Fastfile" "\"cicd\"" "\"$SCHEME\""

replace_in_file "$TARGET_REPO/.github/pipeline-templates/ios-fastlane-workflow.template.yml" "CI_CD_Project.xcodeproj" "$PROJECT_FILE"
replace_in_file "$TARGET_REPO/.github/pipeline-templates/ios-fastlane-workflow.template.yml" "CI_CD_Project" "$SCHEME"

replace_in_file "$TARGET_REPO/.env.example" "com.example.app" "$BUNDLE_ID"

# Ensure project defaults exist in .env.example.
if ! grep -q '^CICD_PROJECT_FILE=' "$TARGET_REPO/.env.example"; then
  cat >> "$TARGET_REPO/.env.example" <<EOF

# Project defaults
CICD_PROJECT_FILE=$PROJECT_FILE
CICD_DEFAULT_SCHEME=$SCHEME
CICD_DEFAULT_CONFIGURATION=$CONFIGURATION
CICD_TEST_DESTINATION=$TEST_DESTINATION
EOF
else
  replace_in_file "$TARGET_REPO/.env.example" "CICD_PROJECT_FILE=CI_CD_Project.xcodeproj" "CICD_PROJECT_FILE=$PROJECT_FILE"
  replace_in_file "$TARGET_REPO/.env.example" "CICD_DEFAULT_SCHEME=CI_CD_Project" "CICD_DEFAULT_SCHEME=$SCHEME"
  replace_in_file "$TARGET_REPO/.env.example" "CICD_DEFAULT_CONFIGURATION=Debug" "CICD_DEFAULT_CONFIGURATION=$CONFIGURATION"
  replace_in_file "$TARGET_REPO/.env.example" "CICD_TEST_DESTINATION=platform=iOS Simulator,name=iPhone 15" "CICD_TEST_DESTINATION=$TEST_DESTINATION"
fi

echo "Bootstrap complete"
echo "Target repo: $TARGET_REPO"
echo "Detected project file: $PROJECT_FILE"
echo "Detected scheme: $SCHEME"
echo "Bundle identifier: $BUNDLE_ID"
echo
echo "Next:"
echo "1) cp .env.example .notification.local.env"
echo "2) Fill local values in .notification.local.env"
echo "3) Add GitHub Actions Secrets/Variables"
