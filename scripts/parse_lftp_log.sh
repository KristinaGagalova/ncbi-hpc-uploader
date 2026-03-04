#!/usr/bin/env bash
set -euo pipefail

LOG="${1:-}"
if [[ -z "$LOG" || ! -f "$LOG" ]]; then
  echo "Usage: $0 <path/to/upload.log>" >&2
  exit 1
fi

# Normalize carriage returns so ^M-progress lines become separate lines
# (lftp progress uses \r)
CLEAN="$(mktemp)"
trap 'rm -f "$CLEAN"' EXIT
tr '\r' '\n' < "$LOG" > "$CLEAN"

echo "=== Parsing: $LOG ==="
echo

echo "## Summary"
total_put_cmds=$(grep -E '^\+ (put|mput)\b' "$CLEAN" | wc -l || true)
mkdir_ok=$(grep -E 'mkdir ok' "$CLEAN" | wc -l || true)
cd_ok=$(grep -E 'cd ok' "$CLEAN" | wc -l || true)
echo "put/mput commands: $total_put_cmds"
echo "cd ok:            $cd_ok"
echo "mkdir ok:         $mkdir_ok"
echo

echo "## Errors / Warnings (high confidence)"
# Common lftp/sftp error patterns
grep -nE \
  'Permission denied|Authentication failed|Login failed|Not connected|Connection (closed|reset)|Broken pipe|Host key verification failed|No route to host|Network is unreachable|Timeout|timed out|Cannot open|failed|Failure|Error|550 |553 |No such file|Could not|refused|Too many connections|quota|disk|write failed|Read-only file system' \
  "$CLEAN" || echo "(none found)"
echo

echo "## SFTP protocol / server-side responses (often useful)"
grep -nE \
  'sftp:|SSH_FX_|status=|remote:|fatal:|Received disconnect|kex_|handshake' \
  "$CLEAN" || echo "(none found)"
echo

echo "## Possible incomplete/aborted transfers"
# Heuristic: see "Sending data" for file A then immediately another file starts or connection drops,
# without seeing a clean finish marker. Logs are messy, so we flag suspicious lines.
grep -nE \
  '\[Sending data\]|\[Waiting for response\.\.\.\]|eta:' \
  "$CLEAN" | tail -n 50

echo
echo "Tip: Best verification is comparing remote sizes vs local sizes (see verify_remote_sizes.sh)."
