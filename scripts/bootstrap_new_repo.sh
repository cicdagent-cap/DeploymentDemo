#!/usr/bin/env bash
set -euo pipefail

KIT_ROOT="$("$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve_kit_home.sh")"
exec "$KIT_ROOT/install.sh" "$@"
