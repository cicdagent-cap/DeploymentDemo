#!/usr/bin/env bash
set -euo pipefail
# Validate independent configuration dimensions for unsupported combinations.

REQUEST=""
REPO=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib_kit_paths.sh"
KIT_ROOT="$CICD_KIT_HOME"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --request) REQUEST="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$REQUEST" ]] || { echo "Usage: validate_configuration.sh --request <file> [--repo <path>]"; exit 1; }

# Reuse validate_request core + presets/variants file existence checks
BASE="$("$(cicd_script validate_request.sh)" --request "$REQUEST" --repo "${REPO:-}" 2>/dev/null || true)"
python3 - "$REQUEST" "${REPO:-}" "$BASE" <<'PY'
import json, sys, subprocess
from pathlib import Path
req_path, repo, base_raw = sys.argv[1:4]
try:
    base = json.loads(base_raw) if base_raw.strip().startswith("{") else {"status":"fail","errors":["validate_request failed"],"warnings":[]}
except Exception:
    base = {"status":"fail","errors":["validate_request failed"],"warnings":[]}

req = json.loads(subprocess.check_output(
    ["ruby","-ryaml","-rjson","-e","print JSON.generate(YAML.safe_load(STDIN.read, aliases:true)||{})"],
    input=Path(req_path).read_bytes()))
errors = list(base.get("errors") or [])
warnings = list(base.get("warnings") or [])

presets = req.get("presets") or {}
for key in ("presets_path", "variants_path"):
    p = presets.get(key)
    if p and repo:
        if not (Path(repo) / p).exists():
            errors.append(f"missing {key}: {p}")

# Release build configuration is not production environment
env = (req.get("environment") or "").lower()
bcfg = (req.get("build_configuration") or "").lower()
if bcfg == "release" and env in ("production", "prod") and (req.get("destination") in (None, "artifacts-only", "none")):
    warnings.append("Release + production environment with artifacts-only destination — confirm intentional")

# Market without presets
if req.get("market") and not presets.get("enabled") and not presets.get("presets_path"):
    warnings.append("market set without presets configuration — ambiguous mapping")

status = "pass" if not errors else "fail"
print(json.dumps({"status": status, "errors": errors, "warnings": warnings, "dimensions": {
    "platform": (req.get("platform") or {}),
    "environment": req.get("environment"),
    "build_configuration": req.get("build_configuration"),
    "market": req.get("market"),
    "variant": req.get("variant"),
    "destination": req.get("destination"),
    "runner_label": req.get("runner_label"),
    "signing": req.get("signing"),
}}, indent=2))
sys.exit(0 if status == "pass" else 1)
PY
