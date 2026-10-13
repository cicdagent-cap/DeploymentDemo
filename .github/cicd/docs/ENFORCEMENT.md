# Enforcement: Host vs Kit

## Critical honesty

An **agent-writable scope file is not an independent security boundary**.

| Layer | What it does |
|-------|----------------|
| **Host** | Human approval; minting and withholding a secret the agent cannot read or invent (`CICD_HOST_APPROVAL_TOKEN` or equivalent); refusing unauthorized shell; CI secret permissions |
| **Kit** | Fail-closed checks in `harness/require_approval.sh` when invoked: action, repo, paths, env, destination, expiry, issuer, optional `host_token`, proposal_hash, rejects in-repo scopes unless `CICD_ALLOW_REPO_SCOPE=1` |
| **Markdown prompts** | Instructions only — not executable enforcement |

**Host approval is an independent boundary only when the agent cannot access or mint the approval credential.** An external file path, `issuer: human` label, or “scope kept outside the repo” alone does **not** prevent manufactured approval if the agent can write that file or invent the same fields. When `CICD_HOST_APPROVAL_TOKEN` is unset, the kit still enforces structural checks but **cannot** prove a human authored the scope. Set a host-only token (env/secret the agent cannot write) for production use.

## Entry points that call the gate

| Script | Action | Notes |
|--------|--------|-------|
| `generate_pipeline.sh` | `generate_pipeline` | Requires path + destination (+ environment if pinned) |
| `generate_jenkins_pipeline.sh` | `generate_pipeline` | Same |
| `apply_approved_patch.sh` | `apply_patch` | Requires proposal_hash when bound |
| `sync_kit_diff.sh --apply-paths` | `apply_patch` | Per path |
| `trigger_existing_workflow.sh` | `workflow_dispatch` | Unscoped bypass requires host token + explicit flag |
| `trigger_jenkins_job.sh` | `jenkins_dispatch` | |
| `notify.sh` (local) | `notification` | Skipped gate inside `GITHUB_ACTIONS=true` (workflow must already gate jobs) |

Direct invocation of helpers **without** going through these scripts can bypass the gate (e.g. raw `gh workflow run`, raw `curl` to Jenkins). That is a **host** control problem.

## Heuristics (not proof)

- Workflow behavior scanning in `recommend_pipeline_action.sh` uses **keyword/regex heuristics** on YAML text (e.g. `upload_to_testflight`, `fastlane … test`). It is not a full semantic parse of jobs/steps.
- Duplicate/in-flight dispatch guards in `trigger_existing_workflow.sh` use **title-based heuristics** (`displayTitle` / `name` vs preset). They are best-effort and can false-positive or miss input-identical runs.

## Stale / unrelated scopes

Denied when: expired; wrong `repo_root`; wrong `repo_head` when set; action not listed; path outside `allowed_paths`; destination/environment mismatch; `proposal_hash` mismatch; `issuer` not `human`/`host`; in-repo scope without allow; `host_token` mismatch when host token is set.
