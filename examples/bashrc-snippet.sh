# shellcheck shell=bash
# Put this ABOVE the interactive guard in ~/.bashrc, i.e. before a line like
#   case $- in *i*) ;; *) return;; esac
# so non-interactive shells that agents spawn also run it. It is lock-guarded and quiet.
[ -x "$HOME/agent-box-oom-guard/bin/oom_guard_ensure.sh" ] && \
  ( "$HOME/agent-box-oom-guard/bin/oom_guard_ensure.sh" >/dev/null 2>&1 & )
