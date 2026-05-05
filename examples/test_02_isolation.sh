#!/usr/bin/env bash
set -uo pipefail

CLAUDE_JAIL_IMAGE="${CLAUDE_JAIL_IMAGE:-oakblu/claude-jail:latest}"
WORKDIR=""
SECRET_DIR=""
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  [ -n "$WORKDIR" ]    && rm -rf "$WORKDIR"
  [ -n "$SECRET_DIR" ] && rm -rf "$SECRET_DIR"
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

echo "=== test_02_isolation: Verifying filesystem isolation ==="

WORKDIR=$(mktemp -d)
chmod 755 "$WORKDIR"
SECRET_DIR=$(mktemp -d)
echo "host-secret-content" > "$SECRET_DIR/secret.txt"

RESULT=$(run_in_container "cat '$SECRET_DIR/secret.txt' 2>&1; echo exit:\$?" || true)
if echo "$RESULT" | grep -q "host-secret-content"; then
  assert_fail "Container can read host secret file — isolation breach at $SECRET_DIR"
else
  assert_pass "Container cannot access host secret file outside /workspace"
fi

RESULT=$(run_in_container "ls /Users 2>&1; echo exit:\$?" || true)
if echo "$RESULT" | grep -q "No such file\|exit:1\|exit:2"; then
  assert_pass "/Users path does not exist inside the container"
else
  assert_fail "/Users exists inside the container unexpectedly"
fi

RESULT=$(run_in_container "ls /private 2>&1; echo exit:\$?" || true)
if echo "$RESULT" | grep -q "No such file\|exit:1\|exit:2"; then
  assert_pass "/private path does not exist inside the container"
else
  assert_fail "/private exists inside the container unexpectedly"
fi

echo "workspace-visible" > "$WORKDIR/probe.txt"
RESULT=$(run_in_container "cat /workspace/probe.txt 2>&1" || true)
if [ "$RESULT" = "workspace-visible" ]; then
  assert_pass "/workspace is accessible inside the container"
else
  assert_fail "/workspace is not accessible inside the container"
fi

RESULT=$(run_in_container "ls /workspace/../../../ 2>&1" || true)
if echo "$RESULT" | grep -qE "^(System|Library|Volumes|Applications)$"; then
  assert_fail "Path traversal from /workspace reached macOS host root (isolation breach)"
else
  assert_pass "Path traversal from /workspace stays within the container's Linux namespace"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
