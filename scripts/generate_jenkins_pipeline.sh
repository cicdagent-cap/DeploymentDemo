#!/usr/bin/env bash
set -euo pipefail

REPO=""
REQUEST=""
SCOPE_FILE="${CICD_APPROVED_SCOPE_FILE:-}"
DRY_RUN=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib_kit_paths.sh"
KIT_ROOT="$CICD_KIT_HOME"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --request) REQUEST="${2:-}"; shift 2 ;;
    --scope-file) SCOPE_FILE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$REPO" && -n "$REQUEST" ]] || { echo "Usage: generate_jenkins_pipeline.sh --repo <path> --request <file> --scope-file <scope> [--dry-run]"; exit 1; }
REPO="$(cd "$REPO" && pwd)"

OUT_REL="$(ruby -ryaml -e 'd=YAML.safe_load(File.read(ARGV[0]), aliases:true)||{}; puts((d["jenkins"]||{})["output_file"] || "Jenkinsfile")' "$REQUEST")"
if [[ "$DRY_RUN" -eq 0 ]]; then
  "$KIT_ROOT/harness/require_approval.sh" --action generate_pipeline --repo "$REPO" --path "$OUT_REL" --scope-file "${SCOPE_FILE:?scope required}"
fi

"$(cicd_script validate_request.sh)" --request "$REQUEST" --repo "$REPO" >/tmp/cicd-jenkins-val.json
DET="$("$(cicd_script detect_project_platform.sh)" --repo "$REPO" --format json)"

python3 - "$KIT_ROOT" "$REPO" "$REQUEST" "$DET" "$DRY_RUN" "$OUT_REL" <<'PY'
import json, sys, subprocess
from pathlib import Path
kit, repo, req_path, det_raw, dry, out_rel = sys.argv[1:7]
dry = dry == "1"
req = json.loads(subprocess.check_output(
    ["ruby","-ryaml","-rjson","-e","print JSON.generate(YAML.safe_load(STDIN.read, aliases:true)||{})"],
    input=Path(req_path).read_bytes()))
det = json.loads(det_raw)
caps = set(req.get("capabilities") or [])
text = (Path(kit) / "providers/jenkins/templates/Jenkinsfile.mobile.template").read_text()
j = req.get("jenkins") or {}
runner = req.get("runner_label") or j.get("agent_label") or ("macos" if det.get("platform")=="ios" else "linux")
platform = det.get("platform") or "ios"
fl_plat = det.get("fastlane_platform") or platform
mode = "release" if (req.get("build_configuration") or "").lower()=="release" else "build"
presets = (req.get("presets") or {}).get("options") or ["Debug-CICD", "Release-CICD"]
preset_choices = str(presets).replace("'", '"')

build_cmd = {
    "ios": "bundle exec fastlane ios " + mode if (Path(repo)/"fastlane/Fastfile").exists() else "xcodebuild -list",
    "android": "bundle exec fastlane android " + mode if (Path(repo)/"fastlane/Fastfile").exists() else "./gradlew assembleDebug",
}.get(platform, "echo 'configure __BUILD_COMMAND__ for platform'")

repl = {
    "__RUNNER_LABEL__": runner,
    "__TIMEOUT_MINUTES__": str(j.get("timeout_minutes") or 120),
    "__PRESET_CHOICES__": preset_choices,
    "__CICD_PLATFORM__": platform,
    "__DEFAULT_PROJECT_FILE__": det.get("project_file") or "",
    "__DEFAULT_SCHEME__": det.get("default_scheme") or "",
    "__CICD_GRADLE_DIR__": det.get("gradle_dir") or "android",
    "__CICD_BUILD_TARGET__": det.get("build_target") or "",
    "__CRED_FASTLANE_TEAM_ID__": (j.get("credentials") or {}).get("fastlane_team_id") or "fastlane-team-id",
    "__CRED_MATCH_PASSWORD__": (j.get("credentials") or {}).get("match_password") or "match-password",
    "__CRED_FIREBASE_SA__": (j.get("credentials") or {}).get("firebase_sa") or "firebase-sa-json",
    "__ENABLE_DEPS__": "true" if "dependency_restoration" in caps else "false",
    "__DEPS_COMMAND__": j.get("deps_command") or "bundle install || true",
    "__FASTLANE_PLATFORM__": fl_plat,
    "__LANE_MODE__": mode,
    "__BUILD_COMMAND__": j.get("build_command") or build_cmd,
    "__ENABLE_ARTIFACTS__": "true" if "artifacts" in caps else "true",
    "__ARTIFACT_GLOBS__": j.get("artifact_globs") or "**/build/outputs/**/*.apk,**/build/outputs/**/*.aab,**/build/**/*.ipa",
    "__ENABLE_DISTRIBUTE__": "true" if any(c in caps for c in ("testflight","firebase_app_distribution","google_play_tracks")) else "false",
    "__DISTRIBUTE_COMMAND__": j.get("distribute_command") or "echo 'Configure distribute command for selected destination'",
}
for k,v in repl.items():
    text = text.replace(k, str(v))

out = Path(repo) / out_rel
if dry:
    print(json.dumps({"status":"dry_run","would_write":str(out),"capabilities":sorted(caps)}, indent=2))
    sys.exit(0)
out.write_text(text)
print(json.dumps({"status":"written","jenkinsfile":out_rel,"capabilities":sorted(caps),"agent_label":runner}, indent=2))
PY
