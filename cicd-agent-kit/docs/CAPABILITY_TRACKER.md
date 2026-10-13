# Capability Tracker

Legend: **Implemented** · **Locally tested** · **Integration tested** · **Blocked** · **Not yet implemented**

Updated after v1.2.0 implementation review (eval suite 23 assertions).

| Capability | Status | Evidence / blocker |
|------------|--------|--------------------|
| Inspect mode (scripts) | Implemented + Locally tested | `inspect_repo.sh`, evals |
| Plan mode (propose/recommend/validate request) | Implemented + Locally tested | propose/recommend/validate_request; loop plan phase |
| Create/update GHA pipeline (capability-aware) | Implemented + Locally tested (dry-run) | `generate_pipeline.sh` dry-run in evals |
| Create/update Jenkinsfile | Implemented + Locally tested (static) | `generate_jenkins_pipeline.sh`, `validate_jenkins.sh` |
| Validate (static kit + config dimensions) | Implemented + Locally tested | validate_kit/request/configuration/jenkins |
| Trigger GHA + monitor | Implemented; Integration **Blocked** | Needs approved scope + `gh` auth + workflow dispatch approval |
| Trigger Jenkins + monitor | Implemented; Integration **Blocked** | Needs `JENKINS_USER`/`JENKINS_TOKEN` + job URL + approval |
| Approval scope enforcement | Implemented + Locally tested | `require_approval.sh` evals |
| Harness loop / trace / checkpoint | Implemented + Locally tested | checkpoint redaction eval |
| Selective sync diff | Implemented + Locally tested | `sync_kit_diff.sh` |
| Selective sync apply | Implemented; apply **Blocked** pending path approval | requires scope + `--apply-paths` |
| Fastlane lane hard-fail | Implemented + Locally tested | `verify_fastlane_lanes.sh` |
| iOS/Android/Flutter/RN lanes in kit Fastfile | Implemented; build Integration **Blocked** | needs runner/deps approval |
| TestFlight path | Implemented in Fastfile (gated); Integration **Blocked** | ASC credentials + approval |
| Firebase ADC path | Implemented in Fastfile/template; Integration **Blocked** | Firebase SA + approval |
| Google Play supply path | Implemented in Fastfile (gated); Integration **Blocked** | Play JSON key + approval |
| Presets/variants examples | Template/example only until project copies | not auto-executable |
| Evals suite | Implemented + Locally tested | `evals/run_evals.sh` |
| Real build/test on CI runner | Not yet integration-tested | blocked: dispatch approval + runner |
| Clean-checkout CI scheme verify | Not yet integration-tested | blocked: CI runner access |
| Embeddings / fine-tuning | Not implemented (intentionally deferred) | no demonstrated need |
