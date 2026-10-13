#!/usr/bin/env bash
set -euo pipefail
# Hard-fail if required lanes are missing (no warn-and-continue).

REPO="${1:-.}"
PLATFORM="${2:-}"
MODE="${3:-build}" # build|test|release
REPO="$(cd "$REPO" && pwd)"

if [[ ! -f "$REPO/fastlane/Fastfile" ]]; then
  echo json_error='"no_fastfile"' >&2
  echo '{"status":"fail","reason":"no_fastfile"}'
  exit 1
fi

# Parse lane names from Fastfile without executing Fastlane network/bundle when possible
# Prefer structured JSON via ruby JSON (force UTF-8 — Fastfile may contain non-ASCII comments)
LANES_JSON="$(ruby -rjson -e 'path=ARGV[0]; t=File.read(path, encoding: "UTF-8"); lanes=t.scan(/^\s*lane\s+:([a-zA-Z0-9_]+)/).flatten; plats=t.scan(/platform\s+:([a-zA-Z0-9_]+)\s+do/).flatten; puts JSON.generate({lanes:lanes.uniq, platforms:plats.uniq})' "$REPO/fastlane/Fastfile")"

python3 - "$LANES_JSON" "$PLATFORM" "$MODE" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
platform = sys.argv[2]
mode = sys.argv[3]
lanes = set(data.get("lanes") or [])

required = []
# Top-level flutter/rn lanes use bare names; ios/android use platform blocks with lane names build/test/release
if platform in ("ios", "android", ""):
    required = [mode]
elif platform == "flutter_android":
    required = ["flutter_release_android" if mode == "release" else "flutter_build_android"]
elif platform == "flutter_ios":
    required = ["flutter_release_ios" if mode == "release" else "flutter_build_ios"]
elif platform == "react_native_android":
    required = ["react_native_release_android" if mode == "release" else "react_native_build_android"]
elif platform == "react_native_ios":
    required = ["react_native_release_ios" if mode == "release" else "react_native_build_ios"]
else:
    required = [mode]

missing = [r for r in required if r not in lanes]
# For ios/android platform lanes, Fastfile uses lane :build inside platform — name still :build
ok = len(missing) == 0
out = {"status": "pass" if ok else "fail", "lanes_found": sorted(lanes), "required": required, "missing": missing}
print(json.dumps(out, indent=2))
sys.exit(0 if ok else 1)
PY
