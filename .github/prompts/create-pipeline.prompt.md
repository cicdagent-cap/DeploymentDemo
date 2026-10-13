# Create / Update Pipeline Flow

Preserve this mode name for orchestrators: **Create Pipeline**.

## Step 0: Inspect first

Unless a fresh inspect report exists for this repo:

```bash
./scripts/inspect_repo.sh --repo <path> --format json
./scripts/detect_project_platform.sh --repo <path> --format json
```

Apply existing-vs-new rules from `agent/CICD.agent.md`. Prefer reuse or targeted extension over a new workflow.

Obtain approval for the file change set before writing files.

Prefer kit tools (enforced where implemented):

```bash
./scripts/validate_request.sh --request <request.yml> --repo <path>
./scripts/recommend_pipeline_action.sh --repo <path> --request <request.yml>
./scripts/propose_changes.sh --repo <path> --request <request.yml>
# After approved-scope file:
./scripts/generate_pipeline.sh --repo <path> --request <request.yml> --scope-file <scope.yml>
# or Jenkins:
./scripts/generate_jenkins_pipeline.sh --repo <path> --request <request.yml> --scope-file <scope.yml>
```

Or drive Inspect→Plan via `./harness/run_loop.sh` (stops at await_approval unless `--apply` + scope).

---

## Step 1: Collect scope

Ask only what remains unresolved:

1. Pipeline name (example: Demo_Pipeline)
2. Output YAML path or folder
3. Approved capabilities (from `capabilities/catalog.yml`) — do not enable signing/distribution/release unless requested
4. Provider: `github_actions` (default). Jenkins is contract-only until implemented.
5. Runner label (discover or ask — never silently replace an existing project runner)
6. Optional: presets/variants paths, config overrides, reusable workflow reference

Request file (optional): `requests/pipeline-request.yml`

---

## Step 2: Resolve file path

IF user gives full file path → use as-is  
IF folder only → `<folder>/<pipeline-name-kebab>.yml`

If the output file already exists → propose update diff; do not overwrite without approval.

---

## Step 3: Generate or update YAML

Primary template: `templates/mobile-ci-workflow.template.yml`

Placeholders:

| Placeholder | Value |
|-------------|-------|
| `__PIPELINE_NAME__` | User input |
| `__RUNNER_LABEL__` | Discovered or user-approved runner (iOS/macOS targets) |
| `__DEFAULT_BRANCH__` | Detected default branch or user value |
| `__DEFAULT_PROJECT_FILE__` | Full relative path when known |
| `__DEFAULT_SCHEME__` | Verified or user-selected scheme |
| `__NOTIFICATIONS_ENABLED__` | `true` / `false` (default false unless approved) |

Optional patterns (only if approved):

- Presets/variants: copy examples from `templates/presets.example.json` / `variants.example.json` and customize
- Config overrides: `config-overrides/config_overrides.json`
- Thin entry → reusable: `templates/entry-reusable-workflow.template.yml`

Rules:

- Notifications optional and non-blocking
- Do not put signing/upload secrets on PR/unsigned jobs
- Release build configuration ≠ production environment
- Android release tasks must not silently fall back to debug
- iOS unsigned CI must not claim archive/upload success

Legacy iOS-only template `templates/ios-fastlane-workflow.template.yml` is deprecated — use only for explicit backward compatibility.

---

## Step 4: Validate (static)

```bash
./scripts/validate_kit.sh --repo <target-or-kit-path>
```

---

## Step 5: Output

```
Pipeline created or updated
File: <path>
Platform: <detected>
Capabilities enabled: <list>
Missing configuration: <variables/secrets by capability>
Next: commit/push and workflow dispatch require separate approval
```
