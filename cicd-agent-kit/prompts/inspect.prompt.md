# Inspect Mode (read-only)

## Goal

Produce a structured discovery report. Do not create, edit, install, build, test, dispatch, upload, or notify.

## Steps

1. Confirm target repository path.
2. Run:

```bash
./scripts/inspect_repo.sh --repo <absolute-path> --format json
./scripts/detect_project_platform.sh --repo <absolute-path> --format json
```

3. Supplement with read-only file inspection:
   - Apps/platforms, Xcode/Gradle/Flutter/RN markers
   - Existing `.github/workflows`, Jenkinsfiles, Fastlane, presets/variants
   - Lockfiles (note reproducibility gaps; missing lockfile is not an automatic build blocker)
   - Credential **names** only — never print secret values
4. If iOS and `xcodebuild` is available, verify schemes:

```bash
xcodebuild -list -project <path>   # or -workspace <path>
```

Mark scheme status as verified / needs verification / unknown. A missing shared `.xcscheme` file is not proof that no scheme exists.

5. Classify findings: **Confirmed** / **Inferred** / **Unknown** with evidence paths.

## Output

```yaml
status: inspected
platform_candidates: []
ci_providers_found: []   # github_actions | jenkins | none
existing_pipelines: []
gaps: []
prerequisites: []
recommended_next_mode: plan
```

Ask only unresolved questions (multiple apps, platform ambiguity, runner choice). Then recommend **Plan**.
