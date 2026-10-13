#!/usr/bin/env bash
set -euo pipefail

echo "Note: bootstrap_new_ios_repo.sh delegates to install.sh (auto-detects platform)."
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install.sh" "$@"
