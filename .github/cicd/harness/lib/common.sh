#!/usr/bin/env bash
# Shared helpers for harness scripts. No secrets logged.

cicd_kit_root() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[1]}")/../.." && pwd)"
  if [[ -f "$here/manifest.yml" ]]; then
    echo "$here"
  else
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
  fi
}

cicd_redact() {
  python3 - "$@" <<'PY'
import json, re, sys
text = sys.stdin.read() if not sys.argv[1:] else " ".join(sys.argv[1:])
patterns = [
    (r'(?i)(password|passwd|secret|token|authorization|api[_-]?key)\s*[:=]\s*\S+', r'\1=[REDACTED]'),
    (r'-----BEGIN [A-Z ]+PRIVATE KEY-----.*?-----END [A-Z ]+PRIVATE KEY-----', '[REDACTED_PRIVATE_KEY]'),
    (r'ghp_[A-Za-z0-9]{20,}', 'ghp_[REDACTED]'),
    (r'gho_[A-Za-z0-9]{20,}', 'gho_[REDACTED]'),
]
for pat, repl in patterns:
    text = re.sub(pat, repl, text, flags=re.S)
print(text, end="" if text.endswith("\n") or not text else "")
PY
}

cicd_iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

cicd_correlation_id() {
  if [[ -n "${CICD_CORRELATION_ID:-}" ]]; then
    echo "$CICD_CORRELATION_ID"
    return
  fi
  python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
}
