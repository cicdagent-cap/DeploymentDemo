# Trigger Build Flow

## Step 1: Ask user

Provide:
1. Workflow URL (default options):
   - https://github.com/gma-org/gmap-ios/actions/workflows/Core.yml
   - https://github.com/gma-org/gmap-ios/actions/workflows/DE.yml
   - Custom (input text field)
2. Branch name (default options):
   - staging-trunk
   - Custom (input text field)

---

## Step 2: Inspect workflow

Run:

./scripts/inspect_workflow_inputs.sh <workflow-url> <branch>

---

## Step 3: Ask inputs dynamically

Show only discovered inputs

Example:

Provide:

1. preset:
   - Debug-CICD
   - Release-CICD

2. config_Override:
   - None
   - a: Feature A Enabled

3. Release_Notes (optional)

---

## Step 4: Trigger build

Before triggering, check local environment setup through the trigger script output.

Show this when configured:

Environment: Configured via local file or GitHub

Show this when missing:

Missing env setup
Run: cp .env.example .notification.local.env

Run:

./scripts/trigger_existing_workflow.sh \
<workflow-url> \
<branch> \
preset=<value> \
config_Override=<value> \
Release_Notes="<value>"

---

## Step 5: Output

Build triggered successfully

Run URL: <github-run-url>

---

## Notifications

IF TEAM_WEBHOOK_URL exists in `.notification.local.env`, local shell env, or GitHub Secrets:
→ Notify team when build is triggered, then monitor build status in background and notify again on completion with:
  - Status (success, failure, cancelled, etc.)
  - Build run URL

The background monitor will automatically send team notifications for:
- Build success
- Build failure
- Build cancelled
- Any other terminal state

ELSE:
Show:

Missing env setup

To enable:
cp .env.example .notification.local.env

Then fill:

TEAM_WEBHOOK_URL=<webhook-url>
CICD_CHAT_PROVIDER=teams
