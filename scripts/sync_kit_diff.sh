#!/usr/bin/env bash
set -euo pipefail
# File-by-file sync plan from config/sync-map.yml. Diff only by default.

KIT_ROOT="$("$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve_kit_home.sh")"
TARGET=""
APPLY_PATHS=""
SCOPE_FILE="${CICD_APPROVED_SCOPE_FILE:-}"
FORMAT="text"
UNIFIED=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kit-root) KIT_ROOT="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --apply-paths) APPLY_PATHS="${2:-}"; shift 2 ;;
    --scope-file) SCOPE_FILE="${2:-}"; shift 2 ;;
    --format) FORMAT="${2:-}"; shift 2 ;;
    --unified-diff) UNIFIED=1; shift ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$TARGET" ]] || { echo "Usage: sync_kit_diff.sh --target <repo> [--unified-diff] [--apply-paths ...]"; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"
KIT_ROOT="$(cd "$KIT_ROOT" && pwd)"

python3 - "$KIT_ROOT" "$TARGET" "$APPLY_PATHS" "$SCOPE_FILE" "$FORMAT" "$UNIFIED" <<'PY'
import json, shutil, subprocess, sys
from pathlib import Path

kit, target, apply_paths, scope_file, fmt, unified = sys.argv[1:7]
kit, target = Path(kit), Path(target)
unified = unified == "1"
raw = subprocess.check_output(
    ["ruby", "-ryaml", "-rjson", "-e", "print JSON.generate(YAML.safe_load(STDIN.read, aliases:true)||{})"],
    input=(kit / "config/sync-map.yml").read_bytes(),
)
sm = json.loads(raw.decode())
rows = []

def add_row(src_rel, dst_rel, risk="normal", merge=None):
    src, dst = kit / src_rel, target / dst_rel
    if not src.exists():
        st = "missing_in_kit"
    elif not dst.exists():
        st = "missing_in_target"
    elif src.read_bytes() == dst.read_bytes():
        st = "same"
    else:
        st = "differs"
    rec = {"src": src_rel, "dst": dst_rel, "status": st, "risk": risk}
    if merge:
        rec["merge"] = merge
    if unified and st == "differs":
        try:
            diff = subprocess.run(["diff", "-u", str(dst), str(src)], capture_output=True, text=True)
            rec["unified_diff"] = diff.stdout[:20000]
        except Exception as e:
            rec["unified_diff_error"] = str(e)
    elif unified and st == "missing_in_target":
        rec["unified_diff"] = f"--- /dev/null\n+++ {dst_rel}\n" + "".join(f"+{l}" for l in src.read_text(errors="ignore").splitlines(True)[:200])
    rows.append(rec)

for m in sm.get("mappings") or []:
    add_row(m["src"], m["dst"], m.get("risk") or "normal", m.get("merge"))

for h in sm.get("harness_files") or []:
    add_row(h, f".github/cicd/{h}")

for s in sm.get("script_files") or []:
    add_row(f"scripts/{s}", f"scripts/{s}")

for p in sm.get("preserve_never_overwrite") or []:
    wf = target / p
    note = None
    contains = False
    if wf.exists():
        text = wf.read_text(errors="ignore")
        contains = "mac-m4-xc26.2-eu" in text
        note = "Project workflow preserved; not overwritten by sync"
    rows.append({
        "src": "(preserve)",
        "dst": p,
        "status": "preserve_project_workflow",
        "risk": "high",
        "note": note,
        "contains_mac_m4": contains,
    })

result = {"target": str(target), "files": rows, "apply": None}
apply_list = [p.strip() for p in apply_paths.split(",") if p.strip()]
if apply_list:
    if not scope_file:
        result["apply"] = {"status": "blocked", "reason": "scope_file_required"}
    else:
        applied, skipped = [], []
        for dst_rel in apply_list:
            match = next((r for r in rows if r["dst"] == dst_rel), None)
            if not match or match["status"] == "preserve_project_workflow":
                skipped.append({"dst": dst_rel, "reason": "not_applicable"})
                continue
            if match.get("merge") == "required":
                skipped.append({"dst": dst_rel, "reason": "merge_required_use_sync_prep"})
                continue
            try:
                subprocess.check_call([str(kit / "harness/require_approval.sh"), "--action", "apply_patch", "--repo", str(target), "--path", dst_rel, "--scope-file", scope_file, "--destination", "artifacts-only"])
            except subprocess.CalledProcessError:
                skipped.append({"dst": dst_rel, "reason": "approval_denied"})
                continue
            src = kit / match["src"]
            dst = target / dst_rel
            if dst.exists():
                shutil.copy2(dst, str(dst) + ".bak-cicd-selective")
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            if dst_rel.endswith(".sh") or "/harness/" in dst_rel:
                dst.chmod(dst.stat().st_mode | 0o111)
            applied.append(dst_rel)
        result["apply"] = {"applied": applied, "skipped": skipped}

if fmt == "json":
    print(json.dumps(result, indent=2))
else:
    for r in rows:
        print(f"{r['status']:28} risk={r.get('risk','normal'):6} {r['dst']}  <=  {r['src']}")
        if r.get("note"):
            print(f"  note: {r['note']}")
        if unified and r.get("unified_diff"):
            print(r["unified_diff"][:4000])
            print("---")
PY
