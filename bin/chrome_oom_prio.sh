#!/usr/bin/env bash
# chrome_oom_prio.sh - rank Chrome processes for the OOM killer via oom_score_adj.
#
# For every Chrome *main* process (no --type= flag):
#   - if it exposes --remote-debugging-port, GET http://HOST:PORT/json/list (read-only)
#     and check tab URLs against OOMG_CRITICAL_PATTERNS (extended regex, '|'-separated);
#   - or if its --user-data-dir matches OOMG_CRITICAL_PROFILE_RE;
#   critical  -> main + all descendants get OOMG_ADJ_CRITICAL  (default -500)
#   otherwise -> main gets OOMG_ADJ_MAIN (default -100), renderers get OOMG_ADJ_RENDERER (default 800)
# Idempotent and safe to re-run every loop (PIDs change as tabs open/close).
#
# Env (all optional):
#   OOMG_PROC_ROOT          default /proc (tests point this at a fake tree)
#   OOMG_PROC_NAME          default chrome  (matched against comm)
#   OOMG_CRITICAL_PATTERNS  default 'example\.com/critical'
#   OOMG_CRITICAL_PROFILE_RE default '' (disabled)
#   OOMG_CDP_HOST           default localhost
#   OOMG_CDP_FETCH          command run as: $OOMG_CDP_FETCH URL  (default: curl -s --max-time 2)
#   OOMG_DRY_RUN=1          print planned changes, write nothing
set -u
PROC=${OOMG_PROC_ROOT:-/proc}
NAME=${OOMG_PROC_NAME:-chrome}
PATTERNS=${OOMG_CRITICAL_PATTERNS:-'example\.com/critical'}
PROFILE_RE=${OOMG_CRITICAL_PROFILE_RE:-}
HOST=${OOMG_CDP_HOST:-localhost}
FETCH=${OOMG_CDP_FETCH:-curl -s --max-time 2}
ADJ_CRIT=${OOMG_ADJ_CRITICAL:--500}
ADJ_MAIN=${OOMG_ADJ_MAIN:--100}
ADJ_REND=${OOMG_ADJ_RENDERER:-800}
DRY=${OOMG_DRY_RUN:-0}

cmdline() { tr '\0' ' ' < "$PROC/$1/cmdline" 2>/dev/null; }
ppid_of() { # field 4 of stat; comm (field 2) may contain spaces, so strip up to ')'
  local s; s=$(cat "$PROC/$1/stat" 2>/dev/null) || return 1
  s=${s##*) }; local _st pp _rest; read -r _st pp _rest <<<"$s"; echo "$pp"
}

# Build pid->ppid map once.
declare -A PARENT=()
pids=()
for d in "$PROC"/[0-9]*; do
  p=${d##*/}; pp=$(ppid_of "$p") || continue
  PARENT[$p]=$pp; pids+=("$p")
done
descendants() {
  local root=$1 p changed=1; declare -A set=(["$root"]=1)
  while [ $changed = 1 ]; do changed=0
    for p in "${pids[@]}"; do
      if [ -z "${set[$p]:-}" ] && [ -n "${set[${PARENT[$p]}]:-}" ]; then set[$p]=1; changed=1; fi
    done
  done
  for p in "${!set[@]}"; do [ "$p" != "$root" ] && echo "$p"; done | sort -n
}
set_adj() { # pid value
  local f="$PROC/$1/oom_score_adj"
  [ -e "$f" ] || return 0
  if [ "$DRY" = 1 ]; then echo "would set pid=$1 oom_score_adj=$2"; return 0; fi
  # lowering below the current value needs CAP_SYS_RESOURCE; try sudo -n, never prompt
  { echo "$2" > "$f"; } 2>/dev/null || echo "$2" | sudo -n tee "$f" >/dev/null 2>&1 || true
  echo "set pid=$1 oom_score_adj=$2"
}

for p in "${pids[@]}"; do
  [ "$(cat "$PROC/$p/comm" 2>/dev/null)" = "$NAME" ] || continue
  args=$(cmdline "$p")
  case "$args" in *--type=*) continue;; esac
  port=$(grep -oE -- '--remote-debugging-port=[0-9]+' <<<"$args" | cut -d= -f2 | head -n1)
  crit=0
  if [ -n "$port" ] && [ "$port" != 0 ]; then
    # shellcheck disable=SC2086  # FETCH is intentionally word-split
    $FETCH "http://$HOST:$port/json/list" 2>/dev/null \
      | grep -oE '"url"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -qE -- "$PATTERNS" && crit=1
  fi
  if [ -n "$PROFILE_RE" ] && grep -qE -- "--user-data-dir=[^ ]*($PROFILE_RE)" <<<"$args"; then crit=1; fi
  if [ $crit = 1 ]; then
    echo "critical browser pid=$p port=${port:-none}"
    set_adj "$p" "$ADJ_CRIT"
    for c in $(descendants "$p"); do set_adj "$c" "$ADJ_CRIT"; done
  else
    set_adj "$p" "$ADJ_MAIN"
    for c in $(descendants "$p"); do
      case "$(cmdline "$c")" in *--type=renderer*) set_adj "$c" "$ADJ_REND";; esac
    done
  fi
done
exit 0
