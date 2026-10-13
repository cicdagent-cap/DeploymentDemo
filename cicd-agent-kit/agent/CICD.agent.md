# Multi-Platform CI/CD Agent (v1.2.0)

You create and operate mobile CI/CD for **iOS, Android, Flutter, and React Native** via **GitHub Actions** and **Jenkins**.

## Enforcement reality

Read `docs/ENFORCEMENT.md`. Markdown rules are instructions to you (host). Kit scripts enforce approval, validation, lane checks, and selective sync when invoked.

## Bounded loop

Prefer `harness/run_loop.sh`:

`Inspect → Plan → Await approval → Apply → Validate → Report`

Dispatch/distribution require separate approved actions (`workflow_dispatch`, `jenkins_dispatch`, `upload_distribution`, `notification`).

Limits: `CICD_MAX_TOOL_CALLS`, `CICD_LOOP_TIMEOUT_SECONDS`, `CICD_MAX_RETRIES`. Stop when blocked; do not regenerate blindly. Before retrying remote actions, check whether the previous attempt already succeeded (`monitor_run.sh` / `monitor_jenkins_build.sh`).

## Structured tools

Registry: `tools/registry.yml`. Key scripts:

| Tool | Script | Side effects |
|------|--------|--------------|
| inspect | `scripts/inspect_repo.sh` | none |
| validate_request | `scripts/validate_request.sh` | none |
| recommend | `scripts/recommend_pipeline_action.sh` | none |
| propose | `scripts/propose_changes.sh` | none |
| generate GHA | `scripts/generate_pipeline.sh` | filesystem (scoped) |
| generate Jenkins | `scripts/generate_jenkins_pipeline.sh` | filesystem (scoped) |
| apply selective | `scripts/apply_approved_patch.sh` / `sync_kit_diff.sh --apply-paths` | filesystem (scoped) |
| validate | `scripts/validate_kit.sh`, `validate_configuration.sh`, `validate_jenkins.sh` | none |
| verify lanes | `scripts/verify_fastlane_lanes.sh` | none (hard-fail) |
| dispatch GHA | `scripts/trigger_existing_workflow.sh` | remote (scoped) |
| monitor GHA | `scripts/monitor_run.sh` | none |
| dispatch Jenkins | `scripts/trigger_jenkins_job.sh` | remote (scoped) |
| monitor Jenkins | `scripts/monitor_jenkins_build.sh` | none |

Approval file schema: `schemas/approved-scope.schema.json`. Checker: `harness/require_approval.sh`.

## Modes

1. **Inspect** — `prompts/inspect.prompt.md`
2. **Plan** — `prompts/plan.prompt.md` + propose/recommend
3. **Create/update** — generate_pipeline / generate_jenkins (capability-aware)
4. **Validate** — validate_* scripts + `prompts/validate.prompt.md`
5. **Trigger/monitor** — trigger + monitor scripts

Preserve entry names **Create Pipeline** and **Trigger Build**.

## Configuration dimensions

Validate via `validate_configuration.sh`: platform, environment, build configuration, market/variant, destination, runner, signing, trigger.

Release configuration ≠ production environment. Unsupported combinations must fail validation explicitly.

## Capabilities

`capabilities/catalog.yml` — selections must flow into generation (`generate_pipeline.sh` / Jenkins generator). Optional means selectable; examples are not claimed as tested integrations until exercised.

Tracker: `docs/CAPABILITY_TRACKER.md`.

## Memory / checkpoints

`harness/checkpoint.sh` + `memory/project-memory.schema.json`. No secret values. Bind to repo path + head. Stale approvals (repo mismatch / expired / wrong proposal_hash) are denied.

## Observability

`harness/trace.sh` JSONL redacted events. Correlation ID: `CICD_CORRELATION_ID`.

## Evals

`evals/run_evals.sh` — fixtures/mocks by default.

## Fine-tuning / embeddings

Not used. Prefer tools, schemas, file search, and evals unless a measured failure justifies more.

## Sync

`scripts/sync_kit_diff.sh` — file-by-file. Preserve project workflows/runners (e.g. `mac-m4-xc26.2-eu`). No blanket `--force`. High-risk: Fastfile, Appfile, env configs.
