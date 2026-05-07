# OpenSpec Flag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--openspec` flag to `claude-jail` that runs `openspec` instead of `claude` inside the Docker sandbox, using an `AGENT` env var to parameterize the container binary.

**Architecture:** A second env var `AGENT` (default `claude`) is passed from the shell script to the container via `docker run -e`. `entrypoint.sh` reads it and replaces `exec claude "$@"` with `exec "$AGENT" "$@"`. The shell script recognises `--openspec` and sets `AGENT=openspec`; auth mode flags remain orthogonal.

**Tech Stack:** Bash, Docker, Node.js/npm (`@fission-ai/openspec@latest`).

---

## File Map

| File | Action | What changes |
|---|---|---|
| `docker/Dockerfile` | Modify | Add `@fission-ai/openspec@latest` to npm install line |
| `docker/entrypoint.sh` | Modify | Add `AGENT` env var; replace `exec claude` with `exec "$AGENT"` |
| `scripts/claude-jail` | Modify | Add `--openspec` flag parsing; pass `AGENT` to docker run; update help text |
| `examples/test_01_software.sh` | Modify | Add `check_exists "openspec"` |
| `examples/test_06_openspec_flag.sh` | Create | Tests: `--openspec` in help, AGENT mechanism, openspec binary in image |
| `examples/run_all_tests.sh` | Modify | Add `test_06_openspec_flag.sh` to test list |
| `README.md` | Modify | Document `--openspec` flag in auth modes table and examples |

---

## Task 1: Write the failing test for `check_exists "openspec"`

**Files:**
- Modify: `examples/test_01_software.sh`

- [ ] **Step 1: Add `check_exists "openspec"` to test_01_software.sh**

Open `examples/test_01_software.sh`. After the existing `check_exists "claude"` line (line 80), add:

```bash
check_exists  "openspec"
```

The file's check block should now look like:

```bash
check_exists  "claude"
check_exists  "openspec"
```

- [ ] **Step 2: Run test_01 to confirm it fails**

```bash
bash examples/test_01_software.sh
```

Expected: `[FAIL] openspec binary not found in PATH` — confirming the test correctly detects the missing binary.

---

## Task 2: Write the failing tests for the `--openspec` flag

**Files:**
- Create: `examples/test_06_openspec_flag.sh`

- [ ] **Step 1: Create `examples/test_06_openspec_flag.sh`**

```bash
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
#!/bin/bash
echo "fake-agent-was-called"
FAKESCRIPT
chmod +x "$WORKDIR/fake-bin/fake-agent"

RESULT=$(docker run --rm \
  -e AUTH_MODE=fresh \
  -e AGENT=/workspace/fake-bin/fake-agent \
  -v "$WORKDIR:/workspace" \
  "$CLAUDE_JAIL_IMAGE" 2>&1) || true

if echo "$RESULT" | grep -q "fake-agent-was-called"; then
  assert_pass "AGENT env var selects which binary entrypoint executes"
else
  assert_fail "AGENT env var did not control binary selection (got: '$RESULT')"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x examples/test_06_openspec_flag.sh
```

- [ ] **Step 3: Run it to confirm tests 1 and 3 fail (test 2 may pass or fail depending on current image)**

```bash
bash examples/test_06_openspec_flag.sh
```

Expected: `[FAIL] --openspec flag missing from --help output` and `[FAIL] AGENT env var did not control binary selection`. Test 2 (openspec in image) will also fail if using the current published image.

---

## Task 3: Update the Dockerfile to install openspec

**Files:**
- Modify: `docker/Dockerfile`

- [ ] **Step 1: Add openspec to the npm install line**

Find this line in `docker/Dockerfile`:

```dockerfile
RUN corepack disable && npm install -g yarn pnpm @anthropic-ai/claude-code
```

Replace it with:

```dockerfile
RUN corepack disable && npm install -g yarn pnpm @anthropic-ai/claude-code @fission-ai/openspec@latest
```

- [ ] **Step 2: Commit the Dockerfile change**

```bash
git add docker/Dockerfile
git commit -m "feat: install openspec globally in Docker image"
```

---

## Task 4: Update `entrypoint.sh` to support the `AGENT` env var

**Files:**
- Modify: `docker/entrypoint.sh`

- [ ] **Step 1: Replace the full contents of `docker/entrypoint.sh`**

```bash
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
```

- [ ] **Step 2: Commit**

```bash
git add docker/entrypoint.sh
git commit -m "feat: parameterise entrypoint binary via AGENT env var"
```

---

## Task 5: Update `scripts/claude-jail` — flag parsing, AGENT passthrough, help text

**Files:**
- Modify: `scripts/claude-jail`

- [ ] **Step 1: Add `AGENT` variable and `--openspec` case to the arg-parsing loop**

Find the arg-parsing block (starts with `AUTH_MODE="local"`):

```bash
  AUTH_MODE="local"
  CLAUDE_ARGS=()
  for arg in "$@"; do
    case "$arg" in
      --fresh|--local|--persist) AUTH_MODE="${arg#--}" ;;
      *) CLAUDE_ARGS+=("$arg") ;;
    esac
  done
```

Replace it with:

```bash
  AUTH_MODE="local"
  AGENT="claude"
  CLAUDE_ARGS=()
  for arg in "$@"; do
    case "$arg" in
      --fresh|--local|--persist) AUTH_MODE="${arg#--}" ;;
      --openspec) AGENT="openspec" ;;
      *) CLAUDE_ARGS+=("$arg") ;;
    esac
  done
```

- [ ] **Step 2: Add `-e "AGENT=$AGENT"` to the `docker run` call**

Find the `exec docker run` block at the bottom of `main()`:

```bash
  exec docker run -it --rm \
    --security-opt no-new-privileges \
    "${VOLUMES[@]}" \
    -e "AUTH_MODE=$AUTH_MODE" \
    -w /workspace \
    "$DOCKER_IMAGE" \
    "${CLAUDE_ARGS[@]+"${CLAUDE_ARGS[@]}"}"
```

Replace it with:

```bash
  exec docker run -it --rm \
    --security-opt no-new-privileges \
    "${VOLUMES[@]}" \
    -e "AUTH_MODE=$AUTH_MODE" \
    -e "AGENT=$AGENT" \
    -w /workspace \
    "$DOCKER_IMAGE" \
    "${CLAUDE_ARGS[@]+"${CLAUDE_ARGS[@]}"}"
```

- [ ] **Step 3: Add `--openspec` to the help text in `cmd_help()`**

Find the `AUTH MODES` section in `cmd_help()`:

```
AUTH MODES
  (default / --local)   Mount ~/.claude from host. Uses your existing login.
  --fresh               No credentials mounted. Login required every run.
  --persist             Credentials stored in $PWD/.claude-jail/. Persists across runs.
                        Add .claude-jail/ to .gitignore to avoid committing credentials.
```

Replace it with:

```
AUTH MODES
  (default / --local)   Mount ~/.claude from host. Uses your existing login.
  --fresh               No credentials mounted. Login required every run.
  --persist             Credentials stored in $PWD/.claude-jail/. Persists across runs.
                        Add .claude-jail/ to .gitignore to avoid committing credentials.

AGENT
  (default)             Run Claude Code (claude).
  --openspec            Run OpenSpec (openspec) instead of Claude Code.
                        Combinable with any auth mode flag.
```

Find the `EXAMPLES` section and add two new lines after the existing examples:

```
  claude-jail                     Start a session using your host Claude login
  claude-jail --fresh             Start a fresh session (login each time)
  claude-jail --persist           Start a session with per-project credentials
  claude-jail -p "explain main"   Run a one-shot prompt
  claude-jail --openspec init     Initialize OpenSpec in the current project
  claude-jail --openspec --fresh  Run OpenSpec with a fresh session
  claude-jail --help              Show this message
```

- [ ] **Step 4: Commit**

```bash
git add scripts/claude-jail
git commit -m "feat: add --openspec flag to run openspec instead of claude"
```

---

## Task 6: Run the tests to verify everything passes

- [ ] **Step 1: Build the Docker image locally**

```bash
docker compose -f docker/docker-compose.yml build
```

Expected: Build completes with no errors. `@fission-ai/openspec@latest` should appear in the npm install output.

- [ ] **Step 2: Run the targeted openspec tests**

`docker compose build` tags the image as `oakblu/claude-jail:latest` (matching the `image:` field in `docker-compose.yml`), so no `CLAUDE_JAIL_IMAGE` override is needed:

```bash
bash examples/test_06_openspec_flag.sh
```

Expected: all 3 tests pass.

- [ ] **Step 3: Run test_01 to verify openspec is in the image**

```bash
bash examples/test_01_software.sh
```

Expected: `[PASS] openspec exists at: /usr/local/bin/openspec` (path may vary).

---

## Task 7: Register the new test in `run_all_tests.sh`

**Files:**
- Modify: `examples/run_all_tests.sh`

- [ ] **Step 1: Add `test_06_openspec_flag.sh` to the test list**

Find the `TESTS` array:

```bash
TESTS=(
  test_01_software.sh
  test_02_isolation.sh
  test_03_workdir.sh
  test_04_auth_modes.sh
  test_05_multi_instance.sh
)
```

Replace it with:

```bash
TESTS=(
  test_01_software.sh
  test_02_isolation.sh
  test_03_workdir.sh
  test_04_auth_modes.sh
  test_05_multi_instance.sh
  test_06_openspec_flag.sh
)
```

- [ ] **Step 2: Run the full test suite**

```bash
bash examples/run_all_tests.sh
```

Expected: 6 test scripts, all passing. (Note: tests that invoke `claude` interactively will still pass since they test the binary's presence, not an interactive session.)

- [ ] **Step 3: Commit**

```bash
git add examples/run_all_tests.sh examples/test_06_openspec_flag.sh examples/test_01_software.sh
git commit -m "test: add test_06 for --openspec flag and openspec binary"
```

---

## Task 8: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add `--openspec` row to the auth modes table**

Find the auth modes table:

```markdown
| Flag | Behavior |
|---|---|
| *(default / `--local`)* | Mounts `~/.claude` from your host. Uses your existing login. |
| `--fresh` | No credentials mounted. Claude prompts for login every run. |
| `--persist` | Credentials stored in `./.claude-jail/` in the current project. Login once per project. |
```

Replace it with:

```markdown
| Flag | Behavior |
|---|---|
| *(default / `--local`)* | Mounts `~/.claude` from your host. Uses your existing login. |
| `--fresh` | No credentials mounted. Claude prompts for login every run. |
| `--persist` | Credentials stored in `./.claude-jail/` in the current project. Login once per project. |
| `--openspec` | Runs [OpenSpec](https://github.com/Fission-AI/OpenSpec) instead of Claude Code. Combinable with any auth mode flag. |
```

- [ ] **Step 2: Add openspec examples to the usage block**

Find the usage examples block:

```bash
claude-jail                  # use your host login (default)
claude-jail --fresh          # fresh session, no credentials
claude-jail --persist        # per-project credentials
```

Replace it with:

```bash
claude-jail                        # use your host login (default)
claude-jail --fresh                # fresh session, no credentials
claude-jail --persist              # per-project credentials
claude-jail --openspec init        # initialize OpenSpec in the current project
claude-jail --openspec --fresh     # run OpenSpec with a fresh session
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document --openspec flag in README"
```

---

## Self-Review Checklist

After implementation, verify:

- [ ] `bash scripts/claude-jail --help | grep openspec` prints the flag documentation
- [ ] `bash examples/run_all_tests.sh` with the local image shows 6 passed, 0 failed
- [ ] `bash examples/security-tests/test-isolation.sh` still shows 11 passed, 2 warnings, 0 failures
- [ ] `claude-jail --openspec --fresh` and `claude-jail --openspec --persist` both correctly combine flags (check by inspecting the docker run command with `echo` before exec, or by adding a dry-run debug mode temporarily)
