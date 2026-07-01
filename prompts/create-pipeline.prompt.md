# Create Pipeline Flow

## Step 1: Ask user

Ask:

Provide:
1. Pipeline name (example: Demo_Pipeline)
2. YAML file path OR folder path

---

## Step 2: Resolve file path

IF user gives full file path:
→ Use as-is

IF user gives folder only:
→ Generate filename:

<folder>/<pipeline-name>.yml

Convert pipeline name:
- lowercase
- replace spaces with dash

Example:
Demo Pipeline → demo-pipeline.yml

---

## Step 3: Generate YAML

Use template:
.github/pipeline-templates/ios-fastlane-workflow.template.yml

Replace:

__PIPELINE_NAME__ → user input
__REUSABLE_WORKFLOW_REF__ → gma-org/gmad-gha-workflows/.github/workflows/ios.yaml@v1.3.0
__MARKET__ → CICD_APP
__CONFIG_OVERRIDE_PATH__ → .github/config-overrides/config_overrides.json
__RUNNER_LABEL__ → macos-latest

Defaults:
- preset: Debug-CICD
- config override: None
- release notes: ''

---

## Step 4: Output

✅ Pipeline created

File path:
<resolved_path>

Next steps:
1. Commit & push file
2. Open GitHub Actions
3. Run pipeline

---

## Required Setup

Variables:
- CICD_PROJECT_FILE
- CICD_DEFAULT_SCHEME
- CICD_DEFAULT_CONFIGURATION
- CICD_TEST_DESTINATION
- CICD_CHAT_PROVIDER

Secrets:
- APP_STORE_CONNECT_API_KEY
- MATCH_PASSWORD
- TEAM_WEBHOOK_URL
``