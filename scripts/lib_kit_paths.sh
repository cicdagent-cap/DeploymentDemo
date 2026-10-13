# Shared path resolution for source-kit and installed (.github/cicd) layouts.
# shellcheck shell=bash
# Source after setting SCRIPT_DIR to this file's parent (scripts/).

: "${SCRIPT_DIR:?SCRIPT_DIR must be set to scripts/ before sourcing lib_kit_paths.sh}"

CICD_SCRIPTS_DIR="$SCRIPT_DIR"
if [[ -x "$SCRIPT_DIR/resolve_kit_home.sh" ]]; then
  CICD_KIT_HOME="$("$SCRIPT_DIR/resolve_kit_home.sh")"
else
  CICD_KIT_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

# Templates: source kit uses templates/; installed layout uses .github/pipeline-templates/
cicd_find_templates_dir() {
  local repo="${1:-}"
  local candidates=(
    "$CICD_KIT_HOME/templates"
    "$CICD_KIT_HOME/../pipeline-templates"
  )
  if [[ -n "$repo" ]]; then
    candidates+=("$repo/.github/pipeline-templates")
  fi
  local c
  for c in "${candidates[@]}"; do
    if [[ -d "$c" ]]; then
      (cd "$c" && pwd)
      return 0
    fi
  done
  return 1
}

# Sibling tools always run from the scripts directory that contains this file
# (works when CICD_KIT_HOME is .github/cicd without a nested scripts/ tree).
cicd_script() {
  echo "$CICD_SCRIPTS_DIR/$1"
}
