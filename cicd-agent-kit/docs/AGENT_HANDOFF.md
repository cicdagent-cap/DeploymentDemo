# Agent Handoff Contract

```yaml
agent_id: cicd
name: CI/CD Agent
version: 1.1.0
definition: agent/CICD.agent.md
```

## Capabilities

### `inspect` / `detect-platform`

```bash
./scripts/inspect_repo.sh --repo <path> --format json
./scripts/detect_project_platform.sh --repo <path> --format json
```

Detection includes candidates, confidence fields, and full relative project/workspace paths when found.

### `plan`

No script — follow `prompts/plan.prompt.md` using inspect output + `capabilities/catalog.yml`.

### `create-pipeline`

Input: `requests/pipeline-request.yml`  
Processing: detect → reuse/extend decision → template substitution → write (after approval) → validate.

### `validate`

```bash
./scripts/validate_kit.sh --kit-root <kit> [--repo <target>]
```

### `trigger-build`

Input: `requests/trigger-build-request.yml`  
```bash
./scripts/inspect_workflow_inputs.sh <workflow-url> <branch>
./scripts/trigger_existing_workflow.sh <url> <branch> key=value ...
```

Dispatch is a **real** workflow run. Missing notification env does not fail the trigger. Jenkins trigger is not implemented.

## Notifications

Optional. Non-blocking in templates. `TEAM_WEBHOOK_URL` is not mandatory for CI success or local trigger success.

## Error codes

| Code | Meaning |
|------|---------|
| `PLATFORM_UNKNOWN` | Could not identify project type |
| `GH_NOT_AUTHENTICATED` | `gh auth login` required |
| `DUPLICATE_RUN` | Active run skipped (intentional) |
| `INVALID_WORKFLOW_URL` | URL parsing failed |
| `JENKINS_NOT_IMPLEMENTED` | Provider selected but contract-only |
| `CORRELATION_UNAVAILABLE` | Dispatch accepted; run URL not yet known |
