#!/bin/bash
set -e

AUTH_MODE="${AUTH_MODE:-fresh}"
AGENT="${AGENT:-claude}"

case "$AUTH_MODE" in
  persist)
    mkdir -p /home/claude/.claude
    ;;
  fresh|local)
    ;;
esac

exec "$AGENT" "$@"
