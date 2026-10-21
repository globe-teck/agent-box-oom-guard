#!/usr/bin/env bash
# oom_guard_ensure.sh - idempotent, quiet, safe to call from every shell start.
# 1) swapon existing swapfile  2) earlyoom running  3) mem_watch running  4) Chrome OOM ranks
# Env: OOMG_SWAPFILE (/swapfile) OOMG_EARLYOOM (/usr/bin/earlyoom) OOMG_EARLYOOM_ARGS
#      OOMG_STATE_DIR  OOMG_LOCK (${OOMG_STATE_DIR}/ensure.lock)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
STATE=${OOMG_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/oom-guard}
mkdir -p "$STATE"; LOG=$STATE/ensure.log
exec 9>"${OOMG_LOCK:-$STATE/ensure.lock}"; flock -n 9 || exit 0
SWAP=${OOMG_SWAPFILE:-/swapfile}
EARLYOOM=${OOMG_EARLYOOM:-/usr/bin/earlyoom}
# No "node" in --avoid and no --prefer chrome: see README.
EARGS=${OOMG_EARLYOOM_ARGS:--m 5 -s 10 -r 3600 -p --avoid ^(Xvfb|Xorg|sshd|init|tini|earlyoom|mem_watch.sh)$}
if [ -f "$SWAP" ] && ! grep -q "^$SWAP " /proc/swaps 2>/dev/null; then sudo -n swapon "$SWAP" 2>>"$LOG"; fi
if [ -x "$EARLYOOM" ] && ! pgrep -x earlyoom >/dev/null; then
  # shellcheck disable=SC2086,SC2024  # word-split args; log file is ours, not root's
  sudo -n nohup "$EARLYOOM" $EARGS >>"$STATE/earlyoom.log" 2>&1 </dev/null 9>&- &
fi
if ! pgrep -f "$HERE/mem_watch.sh" >/dev/null; then
  setsid -f nohup bash "$HERE/mem_watch.sh" >>"$STATE/mem_watch.out" 2>&1 </dev/null 9>&-
fi
bash "$HERE/chrome_oom_prio.sh" 9>&- >/dev/null 2>&1
exit 0
