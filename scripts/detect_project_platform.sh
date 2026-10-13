#!/usr/bin/env bash
set -euo pipefail

# Detect mobile project platform and emit CI/CD defaults + candidates.
# Supports: ios, android, flutter, react-native
# Does not invent confirmed app identifiers; placeholders are marked unverified.

REPO_ROOT="$(pwd)"
FORMAT="human"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/detect_project_platform.sh [--repo <path>] [--format human|env|github|json]

Formats:
  human   Print a readable summary (default)
  env     Print shell-safe KEY=VALUE lines (no eval required)
  github  Append platform + runner outputs to GITHUB_OUTPUT
  json    Print a single JSON object including candidates
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
cd "$REPO_ROOT"

EXPLICIT_PLATFORM="${CICD_PLATFORM:-}"
EXPLICIT_BUILD_TARGET="${CICD_BUILD_TARGET:-}"

is_flutter_project() {
  [[ -f "$REPO_ROOT/pubspec.yaml" ]] && grep -qE 'sdk:\s*flutter' "$REPO_ROOT/pubspec.yaml"
}

is_react_native_project() {
  [[ -f "$REPO_ROOT/package.json" ]] && grep -qE '"react-native"\s*:' "$REPO_ROOT/package.json"
}

rel_path() {
  local abs="$1"
  python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$abs" "$REPO_ROOT"
}

# Collect Xcode project/workspace candidates (relative paths), depth-limited.
collect_ios_candidates() {
  find "$REPO_ROOT" \( -path '*/Pods/*' -o -path '*/.git/*' -o -path '*/DerivedData/*' -o -path '*/node_modules/*' -o -path '*/build/*' -o -path '*/.build/*' -o -path '*/cicd-agent-kit/*' -o -path '*/evals/fixtures/*' \) -prune -o \
    \( -type d -name '*.xcodeproj' -o -type d -name '*.xcworkspace' \) -print 2>/dev/null \
    | while read -r p; do
        # Skip nested project.xcworkspace inside xcodeproj unless no other workspace
        case "$p" in
          *.xcodeproj/project.xcworkspace) continue ;;
        esac
        rel_path "$p"
      done | sort -u
}

has_android_project() {
  [[ -d "$REPO_ROOT/android" && ( -f "$REPO_ROOT/android/build.gradle" || -f "$REPO_ROOT/android/build.gradle.kts" || -f "$REPO_ROOT/android/settings.gradle" || -f "$REPO_ROOT/android/settings.gradle.kts" ) ]] \
    || [[ -f "$REPO_ROOT/settings.gradle" || -f "$REPO_ROOT/settings.gradle.kts" ]] \
    || [[ ( -f "$REPO_ROOT/build.gradle" || -f "$REPO_ROOT/build.gradle.kts" ) && -d "$REPO_ROOT/app" ]]
}

gradle_dir() {
  if [[ -d "$REPO_ROOT/android" ]] && [[ -f "$REPO_ROOT/android/settings.gradle" || -f "$REPO_ROOT/android/settings.gradle.kts" || -f "$REPO_ROOT/android/build.gradle" || -f "$REPO_ROOT/android/build.gradle.kts" ]]; then
    echo "android"
  elif [[ -f "$REPO_ROOT/settings.gradle" || -f "$REPO_ROOT/settings.gradle.kts" ]]; then
    echo "."
  else
    echo ""
  fi
}

read_application_id() {
  local gradle_root="$1"
  local gradle_file=""
  local confidence="missing"

  for candidate in \
    "$REPO_ROOT/$gradle_root/app/build.gradle" \
    "$REPO_ROOT/$gradle_root/app/build.gradle.kts" \
    "$REPO_ROOT/$gradle_root/build.gradle" \
    "$REPO_ROOT/$gradle_root/build.gradle.kts"; do
    if [[ -f "$candidate" ]]; then
      gradle_file="$candidate"
      break
    fi
  done

  if [[ -z "$gradle_file" ]]; then
    echo ""
    return
  fi

  local app_id
  app_id="$(grep -E 'applicationId\s*[=:]' "$gradle_file" | head -n1 | sed -E 's/.*applicationId\s*[=:]\s*["'\'']([^"'\'']+)["'\''].*/\1/' || true)"
  if [[ -n "$app_id" && "$app_id" != *"applicationId"* ]]; then
    echo "$app_id"
  else
    echo ""
  fi
}

guess_scheme_from_path() {
  local path="$1"
  local base
  base="$(basename "$path")"
  echo "${base%.xcodeproj}"
  # caller strips xcworkspace similarly
}

CICD_PLATFORM="unknown"
CICD_BUILD_TARGET=""
CICD_BUILD_TARGET_CONFIDENCE=""
CICD_RUNNER="ubuntu-latest"
CICD_FASTLANE_PLATFORM=""
CICD_PROJECT_FILE=""
CICD_PROJECT_FILE_REL=""
CICD_DEFAULT_SCHEME=""
CICD_SCHEME_CONFIDENCE="unverified"
CICD_DEFAULT_CONFIGURATION="Debug"
CICD_TEST_DESTINATION=""
CICD_GRADLE_DIR=""
CICD_GRADLE_TASK_DEBUG="assembleDebug"
CICD_GRADLE_TASK_RELEASE="bundleRelease"
CICD_GRADLE_TASK="assembleDebug"
CICD_APP_IDENTIFIER=""
CICD_APP_IDENTIFIER_CONFIDENCE="missing"
CICD_NODE_VERSION="20"
CICD_IOS_CANDIDATES=""
PLATFORM_CONFIDENCE="unverified"
NOTES=""

IOS_CANDIDATES_LIST="$(collect_ios_candidates || true)"
CICD_IOS_CANDIDATES="$(echo "$IOS_CANDIDATES_LIST" | tr '\n' '|' | sed 's/|$//')"

if [[ -n "$EXPLICIT_PLATFORM" && "$EXPLICIT_PLATFORM" != "auto" ]]; then
  CICD_PLATFORM="$EXPLICIT_PLATFORM"
  PLATFORM_CONFIDENCE="explicit"
elif is_flutter_project; then
  CICD_PLATFORM="flutter"
  PLATFORM_CONFIDENCE="confirmed"
elif is_react_native_project; then
  CICD_PLATFORM="react-native"
  PLATFORM_CONFIDENCE="confirmed"
elif [[ -n "$IOS_CANDIDATES_LIST" ]]; then
  CICD_PLATFORM="ios"
  PLATFORM_CONFIDENCE="confirmed"
elif has_android_project; then
  CICD_PLATFORM="android"
  PLATFORM_CONFIDENCE="confirmed"
fi

if [[ "$CICD_PLATFORM" == "flutter" || "$CICD_PLATFORM" == "react-native" ]]; then
  if [[ -n "$EXPLICIT_BUILD_TARGET" ]]; then
    CICD_BUILD_TARGET="$EXPLICIT_BUILD_TARGET"
    CICD_BUILD_TARGET_CONFIDENCE="explicit"
  else
    CICD_BUILD_TARGET="android"
    CICD_BUILD_TARGET_CONFIDENCE="default_unconfirmed"
    NOTES="${NOTES}Cross-platform default build_target=android is unconfirmed; ask user if iOS is required. "
  fi
  CICD_GRADLE_DIR="$(gradle_dir)"
  CICD_APP_IDENTIFIER="$(read_application_id "${CICD_GRADLE_DIR:-android}")"
  if [[ -n "$CICD_APP_IDENTIFIER" ]]; then
    CICD_APP_IDENTIFIER_CONFIDENCE="confirmed"
  else
    CICD_APP_IDENTIFIER_CONFIDENCE="missing"
  fi
fi

if [[ "$CICD_PLATFORM" == "ios" ]]; then
  # Prefer workspace over project when both exist; keep full relative path.
  WORKSPACE_CANDIDATE="$(echo "$IOS_CANDIDATES_LIST" | grep '\.xcworkspace$' | head -n1 || true)"
  PROJECT_CANDIDATE="$(echo "$IOS_CANDIDATES_LIST" | grep '\.xcodeproj$' | head -n1 || true)"
  if [[ -n "$WORKSPACE_CANDIDATE" ]]; then
    CICD_PROJECT_FILE_REL="$WORKSPACE_CANDIDATE"
  else
    CICD_PROJECT_FILE_REL="$PROJECT_CANDIDATE"
  fi
  CICD_PROJECT_FILE="$CICD_PROJECT_FILE_REL"
  if [[ -n "$CICD_PROJECT_FILE_REL" ]]; then
    base="$(basename "$CICD_PROJECT_FILE_REL")"
    CICD_DEFAULT_SCHEME="${base%.xcodeproj}"
    CICD_DEFAULT_SCHEME="${CICD_DEFAULT_SCHEME%.xcworkspace}"
    CICD_SCHEME_CONFIDENCE="inferred_from_filename"
    NOTES="${NOTES}Scheme inferred from filename; verify with xcodebuild -list. "
  fi
  if [[ -n "${CICD_DEFAULT_SCHEME:-}" && -n "${CICD_TEST_DESTINATION:-}" ]]; then
    :
  fi
  CICD_TEST_DESTINATION="${CICD_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 16}"
  if [[ -n "${FASTLANE_BUNDLE_IDENTIFIER:-}" ]]; then
    CICD_APP_IDENTIFIER="$FASTLANE_BUNDLE_IDENTIFIER"
    CICD_APP_IDENTIFIER_CONFIDENCE="explicit"
  else
    # Best-effort read from pbxproj without claiming release readiness
    if [[ -n "$PROJECT_CANDIDATE" && -f "$REPO_ROOT/$PROJECT_CANDIDATE/project.pbxproj" ]]; then
      bid="$(grep -E 'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*[^;]+;' "$REPO_ROOT/$PROJECT_CANDIDATE/project.pbxproj" \
        | grep -v 'Tests' | head -n1 | sed -E 's/.*=\s*([^;]+);/\1/' | tr -d '[:space:]' || true)"
      if [[ -n "$bid" && "$bid" != *'$(PRODUCT'* ]]; then
        CICD_APP_IDENTIFIER="$bid"
        CICD_APP_IDENTIFIER_CONFIDENCE="inferred"
      fi
    fi
  fi
fi

if [[ "$CICD_PLATFORM" == "android" ]]; then
  CICD_GRADLE_DIR="$(gradle_dir)"
  CICD_APP_IDENTIFIER="$(read_application_id "$CICD_GRADLE_DIR")"
  if [[ -n "$CICD_APP_IDENTIFIER" ]]; then
    CICD_APP_IDENTIFIER_CONFIDENCE="confirmed"
  else
    CICD_APP_IDENTIFIER_CONFIDENCE="missing"
  fi
  CICD_DEFAULT_SCHEME="app"
  CICD_SCHEME_CONFIDENCE="default_module_name"
fi

case "$CICD_PLATFORM" in
  ios)
    CICD_RUNNER="macos-latest"
    CICD_FASTLANE_PLATFORM="ios"
    ;;
  android)
    CICD_RUNNER="ubuntu-latest"
    CICD_FASTLANE_PLATFORM="android"
    CICD_GRADLE_TASK="$CICD_GRADLE_TASK_DEBUG"
    ;;
  flutter)
    if [[ "$CICD_BUILD_TARGET" == "ios" ]]; then
      CICD_RUNNER="macos-latest"
      CICD_FASTLANE_PLATFORM="flutter_ios"
    else
      CICD_RUNNER="ubuntu-latest"
      CICD_FASTLANE_PLATFORM="flutter_android"
      CICD_GRADLE_TASK="$CICD_GRADLE_TASK_DEBUG"
    fi
    ;;
  react-native)
    if [[ "$CICD_BUILD_TARGET" == "ios" ]]; then
      CICD_RUNNER="macos-latest"
      CICD_FASTLANE_PLATFORM="react_native_ios"
    else
      CICD_RUNNER="ubuntu-latest"
      CICD_FASTLANE_PLATFORM="react_native_android"
      CICD_GRADLE_TASK="$CICD_GRADLE_TASK_DEBUG"
    fi
    ;;
esac

NOTES="${NOTES}Suggested runner is a default; discover or ask for project-specific labels. "

emit_human() {
  cat <<EOF
Detected platform: $CICD_PLATFORM (confidence: $PLATFORM_CONFIDENCE)
Suggested runner: $CICD_RUNNER
App identifier: ${CICD_APP_IDENTIFIER:-"(none found)"} ($CICD_APP_IDENTIFIER_CONFIDENCE)
EOF
  [[ -n "$CICD_BUILD_TARGET" ]] && echo "Build target: $CICD_BUILD_TARGET ($CICD_BUILD_TARGET_CONFIDENCE)"
  [[ -n "$CICD_PROJECT_FILE" ]] && echo "Project/workspace: $CICD_PROJECT_FILE"
  [[ -n "$CICD_DEFAULT_SCHEME" ]] && echo "Default scheme/module: $CICD_DEFAULT_SCHEME ($CICD_SCHEME_CONFIDENCE)"
  [[ -n "$CICD_GRADLE_DIR" ]] && echo "Gradle directory: $CICD_GRADLE_DIR"
  [[ -n "$CICD_TEST_DESTINATION" ]] && echo "Test destination: $CICD_TEST_DESTINATION"
  if [[ -n "$IOS_CANDIDATES_LIST" ]]; then
    echo "iOS candidates:"
    echo "$IOS_CANDIDATES_LIST" | sed 's/^/  - /'
  fi
  [[ -n "$NOTES" ]] && echo "Notes: $NOTES"
}

emit_env() {
  # Safe KEY=VALUE for parsers — install.sh must not eval this blindly.
  cat <<EOF
CICD_PLATFORM=$CICD_PLATFORM
CICD_PLATFORM_CONFIDENCE=$PLATFORM_CONFIDENCE
CICD_RUNNER=$CICD_RUNNER
CICD_FASTLANE_PLATFORM=$CICD_FASTLANE_PLATFORM
CICD_APP_IDENTIFIER=$CICD_APP_IDENTIFIER
CICD_APP_IDENTIFIER_CONFIDENCE=$CICD_APP_IDENTIFIER_CONFIDENCE
CICD_DEFAULT_CONFIGURATION=$CICD_DEFAULT_CONFIGURATION
CICD_GRADLE_TASK=$CICD_GRADLE_TASK
CICD_GRADLE_TASK_DEBUG=$CICD_GRADLE_TASK_DEBUG
CICD_GRADLE_TASK_RELEASE=$CICD_GRADLE_TASK_RELEASE
CICD_NODE_VERSION=$CICD_NODE_VERSION
CICD_SCHEME_CONFIDENCE=$CICD_SCHEME_CONFIDENCE
CICD_BUILD_TARGET=$CICD_BUILD_TARGET
CICD_BUILD_TARGET_CONFIDENCE=$CICD_BUILD_TARGET_CONFIDENCE
CICD_PROJECT_FILE=$CICD_PROJECT_FILE
CICD_DEFAULT_SCHEME=$CICD_DEFAULT_SCHEME
CICD_TEST_DESTINATION=$CICD_TEST_DESTINATION
CICD_GRADLE_DIR=$CICD_GRADLE_DIR
CICD_IOS_CANDIDATES=$CICD_IOS_CANDIDATES
EOF
}

emit_github() {
  if [[ -z "${GITHUB_OUTPUT:-}" ]]; then
    echo "GITHUB_OUTPUT is not set" >&2
    exit 1
  fi
  {
    echo "platform=$CICD_PLATFORM"
    echo "runner=$CICD_RUNNER"
    echo "fastlane_platform=$CICD_FASTLANE_PLATFORM"
    echo "build_target=$CICD_BUILD_TARGET"
    echo "gradle_dir=$CICD_GRADLE_DIR"
    echo "gradle_task=$CICD_GRADLE_TASK"
    echo "gradle_task_debug=$CICD_GRADLE_TASK_DEBUG"
    echo "gradle_task_release=$CICD_GRADLE_TASK_RELEASE"
    echo "project_file=$CICD_PROJECT_FILE"
    echo "default_scheme=$CICD_DEFAULT_SCHEME"
  } >> "$GITHUB_OUTPUT"
}

emit_json() {
  python3 - "$CICD_PLATFORM" "$PLATFORM_CONFIDENCE" "$CICD_RUNNER" "$CICD_FASTLANE_PLATFORM" \
    "$CICD_BUILD_TARGET" "$CICD_BUILD_TARGET_CONFIDENCE" "$CICD_PROJECT_FILE" \
    "$CICD_DEFAULT_SCHEME" "$CICD_SCHEME_CONFIDENCE" "$CICD_DEFAULT_CONFIGURATION" \
    "$CICD_TEST_DESTINATION" "$CICD_GRADLE_DIR" "$CICD_GRADLE_TASK" \
    "$CICD_GRADLE_TASK_DEBUG" "$CICD_GRADLE_TASK_RELEASE" \
    "$CICD_APP_IDENTIFIER" "$CICD_APP_IDENTIFIER_CONFIDENCE" "$CICD_NODE_VERSION" \
    "$CICD_IOS_CANDIDATES" "$NOTES" <<'PY'
import json, sys
keys = [
  "platform","platform_confidence","runner","fastlane_platform",
  "build_target","build_target_confidence","project_file",
  "default_scheme","scheme_confidence","default_configuration",
  "test_destination","gradle_dir","gradle_task",
  "gradle_task_debug","gradle_task_release",
  "app_identifier","app_identifier_confidence","node_version",
  "ios_candidates_csv","notes",
]
vals = sys.argv[1:]
data = dict(zip(keys, vals))
cands = [c for c in data.pop("ios_candidates_csv").split("|") if c]
data["ios_candidates"] = cands
data["notes"] = data["notes"].strip()
print(json.dumps(data, indent=2))
PY
}

case "$FORMAT" in
  human) emit_human ;;
  env) emit_env ;;
  github) emit_github ;;
  json) emit_json ;;
  *) echo "Unsupported format: $FORMAT" >&2; exit 1 ;;
esac

if [[ "$CICD_PLATFORM" == "unknown" ]]; then
  exit 1
fi
