# CICD Starter Kit (Multi-Platform)

Supports **iOS, Android, Flutter, and React Native** with automatic platform detection.

## Integration kit (for multi-agent setups)

All portable agent files live in **`cicd-agent-kit/`**. See:

- [cicd-agent-kit/README.md](cicd-agent-kit/README.md) — folder structure
- [cicd-agent-kit/INTEGRATION.md](cicd-agent-kit/INTEGRATION.md) — keys, secrets, wiring with other agents
- [cicd-agent-kit/docs/AGENT_HANDOFF.md](cicd-agent-kit/docs/AGENT_HANDOFF.md) — input/output contracts

Install into any mobile repo:

```bash
./cicd-agent-kit/install.sh <target-repo-path> [app-identifier]
```

## Quick start (single repo)

1. Unzip this package.
2. Bootstrap into your project repo:

```bash
./scripts/bootstrap_new_repo.sh <target-repo-path> [app-identifier]
```

3. In the target repo, start the CICD agent:

```
CI_CD
Create Pipeline
```

4. Set local env and GitHub Secrets/Variables (see `CICD_HOT_RUN_SETUP.md`).

## Verify detection

```bash
./scripts/detect_project_platform.sh
```

## Legacy

`bootstrap_new_ios_repo.sh` still works — it delegates to `bootstrap_new_repo.sh`.
