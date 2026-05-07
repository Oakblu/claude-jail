#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

TESTS=(
  test_01_software.sh
  test_02_isolation.sh
  test_03_workdir.sh
  test_04_auth_modes.sh
  test_05_multi_instance.sh
  test_06_openspec_flag.sh
)

PASS=0
FAIL=0

for test_file in "${TESTS[@]}"; do
  echo ""
  echo "════════════════════════════════════════"
  echo "Running: $test_file"
  echo "════════════════════════════════════════"
  if bash "$SCRIPT_DIR/$test_file"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "════════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
echo "════════════════════════════════════════"

[ "$FAIL" -eq 0 ]
