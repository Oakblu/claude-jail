#!/usr/bin/env bash
set -uo pipefail

CLAUDE_JAIL_IMAGE="${CLAUDE_JAIL_IMAGE:-oakblu/claude-jail:latest}"
WORKDIR=""
FAKE_CLAUDE=""
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  [ -n "$WORKDIR" ]     && rm -rf "$WORKDIR"
  [ -n "$FAKE_CLAUDE" ] && rm -rf "$FAKE_CLAUDE"
}
trap cleanup EXIT

assert_pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "[PASS] $1"
}

assert_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "[FAIL] $1"
}

echo "=== test_04_auth_modes: Verifying authentication modes ==="

WORKDIR=$(mktemp -d)
chmod 755 "$WORKDIR"

RESULT=$(docker run --rm \
  --entrypoint /bin/bash \
  -e AUTH_MODE=fresh \
  -v "$WORKDIR:/workspace" \
  "$CLAUDE_JAIL_IMAGE" \
  -c "[ -d /home/claude/.claude ] && echo exists || echo missing" 2>&1)

if [ "$RESULT" = "missing" ]; then
  assert_pass "fresh mode: /home/claude/.claude does not exist"
else
  assert_fail "fresh mode: /home/claude/.claude unexpectedly exists"
fi

FAKE_CLAUDE=$(mktemp -d)
chmod 755 "$FAKE_CLAUDE"
echo "sentinel-content" > "$FAKE_CLAUDE/sentinel.txt"

RESULT=$(docker run --rm \
  --entrypoint /bin/bash \
  -e AUTH_MODE=local \
  -v "$WORKDIR:/workspace" \
  -v "$FAKE_CLAUDE:/home/claude/.claude:rw" \
  "$CLAUDE_JAIL_IMAGE" \
  -c "cat /home/claude/.claude/sentinel.txt 2>&1")

if [ "$RESULT" = "sentinel-content" ]; then
  assert_pass "local mode: host Claude config dir is accessible inside the container"
else
  assert_fail "local mode: host Claude config not readable (got: '$RESULT')"
fi

mkdir -p "$WORKDIR/.claude-jail"

docker run --rm \
  --entrypoint /bin/bash \
  -e AUTH_MODE=persist \
  -v "$WORKDIR:/workspace" \
  -v "$WORKDIR/.claude-jail:/home/claude/.claude:rw" \
  "$CLAUDE_JAIL_IMAGE" \
  -c "echo 'persisted-data' > /home/claude/.claude/marker.txt" 2>&1

if [ -f "$WORKDIR/.claude-jail/marker.txt" ]; then
  assert_pass "persist mode: file written inside container is visible in .claude-jail/ on host"
else
  assert_fail "persist mode: .claude-jail/marker.txt not found on host"
fi

CONTENT=$(cat "$WORKDIR/.claude-jail/marker.txt" 2>/dev/null || true)
if [ "$CONTENT" = "persisted-data" ]; then
  assert_pass "persist mode: persisted content is correct"
else
  assert_fail "persist mode: persisted content incorrect (got: '$CONTENT')"
fi

RESULT=$(docker run --rm \
  --entrypoint /bin/bash \
  -e AUTH_MODE=fresh \
  -v "$WORKDIR:/workspace" \
  "$CLAUDE_JAIL_IMAGE" \
  -c "[ -f /home/claude/.claude/sentinel.txt ] && echo found || echo not-found" 2>&1)

if [ "$RESULT" = "not-found" ]; then
  assert_pass "fresh mode does not inherit config from previous local mode run"
else
  assert_fail "fresh mode has unexpected access to local mode config"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
