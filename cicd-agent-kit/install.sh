#!/usr/bin/env bash
set -euo pipefail
# Install kit into a target repo using config/sync-map.yml (idempotent; skip existing unless --force).
# Prefer sync_kit_diff.sh for selective sync. High-risk Fastfile/Appfile skipped unless --force-high-risk.

usage() {
  cat <<'EOF'
Usage:
  ./cicd-agent-kit/install.sh <target-repo-path> [app-identifier] [--force] [--force-high-risk] [--dry-run]
EOF
}

TARGET_REPO=""
APP_IDENTIFIER=""
FORCE=0
FORCE_HIGH=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --force) FORCE=1; shift ;;
    --force-high-risk) FORCE_HIGH=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    *)
      if [[ -z "$TARGET_REPO" ]]; then TARGET_REPO="$1"
      elif [[ -z "$APP_IDENTIFIER" ]]; then APP_IDENTIFIER="$1"
      else echo "Unexpected: $1"; usage; exit 1; fi
      shift ;;
  esac
done

[[ -n "$TARGET_REPO" && -d "$TARGET_REPO" ]] || { usage; exit 1; }
KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_REPO="$(cd "$TARGET_REPO" && pwd)"
chmod +x "$KIT_ROOT/scripts/"*.sh "$KIT_ROOT/harness/"*.sh 2>/dev/null || true

python3 - "$KIT_ROOT" "$TARGET_REPO" "$FORCE" "$FORCE_HIGH" "$DRY_RUN" <<'PY'
import json, shutil, subprocess, sys
from pathlib import Path
kit, target = Path(sys.argv[1]), Path(sys.argv[2])
force, force_high, dry = sys.argv[3] == "1", sys.argv[4] == "1", sys.argv[5] == "1"
sm = json.loads(subprocess.check_output(
    ["ruby","-ryaml","-rjson","-e","print JSON.generate(YAML.safe_load(STDIN.read, aliases:true)||{})"],
    input=(kit/"config/sync-map.yml").read_bytes()))
copied=skipped=overwritten=0

def install(src_rel, dst_rel, risk="normal"):
    global copied, skipped, overwritten
    src, dst = kit/src_rel, target/dst_rel
    if not src.exists():
        print("MISSING_SRC", src_rel); return
    if risk == "high" and not force_high and dst.exists():
        print("Skip high-risk (use --force-high-risk):", dst_rel); skipped += 1; return
    if dst.exists() and not force and not (risk=="high" and force_high):
        print("Skip existing:", dst_rel); skipped += 1; return
    if dry:
        print("DRY-RUN", "overwrite" if dst.exists() else "copy", dst_rel); copied += 1; return
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        shutil.copy2(dst, str(dst)+".bak-cicd-kit"); overwritten += 1
    else:
        copied += 1
    shutil.copy2(src, dst)
    if dst_rel.endswith(".sh") or "/harness/" in dst_rel:
        dst.chmod(dst.stat().st_mode | 0o111)
    print("Installed", dst_rel)

for m in sm.get("mappings") or []:
    if m["dst"] in (sm.get("preserve_never_overwrite") or []):
        continue
    install(m["src"], m["dst"], m.get("risk") or "normal")
for h in sm.get("harness_files") or []:
    install(h, f".github/cicd/{h}")
for s in sm.get("script_files") or []:
    install(f"scripts/{s}", f"scripts/{s}")

# Ensure CICD_KIT_HOME hint file
hint = target/".github/cicd/CICD_KIT_HOME"
if not dry:
    hint.parent.mkdir(parents=True, exist_ok=True)
    hint.write_text(str((target/".github/cicd").resolve())+"\n")
print(f"Summary copied={copied} skipped={skipped} overwritten={overwritten}")
print("Set export CICD_KIT_HOME=.github/cicd when invoking tools from the target repo.")
PY

echo "Next: ./scripts/sync_kit_diff.sh --target $TARGET_REPO  # review before --apply-paths"
echo "High-risk Fastfile/Appfile: use sync-prep/*.merged after approval"
