#!/usr/bin/env bash
set -euo pipefail
# Save/load resumable checkpoints without secret values.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/common.sh"

MODE="${1:-save}" # save | load | list
KIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="${CICD_STATE_DIR:-$KIT_ROOT/state/checkpoints}"
mkdir -p "$STATE_DIR"

case "$MODE" in
  list)
    ls -1 "$STATE_DIR" 2>/dev/null || true
    exit 0
    ;;
  load)
    ID="${2:-}"
    [[ -n "$ID" ]] || { echo "Usage: checkpoint.sh load <id>"; exit 1; }
    cat "$STATE_DIR/$ID.json"
    exit 0
    ;;
  save)
    ;;
  *)
    echo "Usage: checkpoint.sh save|load|list [id]"; exit 1
    ;;
esac

REPO="${CICD_REPO_ROOT:-$(pwd)}"
REPO="$(cd "$REPO" && pwd)"
HEAD="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo null)"
DIRTY="$(git -C "$REPO" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
CORR="$(cicd_correlation_id)"
ID="${2:-$CORR}"
PHASE="${CICD_PHASE:-unknown}"
GOAL="${CICD_GOAL:-}"
SCOPE_FILE="${CICD_APPROVED_SCOPE_FILE:-}"

# Strip common secret-like keys from optional JSON blob on stdin
EXTRA="$(cat || true)"
CLEAN_EXTRA="$(EXTRA_JSON="$EXTRA" python3 - <<'PY'
import json, os, re
raw = os.environ.get("EXTRA_JSON", "").strip()
if not raw:
    print("{}")
    raise SystemExit
try:
    data = json.loads(raw)
except Exception:
    print("{}")
    raise SystemExit
SECRET_KEY = re.compile(r"(password|secret|token|authorization|api[_-]?key|keystore|private)", re.I)

def scrub(o):
    if isinstance(o, dict):
        return {k: ("[REDACTED]" if SECRET_KEY.search(k) else scrub(v)) for k, v in o.items()}
    if isinstance(o, list):
        return [scrub(x) for x in o]
    return o

print(json.dumps(scrub(data)))
PY
)"

OUT="$STATE_DIR/$ID.json"
python3 - "$OUT" "$ID" "$(cicd_iso_now)" "$REPO" "$HEAD" "$DIRTY" "$PHASE" "$GOAL" "$SCOPE_FILE" "$CLEAN_EXTRA" "$CORR" <<'PY'
import json, sys
out, id_, ts, repo, head, dirty, phase, goal, scope, extra, corr = sys.argv[1:12]
doc = {
  "checkpoint_id": id_,
  "correlation_id": corr,
  "ts": ts,
  "repo_root": repo,
  "repo_head": None if head == "null" else head,
  "dirty_file_count": int(dirty),
  "phase": phase,
  "goal": goal,
  "approved_scope_file": scope or None,
  "state": json.loads(extra or "{}"),
  "notes": "No secret values are stored in checkpoints.",
}
with open(out, "w") as f:
    json.dump(doc, f, indent=2)
print(out)
PY
