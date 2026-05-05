#!/usr/bin/env bash
set -uo pipefail

CLAUDE_JAIL_IMAGE="${CLAUDE_JAIL_IMAGE:-oakblu/claude-jail:latest}"
WORKDIR1=""
WORKDIR2=""
WORKDIR3=""
PASS_COUNT=0
FAIL_COUNT=0
TEST_ID="$$"

cleanup() {
  docker rm -f \
    "cj-test-1-$TEST_ID" \
    "cj-test-2-$TEST_ID" \
    "cj-test-3-$TEST_ID" \
    2>/dev/null || true
  [ -n "$WORKDIR1" ] && rm -rf "$WORKDIR1"
  [ -n "$WORKDIR2" ] && rm -rf "$WORKDIR2"
  [ -n "$WORKDIR3" ] && rm -rf "$WORKDIR3"
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

echo "=== test_05_multi_instance: Verifying concurrent container instances ==="

WORKDIR1=$(mktemp -d)
WORKDIR2=$(mktemp -d)
WORKDIR3=$(mktemp -d)

echo "instance-1" > "$WORKDIR1/id.txt"
echo "instance-2" > "$WORKDIR2/id.txt"
echo "instance-3" > "$WORKDIR3/id.txt"

docker run -d \
  --name "cj-test-1-$TEST_ID" \
  --entrypoint /bin/bash \
  -e AUTH_MODE=fresh \
  -v "$WORKDIR1:/workspace" \
  "$CLAUDE_JAIL_IMAGE" \
  -c "sleep 60"

docker run -d \
  --name "cj-test-2-$TEST_ID" \
  --entrypoint /bin/bash \
  -e AUTH_MODE=fresh \
  -v "$WORKDIR2:/workspace" \
  "$CLAUDE_JAIL_IMAGE" \
  -c "sleep 60"

docker run -d \
  --name "cj-test-3-$TEST_ID" \
  --entrypoint /bin/bash \
  -e AUTH_MODE=fresh \
  -v "$WORKDIR3:/workspace" \
  "$CLAUDE_JAIL_IMAGE" \
  -c "sleep 60"

sleep 2

for i in 1 2 3; do
  NAME="cj-test-$i-$TEST_ID"
  STATUS=$(docker inspect --format='{{.State.Status}}' "$NAME" 2>/dev/null || echo "not_found")
  if [ "$STATUS" = "running" ]; then
    assert_pass "Instance $i is running"
  else
    assert_fail "Instance $i is not running (status: $STATUS)"
  fi
done

for i in 1 2 3; do
  NAME="cj-test-$i-$TEST_ID"
  OUTPUT=$(docker exec "$NAME" cat /workspace/id.txt 2>/dev/null || true)
  if [ "$OUTPUT" = "instance-$i" ]; then
    assert_pass "Instance $i sees its own workdir (reads 'instance-$i')"
  else
    assert_fail "Instance $i workdir not isolated (got: '$OUTPUT', expected: 'instance-$i')"
  fi
done

docker exec "cj-test-1-$TEST_ID" bash -c "echo 'written-by-1' > /workspace/cross-check.txt" 2>/dev/null
SEEN_BY_2=$(docker exec "cj-test-2-$TEST_ID" cat /workspace/cross-check.txt 2>/dev/null || echo "not-found")
if [ "$SEEN_BY_2" = "not-found" ]; then
  assert_pass "File written in instance 1 is not visible in instance 2"
else
  assert_fail "File written in instance 1 leaked into instance 2"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
