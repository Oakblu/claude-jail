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

echo "=== test_01_software: Verifying installed tools ==="

WORKDIR=$(mktemp -d)

check_version() {
  local tool="$1"
  local cmd="${2:-$tool --version}"
  local OUTPUT
  OUTPUT=$(run_in_container "$cmd" 2>&1) && EXIT=0 || EXIT=$?
  if [ $EXIT -eq 0 ] && [ -n "$OUTPUT" ]; then
    assert_pass "$tool: $OUTPUT"
  else
    assert_fail "$tool not found or returned no output"
  fi
}

check_exists() {
  local tool="$1"
  local OUTPUT
  OUTPUT=$(run_in_container "which $tool 2>&1") && EXIT=0 || EXIT=$?
  if [ $EXIT -eq 0 ] && [ -n "$OUTPUT" ]; then
    assert_pass "$tool exists at: $OUTPUT"
  else
    assert_fail "$tool binary not found in PATH"
  fi
}

check_host_version() {
  local tool="$1"
  local cmd="${2:-$tool --version}"
  local OUTPUT
  OUTPUT=$(eval "$cmd" 2>&1) && EXIT=0 || EXIT=$?
  if [ $EXIT -eq 0 ] && [ -n "$OUTPUT" ]; then
    assert_pass "$tool: $OUTPUT"
  else
    assert_fail "$tool not found or returned no output"
  fi
}

check_version "node"
check_version "npm"
check_host_version "yarn"
check_host_version "pnpm"
check_version "bun"
check_version "cargo"
check_version "rustc"
check_version "python3"
check_exists  "claude"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
