# CI/CD Hot Run Setup (Generic)

Use this as the first step whenever onboarding a new iOS repository to this CI/CD agent.

## Goal

Make pipeline creation and build triggering work on day 0 with minimum rework.

## Hot Run Order (Run In This Sequence)

1. Run the bootstrap script to copy and auto-map CI/CD files.
2. Configure local environment template and local env file.
3. Set project-specific defaults (project file, scheme, bundle id, simulator destination).
4. Configure GitHub Actions Variables and Secrets.
5. Validate with one manual trigger.
6. Start normal use of the CICD agent modes.

## 0) Recommended One-Command Bootstrap

Run from the CICD template repo:

```bash
./scripts/bootstrap_new_ios_repo.sh <target-repo-path> <bundle-id>
```

Example:

```bash
./scripts/bootstrap_new_ios_repo.sh /Users/you/projects/MyiOSApp com.example.myiosapp
```

This command:

- copies the required starter files
- auto-detects `<YourProject>.xcodeproj`
- sets scheme defaults from project name
- rewrites copied defaults in CI/CD config and Fastlane files

## 1) Starter Files Checklist

Required folders/files:

- .github/agents/CICD.agent.md
- .github/prompts/create-pipeline.prompt.md
- .github/prompts/trigger-build.prompt.md
- .github/pipeline-templates/ios-fastlane-workflow.template.yml
- .github/workflows/ios-ci.yml (or your generated workflow)
- .github/cicd.config.yml
- .github/cicd.env.config.yml
- .github/pipeline-request.yml
- .github/trigger-build-request.yml
- .github/config-overrides/config_overrides.json
- scripts/inspect_workflow_inputs.sh
- scripts/trigger_existing_workflow.sh
- scripts/notify.sh
- fastlane/Appfile
- fastlane/Fastfile
- fastlane/Matchfile
- fastlane/Pluginfile
- Gemfile
- .env.example

## 2) Local Environment Bootstrap

Run from repo root:

```bash
cp .env.example .notification.local.env
```

Fill `.notification.local.env` with real local values (never commit this file):

- TEAM_WEBHOOK_URL
- CICD_CHAT_PROVIDER (teams, slack, generic)
- FASTLANE_TEAM_ID
- FASTLANE_ITC_TEAM_ID
- FASTLANE_BUNDLE_IDENTIFIER
- MATCH_GIT_URL
- MATCH_PASSWORD
- MATCH_GIT_BASIC_AUTHORIZATION
- APP_STORE_CONNECT_API_KEY (if release/testflight lanes need it)
- FIREBASE_APP_ID (if firebase distribution is used)
- FIREBASE_CLI_TOKEN (if firebase distribution is used)

## 3) Project Mapping (Must Update)

Map these values to your new project:

- CICD_PROJECT_FILE -> <YourProject>.xcodeproj
- CICD_DEFAULT_SCHEME -> <YourScheme>
- CICD_DEFAULT_CONFIGURATION -> Debug (or your default)
- CICD_TEST_DESTINATION -> platform=iOS Simulator,name=<Device>
- FASTLANE_BUNDLE_IDENTIFIER -> <your.bundle.id>

Update in:

- .github/cicd.env.config.yml
- .env.example
- fastlane/Fastfile fallback defaults
- fastlane/Appfile
- fastlane/Matchfile

## 4) GitHub Actions Setup (Repo Settings)

Path:

- Settings -> Secrets and variables -> Actions

Create Variables:

- CICD_PROJECT_FILE
- CICD_DEFAULT_SCHEME
- CICD_DEFAULT_CONFIGURATION
- CICD_TEST_DESTINATION
- FASTLANE_BUNDLE_IDENTIFIER
- CICD_CHAT_PROVIDER
- FIREBASE_GROUPS (if needed)

Create Secrets:

- TEAM_WEBHOOK_URL
- FASTLANE_TEAM_ID
- FASTLANE_ITC_TEAM_ID
- MATCH_GIT_URL
- MATCH_PASSWORD
- MATCH_GIT_BASIC_AUTHORIZATION
- APP_STORE_CONNECT_API_KEY
- FIREBASE_APP_ID (if needed)
- FIREBASE_CLI_TOKEN (if needed)

## 5) Validation Commands

Check workflow inputs:

```bash
./scripts/inspect_workflow_inputs.sh <workflow-url> <branch>
```

Trigger workflow:

```bash
./scripts/trigger_existing_workflow.sh <workflow-url> <branch> preset=Debug-CICD
```

Expected output contains:

- Environment: Configured via local file or GitHub
- Build triggered successfully
- Run URL

If env is missing, expected message:

```text
Missing env setup
Run: cp .env.example .notification.local.env
```

## 6) Operational Rule

For every new project, run this Hot Run setup before using:

- Create Pipeline mode
- Trigger Build mode

This prevents most first-run failures (scheme mismatch, missing secrets, and signing issues).
