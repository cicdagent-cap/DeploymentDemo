#!/usr/bin/env bash
set -euo pipefail
# Apply only files listed in a proposal and allowed by approved scope. Selective — not blanket force.

PROPOSAL=""
SCOPE_FILE="${CICD_APPROVED_SCOPE_FILE:-}"
KIT_ROOT="$("$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve_kit_home.sh")"
SRC_ROOT="$KIT_ROOT"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proposal) PROPOSAL="${2:-}"; shift 2 ;;
    --scope-file) SCOPE_FILE="${2:-}"; shift 2 ;;
    --kit-root) SRC_ROOT="${2:-}"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$PROPOSAL" && -f "$SCOPE_FILE" ]] || { echo "Usage: apply_approved_patch.sh --proposal <json> --scope-file <scope>"; exit 1; }

REPO="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["repo_root"])' "$PROPOSAL")"
"$KIT_ROOT/harness/require_approval.sh" --action apply_patch --repo "$REPO" --scope-file "$SCOPE_FILE"

python3 - "$PROPOSAL" "$SCOPE_FILE" "$SRC_ROOT" <<'PY'
import json, shutil, sys, hashlib
from pathlib import Path

proposal = json.loads(Path(sys.argv[1]).read_text())
scope = Path(sys.argv[2]).read_text()
# parse scope via ruby
import subprocess
scope_obj = json.loads(subprocess.check_output(
    ["ruby","-ryaml","-rjson","-e","print JSON.generate(YAML.safe_load(STDIN.read, aliases:true)||{})"],
    input=scope.encode()))

# stale proposal check
if scope_obj.get("proposal_hash") and scope_obj.get("proposal_hash") != proposal.get("proposal_hash"):
    print("STALE_PROPOSAL: scope.proposal_hash does not match proposal", file=sys.stderr)
    sys.exit(3)

repo = Path(proposal["repo_root"])
kit = Path(sys.argv[3])
allowed = scope_obj.get("allowed_paths") or []
applied, skipped = [], []

def allowed_path(rel):
    if not allowed:
        return False
    for a in allowed:
        if a == "*" or rel.startswith(a.rstrip("*")):
            return True
    return False

for f in proposal.get("files") or []:
    rel = f.get("path")
    if not rel:
        skipped.append({"path": rel, "reason": "missing_path"})
        continue
    if not allowed_path(rel):
        skipped.append({"path": rel, "reason": "not_in_allowed_paths"})
        continue
    tmpl = f.get("template")
    if not tmpl:
        skipped.append({"path": rel, "reason": "no_template"})
        continue
    src = kit / tmpl
    dest = repo / rel
    if f.get("op") == "create_if_missing" and dest.exists():
        skipped.append({"path": rel, "reason": "exists"})
        continue
    # High-risk merge files: never blind overwrite Fastfile/Appfile — require explicit allow + backup
    if rel in ("fastlane/Fastfile", "fastlane/Appfile") or rel.endswith("/Fastfile") or rel.endswith("/Appfile"):
        if "fastlane/" not in ",".join(allowed) and rel not in allowed and not any(rel.startswith(a.rstrip("*")) for a in allowed):
            skipped.append({"path": rel, "reason": "high_risk_requires_explicit_allow"})
            continue
        if dest.exists():
            bak = dest.with_suffix(dest.suffix + ".bak-cicd-selective")
            shutil.copy2(dest, bak)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)
    applied.append(rel)

print(json.dumps({"applied": applied, "skipped": skipped}, indent=2))
PY
