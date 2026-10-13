#!/usr/bin/env bash
set -euo pipefail
# Append redacted observability events to a trace file.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/common.sh"

EVENT="${1:-}"
shift || true
TRACE_FILE="${CICD_TRACE_FILE:-}"
KIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="${CICD_STATE_DIR:-$KIT_ROOT/state}"
mkdir -p "$STATE_DIR"
CORR="$(cicd_correlation_id)"
export CICD_CORRELATION_ID="$CORR"
if [[ -z "$TRACE_FILE" ]]; then
  TRACE_FILE="$STATE_DIR/trace-${CORR}.jsonl"
fi

ARGS_JSON="$(printf '%s\n' "$@" | cicd_redact | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip().splitlines()))')"
TS="$(cicd_iso_now)"

python3 - "$TRACE_FILE" "$TS" "$CORR" "$EVENT" "$ARGS_JSON" <<'PY'
import json, sys
path, ts, corr, event, args_json = sys.argv[1:6]
rec = {
  "ts": ts,
  "correlation_id": corr,
  "event": event,
  "args": json.loads(args_json),
  "kit_version": "1.2.0",
}
with open(path, "a") as f:
    f.write(json.dumps(rec) + "\n")
print(path)
PY
