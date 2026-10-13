# CI/CD Hot Run Setup (Multi-Platform)

First-time onboarding checklist. Notifications are optional.

## Hot Run Order

1. Install or sync the kit (`install.sh` — idempotent; `--force` only when approved).
2. Inspect: `./scripts/inspect_repo.sh` and `./scripts/detect_project_platform.sh`.
3. Verify iOS schemes when applicable: `xcodebuild -list -project|-workspace ...` (missing shared `.xcscheme` files means verification is needed, not automatic absence).
4. Configure `.env.example` → `.notification.local.env` only if notifications are desired.
5. Set GitHub Variables/Secrets for approved capabilities only.
6. Static validate: `./scripts/validate_kit.sh`.
7. Create/update pipeline only after Plan approval.
8. Workflow dispatch / builds / uploads require separate approval.

## Starter files (after install)

- `.github/agents/CICD.agent.md`
- `.github/prompts/*.md` (inspect, plan, create-pipeline, validate, trigger-build)
- `.github/pipeline-templates/mobile-ci-workflow.template.yml`
- `.github/pipeline-templates/entry-reusable-workflow.template.yml`
- `.github/pipeline-templates/presets.example.json` / `variants.example.json`
- `scripts/inspect_repo.sh`, `validate_kit.sh`, `detect_project_platform.sh`, …
- `CICD_JENKINS.md` (status: contract only)

## Runner labels

Suggested defaults (`macos-latest` / `ubuntu-latest`) are not authoritative. Discover or ask for project runners. Never silently replace an existing configured label (for example a self-hosted Mac label already used by the project).

## Firebase (optional)

Prefer `GOOGLE_APPLICATION_CREDENTIALS` (service account JSON path / ADC). `FIREBASE_CLI_TOKEN` is compatibility-only.

## Jenkins

Not executable in this kit version. See `docs/JENKINS.md`.
