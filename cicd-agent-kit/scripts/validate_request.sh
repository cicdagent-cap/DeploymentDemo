#!/usr/bin/env bash
set -euo pipefail

REQUEST=""
REPO=""
CATALOG=""
KIT_ROOT="$("$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve_kit_home.sh")"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --request) REQUEST="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --catalog) CATALOG="${2:-}"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$REQUEST" && -f "$REQUEST" ]] || { echo "Usage: validate_request.sh --request <file> [--repo <path>]"; exit 1; }
CATALOG="${CATALOG:-$KIT_ROOT/capabilities/catalog.yml}"
SCHEMA="$KIT_ROOT/schemas/pipeline-request.schema.json"

python3 - "$REQUEST" "$CATALOG" "$SCHEMA" "${REPO:-}" <<'PY'
import json, sys, subprocess
from pathlib import Path

req_path, catalog_path, schema_path, repo = sys.argv[1:5]
text = Path(req_path).read_text()
req = json.loads(subprocess.check_output(
    ["ruby", "-ryaml", "-rjson", "-e", "print JSON.generate(YAML.safe_load(STDIN.read, aliases: true) || {})"],
    input=text.encode(),
))
catalog = json.loads(subprocess.check_output(
    ["ruby", "-ryaml", "-rjson", "-e", "print JSON.generate(YAML.safe_load(STDIN.read, aliases: true) || {})"],
    input=Path(catalog_path).read_bytes(),
))

errors = []
warnings = []

# schema-ish required fields
if not isinstance(req.get("pipeline"), dict):
    errors.append("pipeline object required")
else:
    if not req["pipeline"].get("name"):
        errors.append("pipeline.name required")
    if not req["pipeline"].get("output_file"):
        errors.append("pipeline.output_file required")

provider = req.get("provider")
if provider not in ("github_actions", "jenkins"):
    errors.append("provider must be github_actions or jenkins")

# capability catalog membership
known = set()
for section, items in catalog.items():
    if isinstance(items, list):
        for it in items:
            if isinstance(it, dict) and "id" in it:
                known.add(it["id"])
caps = req.get("capabilities") or []
if not isinstance(caps, list):
    errors.append("capabilities must be a list")
    caps = []
unknown = [c for c in caps if c not in known]
if unknown:
    errors.append(f"unknown capabilities: {unknown}")

destination = req.get("destination") or (req.get("presets") or {}).get("destination")
dest = req.get("destination", "artifacts-only")
build_cfg = (req.get("build_configuration") or "Debug").lower()
signing = ((req.get("signing") or {}).get("strategy")) or "none"

# unsupported combinations — TestFlight/Play judged by signing/export requirements, not the Debug label alone
if dest in ("testflight", "google_play", "firebase_app_distribution") and "build" not in caps and "ios_archive_ipa" not in caps and "android_apk_aab" not in caps:
    warnings.append("distribution destination selected but archive/package capabilities not listed")
if dest == "testflight" and "testflight" not in caps:
    errors.append("destination testflight requires capability testflight")
if dest == "firebase_app_distribution" and "firebase_app_distribution" not in caps:
    errors.append("destination firebase_app_distribution requires capability firebase_app_distribution")
if dest == "google_play" and "google_play_tracks" not in caps:
    errors.append("destination google_play requires capability google_play_tracks")
if dest == "testflight":
    # App Store / TestFlight need a signed device IPA export path — unsigned CI cannot ship.
    if signing in ("none", "", None):
        errors.append("testflight incompatible with signing.strategy=none (requires match/manual/automatic + exportable IPA)")
    elif "ios_archive_ipa" not in caps:
        warnings.append("testflight without capability ios_archive_ipa — confirm export/archive path exists")
    if build_cfg == "debug":
        warnings.append("build_configuration Debug is unusual for TestFlight; validate export method/signing, not the name alone")
if dest == "google_play" and signing == "none":
    errors.append("google_play incompatible with signing.strategy=none (requires release signing + AAB)")
if dest == "google_play" and build_cfg == "debug":
    warnings.append("build_configuration Debug is unusual for Google Play; validate release signing/export, not the name alone")

platform = ((req.get("platform") or {}).get("override") or (req.get("platform") or {}).get("detection") or "auto")
build_target = (req.get("platform") or {}).get("build_target")
if platform in ("flutter", "react-native") and not build_target:
    warnings.append("cross-platform build_target unset — ambiguous android/ios")

# jenkins honesty: generation allowed; remote trigger needs creds later
prov_status = (catalog.get("providers") or {}).get("jenkins", {}).get("status")
# catalog structure uses providers map at top in our catalog - check
jenkins_status = None
providers = catalog.get("providers") or {}
if isinstance(providers, dict):
    jenkins_status = (providers.get("jenkins") or {}).get("status")

normalized = {
    "provider": provider,
    "capabilities": caps,
    "destination": dest,
    "build_configuration": req.get("build_configuration") or "Debug",
    "environment": req.get("environment"),
    "market": req.get("market"),
    "variant": req.get("variant"),
    "runner_label": req.get("runner_label") or (req.get("github_actions") or {}).get("runner_label"),
    "platform": platform,
    "build_target": build_target,
    "signing_strategy": signing,
    "reuse_existing_if_suitable": bool((req.get("pipeline") or {}).get("reuse_existing_if_suitable", True)),
}

out = {"status": "pass" if not errors else "fail", "errors": errors, "warnings": warnings, "normalized": normalized, "jenkins_catalog_status": jenkins_status}
print(json.dumps(out, indent=2))
sys.exit(0 if not errors else 1)
PY
