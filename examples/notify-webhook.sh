#!/usr/bin/env bash
# Example OOMG_NOTIFY hook: POST title/body as JSON to a webhook URL in OOMG_WEBHOOK_URL.
# Exit status non-zero = notify failed (mem_watch logs it and will retry after dedupe window).
set -eu
python3 -c 'import json,sys; print(json.dumps({"title":sys.argv[1],"text":sys.argv[2]}))' "$1" "$2" \
  | curl -fsS --max-time 5 -H 'Content-Type: application/json' -d @- "${OOMG_WEBHOOK_URL:?}" >/dev/null
