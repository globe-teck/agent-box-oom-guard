#!/usr/bin/env bash
# swapfile_setup.sh - create and enable a swapfile. DRY-RUN BY DEFAULT.
# Usage: swapfile_setup.sh [--apply] [--size 4G] [--path /swapfile] [--swappiness 10] [--persist]
#   --persist  also append to /etc/fstab (skip on containers where fstab isn't honoured)
set -eu
APPLY=0; SIZE=4G; PATHF=/swapfile; SWAPPINESS=10; PERSIST=0
while [ $# -gt 0 ]; do case "$1" in
  --apply) APPLY=1;; --size) SIZE=$2; shift;; --path) PATHF=$2; shift;;
  --swappiness) SWAPPINESS=$2; shift;; --persist) PERSIST=1;;
  -h|--help) sed -n '2,4p' "$0"; exit 0;;
  *) echo "unknown arg: $1" >&2; exit 2;; esac; shift; done
run() { if [ "$APPLY" = 1 ]; then echo "+ $*"; "$@"; else echo "[dry-run] $*"; fi; }
SUDO=""; [ "$(id -u)" = 0 ] || SUDO="sudo"
if grep -q "^$PATHF " /proc/swaps 2>/dev/null; then echo "$PATHF already active"; exit 0; fi
if [ ! -f "$PATHF" ]; then
  run $SUDO fallocate -l "$SIZE" "$PATHF"
  run $SUDO chmod 600 "$PATHF"
  run $SUDO mkswap "$PATHF"
fi
run $SUDO swapon "$PATHF"
run $SUDO sysctl -q -w vm.swappiness="$SWAPPINESS"
if [ "$PERSIST" = 1 ] && ! grep -q "^$PATHF " /etc/fstab 2>/dev/null; then
  if [ "$APPLY" = 1 ]; then echo "$PATHF none swap sw 0 0" | $SUDO tee -a /etc/fstab >/dev/null; else echo "[dry-run] append '$PATHF none swap sw 0 0' to /etc/fstab"; fi
fi
[ "$APPLY" = 1 ] || echo "Dry run only. Re-run with --apply to make changes."
