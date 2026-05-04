# Examples

## security-tests/test-isolation.sh

Automated test suite that verifies the claude-jail container cannot reach host files outside its declared volume mounts.

Run from the repo root:

```bash
bash examples/security-tests/test-isolation.sh
```

The script builds the image if it is not already built, then runs 7 test groups covering filesystem visibility, path traversal, sensitive file access, workspace write-through, credential availability, privilege escalation, and symlink safety. It exits with code `0` if all tests pass and `1` if any test fails.

See the root [README.md](../README.md) for a full explanation of what each test checks and what the expected output looks like.
