# Create Pipeline Flow

## Step 0: Detect platform

Run from repo root:

```bash
./scripts/detect_project_platform.sh
```

Use the detected platform to choose runner label and required variables. If detection fails, ask the user which platform they are targeting.

---

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

`<folder>/<pipeline-name>.yml`

Convert pipeline name:
- lowercase
- replace spaces with dash

Example:
Demo Pipeline → demo-pipeline.yml

---

## Step 3: Generate YAML

Use template:
`.github/pipeline-templates/mobile-ci-workflow.template.yml`

Replace placeholders:

| Placeholder | Value |
|-------------|-------|
| `__PIPELINE_NAME__` | User input |
| `__RUNNER_LABEL__` | `macos-latest` for iOS / Flutter-iOS / RN-iOS; use repo override if configured |
| `__DEFAULT_PROJECT_FILE__` | From detection or `CICD_PROJECT_FILE` |
| `__DEFAULT_SCHEME__` | From detection or `CICD_DEFAULT_SCHEME` |

Defaults:
- preset: Debug-CICD
- platform: auto-detect at runtime via `scripts/detect_project_platform.sh`
- release notes: ''

The generated workflow includes a `detect` job that auto-selects build steps for ios, android, flutter, or react-native.

---

## Step 4: Output

✅ Pipeline created

File path:
`<resolved_path>`

Detected platform: `<platform from detect script>`

Next steps:
1. Commit & push file
2. Set GitHub Actions Variables / Secrets for detected platform (see `.github/cicd.config.yml`)
3. Open GitHub Actions and run pipeline

---

## Required setup (by platform)

**All platforms:**
- `CICD_CHAT_PROVIDER`
- `TEAM_WEBHOOK_URL` (secret)

**iOS:**
- `CICD_PROJECT_FILE`, `CICD_DEFAULT_SCHEME`, `CICD_DEFAULT_CONFIGURATION`, `CICD_TEST_DESTINATION`
- `FASTLANE_BUNDLE_IDENTIFIER`, `MATCH_*`, `APP_STORE_CONNECT_API_KEY`

**Android:**
- `CICD_GRADLE_DIR`
- `ANDROID_KEYSTORE_*` (release signing)

**Flutter / React Native:**
- `CICD_BUILD_TARGET` (`android` or `ios`)
- `CICD_GRADLE_DIR` (Android target)
- iOS target also needs iOS signing secrets
