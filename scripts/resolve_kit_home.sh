#!/usr/bin/env bash
# Resolve installed kit home so scripts work without depending on source cicd-agent-kit/ path.
set -euo pipefail
if [[ -n "${CICD_KIT_HOME:-}" && -d "${CICD_KIT_HOME}" ]]; then
  echo "$CICD_KIT_HOME"
  exit 0
fi
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Preferred installed layout
for cand in \
  "$HERE/../.github/cicd" \
  "$(pwd)/.github/cicd" \
  "$HERE/.." \
  "$(cd "$HERE/.." && pwd)"; do
  if [[ -f "$cand/manifest.yml" || -f "$cand/harness/require_approval.sh" ]]; then
    cd "$cand" && pwd
    exit 0
  fi
done
# Fallback: scripts live inside source kit
if [[ -f "$HERE/../manifest.yml" ]]; then
  cd "$HERE/.." && pwd
  exit 0
fi
echo "CICD_KIT_HOME unresolved" >&2
exit 1
