# Jenkins Support

## Status: implemented (generation + local inspect/validate; remote API when credentials provided)

| Function | Script | Local | Remote |
|----------|--------|-------|--------|
| Generate Jenkinsfile | `scripts/generate_jenkins_pipeline.sh` | Yes (requires approved scope unless `--dry-run`) | n/a |
| Inspect job/file | `scripts/inspect_jenkins_job.sh` | Jenkinsfile parse | API when `JENKINS_USER`/`JENKINS_TOKEN`/`--job-url` |
| Trigger | `scripts/trigger_jenkins_job.sh` | `--dry-run` | `buildWithParameters` + crumb |
| Monitor | `scripts/monitor_jenkins_build.sh` | n/a | Queue/build polling |
| Validate | `scripts/validate_jenkins.sh` | Static | n/a |

Template: `providers/jenkins/templates/Jenkinsfile.mobile.template`

Credential bindings use Jenkins credential **IDs** only. Presence of an ID does not prove auth works.

## Blocked without

- `JENKINS_USER`, `JENKINS_TOKEN`, job URL for remote trigger/monitor
- Approved scope action `jenkins_dispatch` for real triggers
