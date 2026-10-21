#!/usr/bin/env bash
# mem_watch.sh - alert when MemAvailable drops under a threshold; re-apply Chrome OOM ranks.
# Env: OOMG_THRESH_MB (2048) OOMG_INTERVAL (60) OOMG_ONCE (0) OOMG_DEDUPE_SEC (1800)
#      OOMG_STATE_DIR (${XDG_STATE_HOME:-$HOME/.local/state}/oom-guard) OOMG_PROC_ROOT (/proc)
#      OOMG_NOTIFY  command; called as: $OOMG_NOTIFY "<title>" "<body>"  (default: logger/stderr)
#      OOMG_PRIO_SCRIPT (sibling chrome_oom_prio.sh; set to "" to skip)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PROC=${OOMG_PROC_ROOT:-/proc}
THRESH=${OOMG_THRESH_MB:-2048}; INTERVAL=${OOMG_INTERVAL:-60}; ONCE=${OOMG_ONCE:-0}
DEDUPE=${OOMG_DEDUPE_SEC:-1800}
STATE=${OOMG_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/oom-guard}
PRIO=${OOMG_PRIO_SCRIPT-$HERE/chrome_oom_prio.sh}
mkdir -p "$STATE"; STAMP=$STATE/last_alert; LOG=$STATE/mem_watch.log

default_notify() { logger -t oom-guard -- "$1: $2" 2>/dev/null; echo "ALERT $1: $2" >&2; }
notify() { if [ -n "${OOMG_NOTIFY:-}" ]; then $OOMG_NOTIFY "$1" "$2"; else default_notify "$1" "$2"; fi; }

top_rss() { # top 5 by VmRSS from the proc tree
  for d in "$PROC"/[0-9]*; do
    r=$(awk '/^VmRSS:/{print $2}' "$d/status" 2>/dev/null) || continue
    [ -n "$r" ] && echo "$r $(cat "$d/comm" 2>/dev/null)"
  done | sort -rn | head -n5 | awk '{printf "%s(%dMB) ", $2, $1/1024}'
}

check_once() {
  local av sf ts line now last body
  read -r av sf < <(awk '/^MemAvailable:/{a=int($2/1024)} /^SwapFree:/{s=int($2/1024)} END{print a+0, s+0}' "$PROC/meminfo")
  ts=$(date '+%F %T %Z'); line="$ts MemAvailable=${av}MB SwapFree=${sf}MB thresh=${THRESH}MB"
  if [ "$av" -lt "$THRESH" ]; then
    now=$(date +%s); last=$(cat "$STAMP" 2>/dev/null || echo 0)
    if [ $((now - last)) -ge "$DEDUPE" ]; then
      echo "$now" > "$STAMP"
      body="MemAvailable ${av}MB < ${THRESH}MB, SwapFree ${sf}MB at $ts. Top RSS: $(top_rss)"
      if notify "Memory low: ${av}MB available" "$body"; then line="$line ALERT sent"
      else line="$line ALERT notify-failed"; fi
    else line="$line low (deduped)"; fi
  fi
  if [ -n "$PRIO" ] && [ -f "$PRIO" ]; then bash "$PRIO" >/dev/null 2>&1; fi
  echo "$line" | tee -a "$LOG"
  tail -n 2000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
}

while :; do
  check_once
  [ "$ONCE" = 1 ] && break
  sleep "$INTERVAL"
done
