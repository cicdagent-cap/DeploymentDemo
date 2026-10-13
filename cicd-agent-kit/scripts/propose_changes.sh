#!/usr/bin/env bash
set -euo pipefail

REPO=""
REQUEST=""
OUT=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib_kit_paths.sh"
KIT_ROOT="$CICD_KIT_HOME"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --request) REQUEST="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$REPO" && -n "$REQUEST" ]] || { echo "Usage: propose_changes.sh --repo <path> --request <file> [--out <json>]"; exit 1; }
REPO="$(cd "$REPO" && pwd)"
OUT="${OUT:-/dev/stdout}"

REC="$("$(cicd_script recommend_pipeline_action.sh)" --repo "$REPO" --request "$REQUEST")"
VAL="$("$(cicd_script validate_request.sh)" --request "$REQUEST" --repo "$REPO" 2>/dev/null || true)"

python3 - "$REPO" "$REQUEST" "$REC" "$VAL" "$OUT" "$KIT_ROOT" <<'PY'
import hashlib, json, sys, subprocess
from pathlib import Path
repo, req_path, rec_raw, val_raw, out, kit = sys.argv[1:7]
req = json.loads(subprocess.check_output(
    ["ruby","-ryaml","-rjson","-e","print JSON.generate(YAML.safe_load(STDIN.read, aliases:true)||{})"],
    input=Path(req_path).read_bytes()))
rec = json.loads(rec_raw)
try:
    val = json.loads(val_raw) if val_raw.strip().startswith("{") else {"status":"fail"}
except Exception:
    val = {"status":"fail"}

provider = req.get("provider") or "github_actions"
files = []
if rec["action"] in ("create", "extend"):
    if provider == "github_actions":
        files.append({
            "path": (req.get("pipeline") or {}).get("output_file"),
            "op": "create_or_update",
            "template": "templates/mobile-ci-workflow.template.yml",
            "risk": "medium",
        })
        caps = set(req.get("capabilities") or [])
        if "presets_variants" in caps:
            files.append({"path": ".github/pipeline-templates/presets.json", "op": "create_if_missing", "template": "templates/presets.example.json", "risk": "low"})
            files.append({"path": ".github/pipeline-templates/variants.json", "op": "create_if_missing", "template": "templates/variants.example.json", "risk": "low"})
    else:
        files.append({
            "path": (req.get("jenkins") or {}).get("output_file") or "Jenkinsfile",
            "op": "create_or_update",
            "template": "providers/jenkins/templates/Jenkinsfile.mobile.template",
            "risk": "medium",
        })

proposal = {
    "proposal_version": 1,
    "repo_root": repo,
    "action": rec["action"],
    "provider": provider,
    "validation": val,
    "recommendation": rec,
    "files": files,
    "capabilities": req.get("capabilities") or [],
    "destination": req.get("destination"),
    "runner_label": req.get("runner_label") or (req.get("github_actions") or {}).get("runner_label"),
    "preserve": ["mac-m4-xc26.2-eu runner labels in existing workflows unless explicitly approved to change"],
    "not_included": ["workflow_dispatch", "uploads", "notifications", "commits"],
    "host_vs_kit": {
        "approval_presentation": "host_or_agent_markdown",
        "approval_enforcement_on_mutate": "kit_harness_require_approval",
        "model_behavior": "host",
    },
}
blob = json.dumps(proposal, sort_keys=True)
proposal["proposal_hash"] = hashlib.sha256(blob.encode()).hexdigest()
Path(out).write_text(json.dumps(proposal, indent=2)) if out != "/dev/stdout" else print(json.dumps(proposal, indent=2))
if out != "/dev/stdout":
    print(out)
PY
