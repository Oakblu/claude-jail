#!/usr/bin/env bash
set -uo pipefail

CLAUDE_JAIL_IMAGE="${CLAUDE_JAIL_IMAGE:-oakblu/claude-jail:latest}"
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

run_in_container() {
  docker run --rm \
    --entrypoint /bin/bash \
    -e AUTH_MODE=fresh \
    -v "$WORKDIR:/workspace" \
    "$CLAUDE_JAIL_IMAGE" \
    -c "$1" 2>&1
}

echo "=== test_03_workdir: Verifying workdir mounting ==="

WORKDIR=$(mktemp -d)
chmod 777 "$WORKDIR"

echo "hello-from-host" > "$WORKDIR/host-file.txt"
OUTPUT=$(run_in_container "cat /workspace/host-file.txt")
if [ "$OUTPUT" = "hello-from-host" ]; then
  assert_pass "Container can read host-created file in /workspace"
else
  assert_fail "Container cannot read host-created file (got: '$OUTPUT')"
fi

run_in_container "echo 'hello-from-container' > /workspace/container-file.txt"
if [ -f "$WORKDIR/container-file.txt" ]; then
  assert_pass "File written inside container is visible on host"
else
  assert_fail "File written inside container is NOT visible on host"
fi

CONTENT=$(cat "$WORKDIR/container-file.txt" 2>/dev/null || true)
if [ "$CONTENT" = "hello-from-container" ]; then
  assert_pass "Container-written file has correct content"
else
  assert_fail "Container-written file has incorrect content (got: '$CONTENT')"
fi

MARKER="marker-$$"
echo "$MARKER" > "$WORKDIR/marker.txt"
OUTPUT=$(run_in_container "cat /workspace/marker.txt")
if [ "$OUTPUT" = "$MARKER" ]; then
  assert_pass "HOST_WORKDIR correctly maps to /workspace inside the container"
else
  assert_fail "Mount mismatch (got: '$OUTPUT', expected: '$MARKER')"
fi

run_in_container "touch /workspace/dir-test-a.txt /workspace/dir-test-b.txt"
if [ -f "$WORKDIR/dir-test-a.txt" ] && [ -f "$WORKDIR/dir-test-b.txt" ]; then
  assert_pass "Multiple files written by container are all visible on host"
else
  assert_fail "Not all container-created files are visible on host"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
