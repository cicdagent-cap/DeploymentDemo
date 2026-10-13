#!/usr/bin/env bash
set -euo pipefail

REPO=""
REQUEST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --request) REQUEST="${2:-}"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$REPO" && -n "$REQUEST" ]] || { echo "Usage: recommend_pipeline_action.sh --repo <path> --request <file>"; exit 1; }
REPO="$(cd "$REPO" && pwd)"

python3 - "$REPO" "$REQUEST" <<'PY'
import json, sys, subprocess, re
from pathlib import Path

repo = Path(sys.argv[1])
req = json.loads(subprocess.check_output(
    ["ruby","-ryaml","-rjson","-e","print JSON.generate(YAML.safe_load(STDIN.read, aliases:true)||{})"],
    input=Path(sys.argv[2]).read_bytes()))

provider = req.get("provider") or "github_actions"
out_file = (req.get("pipeline") or {}).get("output_file")
reuse_flag = bool((req.get("pipeline") or {}).get("reuse_existing_if_suitable", True))
wanted_caps = set(req.get("capabilities") or [])
destination = req.get("destination") or "artifacts-only"
wants_dist = destination not in ("artifacts-only", "none", None) or bool(wanted_caps & {"testflight","firebase_app_distribution","google_play_tracks","ios_archive_ipa"})
wants_notify = bool((req.get("notifications") or {}).get("enabled")) or "notifications_teams_slack" in wanted_caps
wants_tests = "unit_tests" in wanted_caps

workflows = []
wf_dir = repo / ".github" / "workflows"
if wf_dir.is_dir():
    workflows = sorted([p.relative_to(repo).as_posix() for p in list(wf_dir.glob("*.yml")) + list(wf_dir.glob("*.yaml"))])
jenkinsfiles = [p.relative_to(repo).as_posix() for p in repo.glob("Jenkinsfile*")]

def analyze_workflow(path: Path):
    # Keyword/regex heuristics over workflow YAML — not a full semantic job graph.
    text = path.read_text(errors="ignore")
    return {
        "path": path.relative_to(repo).as_posix(),
        "workflow_dispatch": "workflow_dispatch" in text,
        "uses": re.findall(r"uses:\s*([^\s]+)", text),
        "runs_tests": bool(re.search(r"(fastlane\s+\w+\s+test|xcodebuild.*test|gradlew\s+test|flutter test)", text, re.I)),
        "uploads_artifacts": "upload-artifact" in text,
        "distributes": bool(re.search(r"(upload_to_testflight|firebase_app_distribution|supply\(|CICD_UPLOAD_TESTFLIGHT:\s*(\"true\"|true)|CICD_ALLOW_DISTRIBUTION:\s*(\"true\"|true))", text)),
        "notifies": "notify.sh" in text or "notify-triggered" in text,
        "build_only_guard": "CICD_ALLOW_DISTRIBUTION: \"false\"" in text or "CICD_ALLOW_DISTRIBUTION: false" in text,
        "secrets": sorted(set(re.findall(r"secrets\.([A-Z0-9_]+)", text))),
        "scan_method": "keyword_heuristic",
    }

scanned = [analyze_workflow(repo / w) for w in workflows]
deps = sorted({u for s in scanned for u in s["uses"] if not u.startswith("./")})
evidence = [f"external_reusable_ref:{u}" for u in deps]
blockers = []

ios = [p for p in list(repo.glob("*.xcodeproj")) + list(repo.glob("*/*.xcodeproj")) if "Pods" not in str(p)]
if len(ios) > 1:
    blockers.append("ambiguous_multiple_xcode_projects")

action = "create"
reasons = []

if provider == "github_actions":
    if out_file and (repo / out_file).exists():
        meta = analyze_workflow(repo / out_file)
        # extend if behavior gaps vs request
        gaps = []
        if wants_tests and not meta["runs_tests"]:
            gaps.append("missing_tests")
        if wants_dist and not meta["distributes"]:
            gaps.append("missing_distribution")
        if not wants_dist and meta["distributes"] and not meta["build_only_guard"]:
            gaps.append("existing_has_distribution_without_guard")
        if wants_notify and not meta["notifies"]:
            gaps.append("missing_notifications")
        if gaps:
            action = "extend"
            reasons.append(f"output_file exists but behavior gaps: {gaps}")
        elif reuse_flag:
            action = "reuse"
            reasons.append(f"output_file {out_file} behavior matches request")
        else:
            action = "create"
            reasons.append("reuse_existing_if_suitable=false")
    elif reuse_flag and scanned:
        candidates = []
        for s in scanned:
            if not s["workflow_dispatch"]:
                continue
            ok = True
            if wants_tests and not s["runs_tests"]:
                ok = False
            if wants_dist and not s["distributes"]:
                ok = False
            if not wants_dist and s["distributes"] and not s["build_only_guard"]:
                ok = False  # unsafe reuse
            if wants_notify and not s["notifies"]:
                ok = False
            if ok:
                candidates.append(s)
        if candidates:
            action = "reuse"
            reasons.append(f"reusable workflow behavior match: {candidates[0]['path']}")
        else:
            # partial
            dispatchable = [s for s in scanned if s["workflow_dispatch"]]
            if dispatchable:
                action = "extend"
                reasons.append("dispatchable workflows exist but behavior does not satisfy request (tests/distribution/notify)")
            else:
                action = "create"
                reasons.append("no workflow_dispatch workflows")
    else:
        action = "create"
        reasons.append("no suitable github workflow found")
elif provider == "jenkins":
    if jenkinsfiles and reuse_flag:
        action = "extend"
        reasons.append(f"jenkinsfile present: {jenkinsfiles[0]}")
    else:
        action = "create"
        reasons.append("no Jenkinsfile or reuse disabled")

print(json.dumps({
    "action": action,
    "provider": provider,
    "reasons": reasons,
    "evidence": evidence + [f"workflow:{w}" for w in workflows] + [f"jenkins:{j}" for j in jenkinsfiles],
    "workflow_dependencies": deps,
    "scanned_workflows": scanned,
    "request_needs": {"tests": wants_tests, "distribution": wants_dist, "notifications": wants_notify, "destination": destination},
    "blockers": blockers,
    "reuse_flag": reuse_flag,
}, indent=2))
PY
