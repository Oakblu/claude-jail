#!/usr/bin/env bash
set -uo pipefail

CLAUDE_JAIL_IMAGE="${CLAUDE_JAIL_IMAGE:-oakblu/claude-jail:latest}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
WORKDIR=""
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  [ -n "$WORKDIR" ] && rm -rf "$WORKDIR"
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

echo "=== test_06_openspec_flag: Verifying --openspec flag ==="

WORKDIR=$(mktemp -d)
chmod 777 "$WORKDIR"

# Test 1: --openspec appears in help output (tests the shell script, no Docker needed)
HELP_OUTPUT=$(bash "$SCRIPT_DIR/../scripts/claude-jail" --help 2>&1)
if echo "$HELP_OUTPUT" | grep -q "\-\-openspec"; then
  assert_pass "--openspec flag documented in --help output"
else
  assert_fail "--openspec flag missing from --help output"
fi

# Test 2: openspec binary exists in the image
RESULT=$(docker run --rm \
  --entrypoint /bin/bash \
  -e AUTH_MODE=fresh \
  -v "$WORKDIR:/workspace" \
  "$CLAUDE_JAIL_IMAGE" \
  -c "which openspec 2>&1") && EXIT=0 || EXIT=$?

if [ $EXIT -eq 0 ] && [ -n "$RESULT" ]; then
  assert_pass "openspec binary exists in image at: $RESULT"
else
  assert_fail "openspec binary not found in image"
fi

# Test 3: AGENT env var controls which binary is exec'd by entrypoint
# Uses a fake binary written into /workspace so no image rebuild is needed
mkdir -p "$WORKDIR/fake-bin"
cat > "$WORKDIR/fake-bin/fake-agent" << 'FAKESCRIPT'
#!/bin/sh
echo "fake-agent-was-called"
FAKESCRIPT
chmod +x "$WORKDIR/fake-bin/fake-agent"

RESULT=$(docker run --rm \
  -e AUTH_MODE=fresh \
  -e AGENT=/workspace/fake-bin/fake-agent \
  -v "$WORKDIR:/workspace" \
  "$CLAUDE_JAIL_IMAGE" 2>&1) && AGENT_EXIT=0 || AGENT_EXIT=$?

if echo "$RESULT" | grep -q "fake-agent-was-called"; then
  assert_pass "AGENT env var selects which binary entrypoint executes"
else
  assert_fail "AGENT env var did not control binary selection (exit=$AGENT_EXIT, got: '$RESULT')"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
