# CI/CD Agent Kit v1.2.0

Portable agent kit for **iOS / Android / Flutter / React Native** with **GitHub Actions** and **Jenkins**.

## Quick commands

```bash
# Static validation
./scripts/validate_kit.sh --kit-root .

# Fixture evals (no remote side effects)
./evals/run_evals.sh

# Bounded loop through plan (stops for approval)
./harness/run_loop.sh --repo /path/to/app --request requests/pipeline-request.yml

# File-by-file sync diff (no overwrite)
./scripts/sync_kit_diff.sh --target /path/to/app
```

## Layout

- `agent/` `prompts/` — mode instructions (host-interpreted)
- `harness/` — approval, loop, trace, checkpoints (**kit-enforced**)
- `tools/registry.yml` — structured tool contracts
- `scripts/` — inspect, validate, generate, trigger, monitor, sync
- `providers/jenkins/` — Jenkins template + contract
- `evals/` — fixture/mock regression suite
- `docs/ENFORCEMENT.md` — host vs kit enforcement
- `docs/CAPABILITY_TRACKER.md` — implementation status

## Important limits

Static/fixture tests ≠ working CI builds, signing, or distribution. Local `xcodebuild -list` ≠ clean-checkout verification on the project CI runner. Templates/examples ≠ integration-tested destinations until exercised with approval.
