#!/bin/bash
set -e

AUTH_MODE="${AUTH_MODE:-fresh}"
AGENT="${AGENT:-claude}"

case "$AGENT" in
  claude|openspec) ;;
  *) echo "error: unknown AGENT '$AGENT' (allowed: claude, openspec)" >&2; exit 1 ;;
esac

case "$AUTH_MODE" in
  persist)
    mkdir -p /home/claude/.claude
    ;;
  fresh|local)
    ;;
esac

exec "$AGENT" "$@"
