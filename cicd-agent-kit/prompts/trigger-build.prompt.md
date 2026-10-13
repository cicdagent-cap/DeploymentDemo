# Trigger / Monitor Build Flow

Preserve this mode name for orchestrators: **Trigger Build**.

Workflow dispatch, notifications, and continuous monitoring each require **explicit approval**. Do not treat a real workflow dispatch as a dry-run.

## Step 1: Collect target

Provide (no organization-specific defaults):

1. Workflow URL (GitHub Actions), **or** Jenkins job identifier if/when Jenkins adapter is implemented
2. Branch / ref name
3. Whether to monitor until completion (optional; default no)
4. Whether to send notifications (optional; default no)

Optional request file: `requests/trigger-build-request.yml`

If Jenkins is selected: stop and report that Jenkins triggering is **not implemented** in this kit version — see `docs/JENKINS.md`.

---

## Step 2: Inspect workflow inputs

```bash
./scripts/inspect_workflow_inputs.sh <workflow-url> <branch>
```

---

## Step 3: Collect inputs dynamically

Show only discovered inputs. Do not invent preset names.

---

## Step 4: Trigger (GitHub Actions)

Requires approved scope action `workflow_dispatch` (kit fail-closed via `harness/require_approval.sh` unless `CICD_ALLOW_UNSCOPED_DISPATCH=1`).

```bash
export CICD_APPROVED_SCOPE_FILE=/path/to/approved-scope.yml
./scripts/trigger_existing_workflow.sh \
  <workflow-url> \
  <branch> \
  preset=<value> \
  key=value...
./scripts/monitor_run.sh <run-url-or-id> [owner/repo]
```

Jenkins:

```bash
./scripts/trigger_jenkins_job.sh <job-url> PRESET=Debug-CICD --scope-file "$CICD_APPROVED_SCOPE_FILE"
./scripts/monitor_jenkins_build.sh <queue-or-build-url>
```

The script correlates the created run via GitHub CLI/API when available, with a polling fallback. Duplicate detection considers recent runs for the same workflow, ref, and overlapping inputs when possible.

Missing local notification env must **not** block dispatch.

---

## Step 5: Monitor (optional)

Only if approved:

```bash
gh run watch <run-id> --repo <owner/repo>
# or
gh run view <run-id> --repo <owner/repo>
```

Report terminal status separately from dispatch success.

---

## Step 6: Notifications (optional)

Only if approved and `TEAM_WEBHOOK_URL` (or configured provider webhook) is available:

- Workflow-level `scripts/notify.sh` may already notify from CI (non-blocking).
- Local notify after trigger is optional and must not be required for a successful trigger.

If webhook missing: report notifications disabled — not a trigger failure.

---

## Output

```yaml
status: triggered | skipped | failed
run_url: <url-or-null>
correlation: api_run_details | poll_fallback | unavailable
notifications: disabled | skipped_unapproved | sent
monitor: not_requested | completed:<status> | not_approved
```
