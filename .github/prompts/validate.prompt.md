# Validate Mode

## Goal

Statically validate kit and/or generated pipeline contracts. Do not dispatch workflows, install dependencies, run builds/tests, upload, or notify unless the user separately approves those actions.

## Steps

1. Run:

```bash
./scripts/validate_kit.sh --kit-root <path-to-cicd-agent-kit>
```

If validating an installed target repo:

```bash
./scripts/validate_kit.sh --repo <target-repo>
```

2. Report separately:
   - Changes under review (paths)
   - Static validation results
   - Unresolved placeholders
   - Referenced scripts/lanes/templates
   - What was **not** tested (builds, uploads, live credentials)

3. Valid YAML alone does not prove a working pipeline. List recommended next verification steps that require approval (local build/test, workflow dispatch, signing/upload checks).

## Output

```yaml
status: pass | fail | partial
checks: []
blockers: []
recommended_approved_next_steps: []
```
