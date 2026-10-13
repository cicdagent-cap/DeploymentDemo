# CI/CD Agent — Integration Guide

## 1. Overview

Specialist agent modes: **Inspect → Plan → Create/update → Validate → Trigger/monitor**.

Backward-compatible entry points: **Create Pipeline**, **Trigger Build**.

Providers:

| Provider | Status |
|----------|--------|
| GitHub Actions | Implemented |
| Jenkins | Contract only — [docs/JENKINS.md](./docs/JENKINS.md) |

```
Orchestrator --request YAML--> CI/CD Agent --scripts/templates--> run URL / workflow path / inspect report
```

## 2. Installation

```bash
./cicd-agent-kit/install.sh <absolute-path-to-mobile-repo> [app-identifier]
```

Idempotent: existing files are **skipped** unless `--force` (writes `.bak-cicd-kit` backups). Use `--dry-run` to preview.

## 3. Registering the agent

### Cursor / IDE

1. Copy or reference `agent/CICD.agent.md` (install maps to `.github/agents/CICD.agent.md`).
2. Copy prompts to `.github/prompts/`.
3. Invoke with agent name **CICD** and mode keywords. Path registration is not universal across all tools — confirm how your IDE loads custom agents.

### Orchestrator metadata

| Field | Value |
|-------|-------|
| `agent_id` | `cicd` |
| `version` | `1.1.0` |
| `capabilities` | `inspect`, `plan`, `create-pipeline`, `validate`, `trigger-build`, `detect-platform` |
| `definition` | `cicd-agent-kit/agent/CICD.agent.md` |

## 4. Handoff contracts

See [docs/AGENT_HANDOFF.md](./docs/AGENT_HANDOFF.md) and `requests/*.yml`.

### Detect / inspect

```bash
./scripts/detect_project_platform.sh --repo <path> --format json
./scripts/inspect_repo.sh --repo <path> --format json
```

## 5. Keys and secrets

### Optional notifications (all platforms)

| Name | Type | Required? | Purpose |
|------|------|-----------|---------|
| `TEAM_WEBHOOK_URL` | Secret | **No** | Chat webhook |
| `CICD_CHAT_PROVIDER` | Variable | No | `teams` / `slack` / `generic` |
| `CICD_NOTIFICATIONS_ENABLED` | Variable | No | `true` to enable workflow notify jobs |

Making the webhook non-mandatory is **not** a breaking interface change: triggers and builds succeed without it.

### Common

| Name | Type | Purpose |
|------|------|---------|
| `CICD_PLATFORM` | Variable | `auto` or forced platform |

### iOS (build variables)

`CICD_PROJECT_FILE` (prefer full relative path), `CICD_DEFAULT_SCHEME`, `CICD_DEFAULT_CONFIGURATION`, `CICD_TEST_DESTINATION`, `FASTLANE_BUNDLE_IDENTIFIER`

Signing/distribution secrets are **capability-gated** (`CICD_USE_MATCH`, `CICD_UPLOAD_TESTFLIGHT`): `FASTLANE_TEAM_ID`, Match secrets, `APP_STORE_CONNECT_API_KEY`, etc.

### Android

`CICD_GRADLE_DIR`; keystore secrets only for release signing capabilities.

### Firebase App Distribution (optional)

**Preferred:** service account / ADC — set `GOOGLE_APPLICATION_CREDENTIALS` to a JSON key file path in the runner environment ([Firebase: Authenticate with a service account](https://firebase.google.com/docs/app-distribution/authenticate-service-account)).

**Compatibility only:** `FIREBASE_CLI_TOKEN` — limited; Firebase CLI documents migration away from long-lived CI tokens toward service accounts.

Also: `FIREBASE_APP_ID`, `FIREBASE_GROUPS`, `CICD_DISTRIBUTE_FIREBASE=true`.

SDK installation is not required for CLI-based distribution.

## 6. Presets, variants, reusable workflows

Optional project-configurable files:

- `templates/presets.example.json`
- `templates/variants.example.json`
- `config-overrides/config_overrides.json`
- `templates/entry-reusable-workflow.template.yml` (thin entry → reusable workflow ref)

Do not ship organization-specific markets, branches, or secret names as defaults.

## 7. External tools

| Tool | When |
|------|------|
| GitHub CLI (`gh`) ≥ 2.87 recommended | Trigger Build (run URL via API details when available) |
| Ruby + Bundler | Fastlane jobs |
| Xcode / Java 17 / Flutter / Node | Per platform |

## 8. Validation

```bash
./scripts/validate_kit.sh --kit-root ./cicd-agent-kit --repo <target>
```

Static only. Valid YAML ≠ working pipeline.

## 9. Security notes

- Never commit secrets.
- Keep signing/upload secrets off unsigned PR jobs.
- Prefer read-only Match in CI when Match is enabled.
- Notifications must remain non-blocking.
- Do not `eval` detection output (install.sh uses safe KEY=VALUE parsing).

## Sources

- [GitHub changelog: workflow dispatch returns run IDs](https://github.blog/changelog/2026-02-19-workflow-dispatch-api-now-returns-run-ids/)
- [gh workflow run](https://cli.github.com/manual/gh_workflow_run)
- [Firebase App Distribution service account auth](https://firebase.google.com/docs/app-distribution/authenticate-service-account)
