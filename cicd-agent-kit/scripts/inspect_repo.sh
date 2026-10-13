#!/usr/bin/env bash
set -euo pipefail

# Read-only repository inspection for the CI/CD agent.
# Does not install dependencies, build, test, dispatch, upload, or notify.

REPO_ROOT="$(pwd)"
FORMAT="human"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/inspect_repo.sh [--repo <path>] [--format human|json]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --format) FORMAT="${2:-human}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ ! -d "$REPO_ROOT" ]]; then
  echo "Repo path does not exist: $REPO_ROOT" >&2
  exit 1
fi
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

KIT_DETECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/detect_project_platform.sh"
DETECT_JSON="{}"
if [[ -x "$KIT_DETECT" ]]; then
  DETECT_JSON="$("$KIT_DETECT" --repo "$REPO_ROOT" --format json 2>/dev/null || echo '{}')"
fi

python3 - "$REPO_ROOT" "$FORMAT" "$DETECT_JSON" <<'PY'
import json, os, re, sys, subprocess
from pathlib import Path

root = Path(sys.argv[1])
fmt = sys.argv[2]
try:
    detect = json.loads(sys.argv[3] or "{}")
except Exception:
    detect = {}

def exists(rel):
    return (root / rel).exists()

workflows = sorted(p.relative_to(root).as_posix() for p in (root / ".github" / "workflows").glob("*.yml")) if (root / ".github" / "workflows").is_dir() else []
workflows += sorted(p.relative_to(root).as_posix() for p in (root / ".github" / "workflows").glob("*.yaml")) if (root / ".github" / "workflows").is_dir() else []

jenkins = []
for pattern in ("Jenkinsfile", "Jenkinsfile.*", "*.jenkinsfile"):
    jenkins += [p.relative_to(root).as_posix() for p in root.glob(pattern)]
jenkins = sorted(set(jenkins))

fastlane = []
fl = root / "fastlane"
if fl.is_dir():
    fastlane = sorted(p.relative_to(root).as_posix() for p in fl.iterdir() if p.is_file())

lockfiles = []
for name in ("Gemfile.lock", "Podfile.lock", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "pubspec.lock", "Cargo.lock"):
    if (root / name).exists():
        lockfiles.append(name)

missing_lock_hints = []
if (root / "Gemfile").exists() and "Gemfile.lock" not in lockfiles:
    missing_lock_hints.append({"file": "Gemfile.lock", "impact": "reproducibility_gap", "blocker": False})
if (root / "package.json").exists() and not any(x in lockfiles for x in ("package-lock.json", "yarn.lock", "pnpm-lock.yaml")):
    missing_lock_hints.append({"file": "js lockfile", "impact": "reproducibility_gap", "blocker": False})
if (root / "pubspec.yaml").exists() and "pubspec.lock" not in lockfiles:
    missing_lock_hints.append({"file": "pubspec.lock", "impact": "reproducibility_gap", "blocker": False})

presets = sorted(p.relative_to(root).as_posix() for p in root.glob("**/*presets.json") if ".git" not in p.parts)[:50]
variants = sorted(p.relative_to(root).as_posix() for p in root.glob("**/*variants.json") if ".git" not in p.parts)[:50]
overrides = []
for p in [root / ".github" / "config-overrides" / "config_overrides.json", root / "config-overrides" / "config_overrides.json"]:
    if p.exists():
        overrides.append(p.relative_to(root).as_posix())

# Secret name references only (not values)
secret_names = set()
for wf in workflows:
    text = (root / wf).read_text(errors="ignore")
    secret_names.update(re.findall(r"secrets\.([A-Z0-9_]+)", text))

providers = []
if workflows:
    providers.append("github_actions")
if jenkins:
    providers.append("jenkins")
if not providers:
    providers.append("none")

scheme_note = "Scheme availability needs verification when shared .xcscheme files are absent; use xcodebuild -list when available."
shared_schemes = list(root.glob("**/*.xcodeproj/xcshareddata/xcschemes/*.xcscheme"))
shared_schemes = [p.relative_to(root).as_posix() for p in shared_schemes if ".git" not in p.parts]

verified_schemes = []
scheme_verification = "not_run"
project_file = detect.get("project_file") or ""
if project_file:
    pf = root / project_file
    try:
        if project_file.endswith(".xcworkspace"):
            cmd = ["xcodebuild", "-list", "-workspace", str(pf)]
        else:
            cmd = ["xcodebuild", "-list", "-project", str(pf)]
        out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL, timeout=120)
        in_schemes = False
        for line in out.splitlines():
            if line.strip() == "Schemes:":
                in_schemes = True
                continue
            if in_schemes:
                if not line.strip():
                    break
                if line.startswith("        "):
                    verified_schemes.append(line.strip())
        scheme_verification = "verified" if verified_schemes else "ran_no_schemes_parsed"
        if verified_schemes:
            scheme_note = "Schemes verified via xcodebuild -list (shared .xcscheme file may still be absent on disk)."
    except FileNotFoundError:
        scheme_verification = "xcodebuild_unavailable"
    except Exception:
        scheme_verification = "xcodebuild_failed"

default_branch = None
try:
    out = subprocess.check_output(["git", "-C", str(root), "symbolic-ref", "refs/remotes/origin/HEAD"], text=True, stderr=subprocess.DEVNULL).strip()
    default_branch = out.split("/")[-1]
except Exception:
    try:
        default_branch = subprocess.check_output(["git", "-C", str(root), "rev-parse", "--abbrev-ref", "HEAD"], text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        default_branch = None

report = {
    "repo": str(root),
    "default_branch": default_branch,
    "platform_detection": detect,
    "ci_providers_found": providers,
    "github_workflows": workflows,
    "jenkinsfiles": jenkins,
    "jenkins_kit_status": "implemented_credentials_gated_for_remote",
    "fastlane_files": fastlane,
    "presets_files": presets,
    "variants_files": variants,
    "config_overrides": overrides,
    "lockfiles_present": lockfiles,
    "lockfile_gaps": missing_lock_hints,
    "shared_xcschemes": shared_schemes,
    "verified_schemes": verified_schemes,
    "scheme_verification": scheme_verification,
    "scheme_notes": scheme_note,
    "secret_name_references": sorted(secret_names),
    "findings": [
        {"id": "jenkins_provider", "status": "documented_contract_only", "evidence": "cicd-agent-kit/docs/JENKINS.md"},
    ],
}

if fmt == "json":
    print(json.dumps(report, indent=2))
else:
    print(f"Repo: {report['repo']}")
    print(f"Default branch: {report['default_branch']}")
    print(f"Providers: {', '.join(providers)}")
    print(f"Platform detection: {detect.get('platform', 'unknown')} ({detect.get('platform_confidence', '')})")
    print(f"Workflows ({len(workflows)}):")
    for w in workflows:
        print(f"  - {w}")
    print(f"Jenkinsfiles ({len(jenkins)}):")
    for j in jenkins or ["(none)"]:
        print(f"  - {j}")
    print(f"Shared xcschemes on disk ({len(shared_schemes)}):")
    for s in shared_schemes or ["(none found on disk)"]:
        print(f"  - {s}")
    print(f"Scheme verification: {scheme_verification}")
    print(f"Verified schemes ({len(verified_schemes)}):")
    for s in verified_schemes or ["(none)"]:
        print(f"  - {s}")
    print(f"Scheme note: {scheme_note}")
    print(f"Lockfiles: {', '.join(lockfiles) or '(none)'}")
    if missing_lock_hints:
        print("Lockfile gaps (reproducibility, not automatic blockers):")
        for g in missing_lock_hints:
            print(f"  - {g['file']}")
    print(f"Secret name references: {', '.join(sorted(secret_names)) or '(none scanned)'}")
    print("Jenkins kit status: contract_only — see docs/JENKINS.md")
PY
