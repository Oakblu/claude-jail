# Migrate claude-jail → claude-jail-2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the superior Dockerfile, auth modes system, and test suite from `claude-jail` into `claude-jail-2` while keeping `claude-jail-2`'s standalone CLI, CI/CD, and Homebrew infrastructure intact.

**Architecture:** Replace the Alpine/root Dockerfile with `node:lts-slim` plus a non-root `claude` user, add an `entrypoint.sh` for per-mode container setup, extend the existing `scripts/claude-jail` CLI with `--fresh`/`--local`/`--persist` flags that pass different volume mounts, and bring over the five functional test scripts verbatim (they already use `docker run` and `/home/claude/.claude` paths).

**Tech Stack:** Bash, Docker, node:lts-slim, Rust toolchain, bun, yarn, pnpm, @anthropic-ai/claude-code

**Working directory:** `/Users/pablohpsilva/Documents/claude-jail-2`

---

## File Map

| File | Action | Reason |
|---|---|---|
| `docker/Dockerfile` | Replace | Switch to lts-slim, non-root user, rust/bun/yarn/pnpm, entrypoint |
| `docker/entrypoint.sh` | Create | Per-mode container setup before exec'ing claude |
| `docker/docker-compose.yml` | Modify | Update mount paths from `/root/.claude` → `/home/claude/.claude` |
| `scripts/claude-jail` | Modify | Add auth mode flags + update cmd_help + fix mount paths |
| `examples/run_all_tests.sh` | Create | Runs test_01 through test_05 sequentially |
| `examples/test_01_software.sh` | Create | Verifies all tools are installed in image |
| `examples/test_02_isolation.sh` | Create | Verifies host paths unreachable from container |
| `examples/test_03_workdir.sh` | Create | Verifies bidirectional /workspace mount |
| `examples/test_04_auth_modes.sh` | Create | Verifies fresh/local/persist volume behavior |
| `examples/test_05_multi_instance.sh` | Create | Verifies concurrent containers don't share state |
| `README.md` | Modify | Auth modes section, updated paths, updated structure |
| `CLAUDE.md` | Modify | Updated Dockerfile description, mount paths, key commands |

---

## Task 1: Replace Dockerfile and create entrypoint.sh

**Files:**
- Replace: `docker/Dockerfile`
- Create: `docker/entrypoint.sh`

- [ ] **Step 1: Replace docker/Dockerfile**

```dockerfile
FROM node:lts-slim

RUN apt-get update && apt-get install -y \
    python3 python3-pip curl git bash ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --default-toolchain stable --profile minimal \
    && chmod -R a+w /usr/local/rustup /usr/local/cargo \
    && rm -rf /usr/local/cargo/registry

ENV BUN_INSTALL=/usr/local/bun \
    PATH=/usr/local/bun/bin:$PATH

RUN curl -fsSL https://bun.sh/install | bash \
    && chmod -R a+rx /usr/local/bun

RUN npm install -g yarn pnpm @anthropic-ai/claude-code

RUN useradd -m -u 1000 -s /bin/bash claude \
    && mkdir -p /workspace && chown claude:claude /workspace

WORKDIR /workspace

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER claude

ENTRYPOINT ["/entrypoint.sh"]
```

- [ ] **Step 2: Create docker/entrypoint.sh**

```bash
#!/bin/bash
set -e

AUTH_MODE="${AUTH_MODE:-fresh}"

case "$AUTH_MODE" in
  persist)
    mkdir -p /home/claude/.claude
    ;;
  fresh|local)
    ;;
esac

exec claude "$@"
```

- [ ] **Step 3: Make entrypoint.sh executable**

```bash
chmod +x docker/entrypoint.sh
```

- [ ] **Step 4: Build the image to verify the Dockerfile compiles**

```bash
docker build -t oakblu/claude-jail:latest docker/
```

Expected: build completes successfully with no errors. Rust install takes 2-3 minutes.

- [ ] **Step 5: Smoke test — verify container runs as non-root user**

```bash
docker run --rm --entrypoint /bin/bash oakblu/claude-jail:latest -c "whoami"
```

Expected output:
```
claude
```

- [ ] **Step 6: Smoke test — verify entrypoint passes args correctly**

```bash
docker run --rm -e AUTH_MODE=fresh oakblu/claude-jail:latest --version 2>&1 | head -1
```

Expected: a Claude version string like `Claude Code 1.x.x` (not a bash error).

- [ ] **Step 7: Commit**

```bash
git add docker/Dockerfile docker/entrypoint.sh
git commit -m "Replace Dockerfile: lts-slim, non-root claude user, rust/bun/yarn, entrypoint"
```

---

## Task 2: Update docker/docker-compose.yml

**Files:**
- Modify: `docker/docker-compose.yml`

The compose file is used by contributors building from source. Mount paths must match the non-root user's home directory.

- [ ] **Step 1: Update docker/docker-compose.yml**

Replace the entire file with:

```yaml
services:
  claude-jail:
    image: oakblu/claude-jail:latest
    build:
      context: .
      dockerfile: Dockerfile
    volumes:
      - ${WORKSPACE_PATH:-.}:/workspace
      - ${HOME}/.claude:/home/claude/.claude
      - ${HOME}/.claude.json:/home/claude/.claude.json
    working_dir: /workspace
    security_opt:
      - no-new-privileges
    stdin_open: true
    tty: true
```

- [ ] **Step 2: Verify compose config parses correctly**

```bash
docker compose -f docker/docker-compose.yml config
```

Expected: YAML output with `/home/claude/.claude` mount paths (not `/root/.claude`).

- [ ] **Step 3: Commit**

```bash
git add docker/docker-compose.yml
git commit -m "Update docker-compose.yml mount paths for non-root claude user"
```

---

## Task 3: Create test files

**Files:**
- Create: `examples/run_all_tests.sh`
- Create: `examples/test_01_software.sh`
- Create: `examples/test_02_isolation.sh`
- Create: `examples/test_03_workdir.sh`
- Create: `examples/test_04_auth_modes.sh`
- Create: `examples/test_05_multi_instance.sh`

These files are ported from `claude-jail` unchanged — they already use `docker run` directly and reference `/home/claude/.claude` paths.

- [ ] **Step 1: Create examples/run_all_tests.sh**

```bash
#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

TESTS=(
  test_01_software.sh
  test_02_isolation.sh
  test_03_workdir.sh
  test_04_auth_modes.sh
  test_05_multi_instance.sh
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
```

- [ ] **Step 2: Create examples/test_01_software.sh**

```bash
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

check_version "node"
check_version "npm"
check_version "yarn"
check_version "pnpm"
check_version "bun"
check_version "cargo"
check_version "rustc"
check_version "python3"
check_exists  "claude"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
```

- [ ] **Step 3: Create examples/test_02_isolation.sh**

```bash
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
```

- [ ] **Step 4: Create examples/test_03_workdir.sh**

```bash
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
```

- [ ] **Step 5: Create examples/test_04_auth_modes.sh**

```bash
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
```

- [ ] **Step 6: Create examples/test_05_multi_instance.sh**

```bash
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
```

- [ ] **Step 7: Make all test files executable**

```bash
chmod +x examples/run_all_tests.sh \
         examples/test_01_software.sh \
         examples/test_02_isolation.sh \
         examples/test_03_workdir.sh \
         examples/test_04_auth_modes.sh \
         examples/test_05_multi_instance.sh
```

- [ ] **Step 8: Commit**

```bash
git add examples/run_all_tests.sh \
        examples/test_01_software.sh \
        examples/test_02_isolation.sh \
        examples/test_03_workdir.sh \
        examples/test_04_auth_modes.sh \
        examples/test_05_multi_instance.sh
git commit -m "Add functional test suite: software, isolation, workdir, auth modes, multi-instance"
```

---

## Task 4: Verify image with test_01

**Files:** none changed — this task only runs tests.

- [ ] **Step 1: Run test_01 to verify all tools installed**

```bash
bash examples/test_01_software.sh
```

Expected output (9 passed, 0 failed):
```
=== test_01_software: Verifying installed tools ===
[PASS] node: v22.x.x
[PASS] npm: 10.x.x
[PASS] yarn: 1.x.x
[PASS] pnpm: 10.x.x
[PASS] bun: 1.x.x
[PASS] cargo: cargo 1.x.x
[PASS] rustc: rustc 1.x.x
[PASS] python3: Python 3.x.x
[PASS] claude exists at: /usr/local/...

Results: 9 passed, 0 failed
```

If any tool fails, the Dockerfile step is broken — go back to Task 1 and fix the failing install layer before continuing.

---

## Task 5: Extend scripts/claude-jail with auth modes

**Files:**
- Modify: `scripts/claude-jail`

Two changes: (1) replace `cmd_help` body with auth-mode-aware version, (2) replace `main()` body with auth mode parsing and per-mode volume selection.

- [ ] **Step 1: Replace cmd_help in scripts/claude-jail**

Find the existing `cmd_help()` function (it starts with `cmd_help() {` and ends before `cmd_version()`). Replace the entire function body with:

```bash
cmd_help() {
  cat <<'EOF'
claude-jail — Run Claude Code inside an isolated Docker sandbox

USAGE
  claude-jail [AUTH MODE] [CLAUDE ARGS...]
  claude-jail [OPTIONS]

AUTH MODES
  (default / --local)   Mount ~/.claude from host. Uses your existing login.
  --fresh               No credentials mounted. Login required every run.
  --persist             Credentials stored in $PWD/.claude-jail/. Persists across runs.
                        Add .claude-jail/ to .gitignore to avoid committing credentials.

OPTIONS
  -h, --help        Show this help message and exit
  --install         Add claude-jail to your shell PATH (auto-detected RC file)
  --uninstall       Remove the shell PATH entry added by --install
  --version         Print version information and exit

DESCRIPTION
  claude-jail launches Claude Code in a Docker container with access only to
  the current directory. The rest of your host filesystem is not visible
  inside the container.

  Mounts (container path ← host path):
    /workspace                ← $(pwd)
    /home/claude/.claude      ← ~/.claude          (--local mode, default)
    /home/claude/.claude      ← $PWD/.claude-jail/ (--persist mode)

  Security:
    • Runs as non-root user (claude, UID 1000)
    • no-new-privileges enforced — container cannot escalate permissions
    • No SSH keys, AWS credentials, or other projects are accessible

EXAMPLES
  claude-jail                     Start a session using your host Claude login
  claude-jail --fresh             Start a fresh session (login each time)
  claude-jail --persist           Start a session with per-project credentials
  claude-jail -p "explain main"   Run a one-shot prompt
  claude-jail --help              Show this message

REQUIREMENTS
  Docker must be installed and the Docker daemon must be running.

  Install options:
    • Docker Desktop  https://www.docker.com/products/docker-desktop
    • OrbStack        https://orbstack.dev
    • Colima          brew install colima && colima start

MORE
  https://github.com/oakblu/claude-jail
EOF
}
```

- [ ] **Step 2: Replace main() in scripts/claude-jail**

Find the existing `main()` function (starts with `main() {`). Replace the entire function with:

```bash
main() {
  case "${1:-}" in
    -h|--help)
      cmd_help
      exit 0
      ;;
    --install)
      cmd_install "${2:-}"
      exit 0
      ;;
    --uninstall)
      cmd_uninstall
      exit 0
      ;;
    --version)
      cmd_version
      exit 0
      ;;
  esac

  AUTH_MODE="local"
  CLAUDE_ARGS=()
  for arg in "$@"; do
    case "$arg" in
      --fresh|--local|--persist) AUTH_MODE="${arg#--}" ;;
      *) CLAUDE_ARGS+=("$arg") ;;
    esac
  done

  check_docker_installed
  check_docker_running

  VOLUMES=(-v "$(pwd):/workspace")

  case "$AUTH_MODE" in
    local)
      VOLUMES+=(-v "$HOME/.claude:/home/claude/.claude")
      VOLUMES+=(-v "$HOME/.claude.json:/home/claude/.claude.json")
      ;;
    persist)
      mkdir -p "$(pwd)/.claude-jail"
      VOLUMES+=(-v "$(pwd)/.claude-jail:/home/claude/.claude")
      ;;
    fresh)
      ;;
  esac

  exec docker run -it --rm \
    --security-opt no-new-privileges \
    "${VOLUMES[@]}" \
    -e "AUTH_MODE=$AUTH_MODE" \
    -w /workspace \
    "$DOCKER_IMAGE" \
    "${CLAUDE_ARGS[@]+"${CLAUDE_ARGS[@]}"}"
}
```

- [ ] **Step 3: Verify the script parses correctly (no syntax errors)**

```bash
bash -n scripts/claude-jail
```

Expected: no output (syntax is valid).

- [ ] **Step 4: Verify --help shows auth modes**

```bash
scripts/claude-jail --help
```

Expected: help text containing "AUTH MODES" section with `--fresh`, `--local`, `--persist` entries.

- [ ] **Step 5: Commit**

```bash
git add scripts/claude-jail
git commit -m "Extend claude-jail CLI with --fresh/--local/--persist auth modes"
```

---

## Task 6: Verify auth modes with test_04

**Files:** none changed — this task only runs tests.

- [ ] **Step 1: Run test_04 to verify all three auth modes**

```bash
bash examples/test_04_auth_modes.sh
```

Expected output (5 passed, 0 failed):
```
=== test_04_auth_modes: Verifying authentication modes ===
[PASS] fresh mode: /home/claude/.claude does not exist
[PASS] local mode: host Claude config dir is accessible inside the container
[PASS] persist mode: file written inside container is visible in .claude-jail/ on host
[PASS] persist mode: persisted content is correct
[PASS] fresh mode does not inherit config from previous local mode run

Results: 5 passed, 0 failed
```

If `fresh mode: /home/claude/.claude unexpectedly exists`, the `entrypoint.sh` `persist` case is creating the directory unconditionally — verify `AUTH_MODE` env var is being passed and the case statement is correct.

---

## Task 7: Run full test suite

**Files:** none changed — this task only runs tests.

- [ ] **Step 1: Run the full test suite**

```bash
bash examples/run_all_tests.sh
```

Expected: all 5 test scripts report 0 failures. Final output:
```
════════════════════════════════════════
Results: 5 passed, 0 failed
════════════════════════════════════════
```

If any test fails, fix the root cause before continuing to the docs tasks.

- [ ] **Step 2: Run the deep security test**

```bash
bash examples/security-tests/test-isolation.sh
```

Expected: `Results: 10 passed  0 failed  3 warnings` (the 3 warnings for `/home`, capabilities, and symlinks are expected and documented).

---

## Task 8: Update README.md

**Files:**
- Modify: `README.md`

Four targeted edits — no restructuring.

- [ ] **Step 1: Update the manual shell function (Quick start section)**

Find:
```bash
claude-jail() {
  docker run -it --rm \
    --security-opt no-new-privileges \
    -v "$(pwd):/workspace" \
    -v "$HOME/.claude:/root/.claude" \
    -v "$HOME/.claude.json:/root/.claude.json" \
    -w /workspace \
    oakblu/claude-jail:latest \
    claude "$@"
}
```

Replace with:
```bash
claude-jail() {
  docker run -it --rm \
    --security-opt no-new-privileges \
    -v "$(pwd):/workspace" \
    -v "$HOME/.claude:/home/claude/.claude" \
    -v "$HOME/.claude.json:/home/claude/.claude.json" \
    -e AUTH_MODE=local \
    -w /workspace \
    oakblu/claude-jail:latest \
    "$@"
}
```

- [ ] **Step 2: Update the docker compose snippet in Quick start**

Find:
```yaml
    volumes:
      - ${WORKSPACE_PATH:-.}:/workspace
      - ${HOME}/.claude:/root/.claude
      - ${HOME}/.claude.json:/root/.claude.json
```

Replace with:
```yaml
    volumes:
      - ${WORKSPACE_PATH:-.}:/workspace
      - ${HOME}/.claude:/home/claude/.claude
      - ${HOME}/.claude.json:/home/claude/.claude.json
```

- [ ] **Step 3: Update the "How it works" mount table**

Find:
```
| `~/.claude/` → `/root/.claude/` | Claude credentials and configuration (persistent login) |
| `~/.claude.json` → `/root/.claude.json` | Claude main settings file |
```

Replace with:
```
| `~/.claude/` → `/home/claude/.claude/` | Claude credentials and configuration (persistent login, --local mode) |
| `~/.claude.json` → `/home/claude/.claude.json` | Claude main settings file |
```

- [ ] **Step 4: Add auth modes section after the "Usage" section**

After the Usage section (which ends with `claude-jail --help                 # show all Claude flags`), insert the following block verbatim as the next `##` section:

~~~~
## Auth modes

| Flag | Behavior |
|---|---|
| *(default / `--local`)* | Mounts `~/.claude` from your host machine. Uses your existing login. Token refreshes and preference changes persist back to the host. |
| `--fresh` | No config mounted. Claude prompts for login every run. Credentials never touch the host. |
| `--persist` | Mounts `$PWD/.claude-jail/` as the Claude config directory. Created on first run. Subsequent runs from the same directory skip the login prompt. |

**Tip:** When using `--persist`, add `.claude-jail/` to your `.gitignore`:

```bash
echo '.claude-jail/' >> .gitignore
```
~~~~

- [ ] **Step 5: Update the Directory structure section**

Find:
```
claude-jail/
├── docker/
│   ├── Dockerfile            # node:latest + claude-code global install
│   └── docker-compose.yml    # volume mounts and security settings
├── examples/
│   ├── security-tests/
│   │   └── test-isolation.sh # automated isolation test suite
│   └── README.md
└── README.md
```

Replace with:
```
claude-jail/
├── docker/
│   ├── Dockerfile            # node:lts-slim, non-root claude user, rust/bun/yarn/pnpm
│   ├── entrypoint.sh         # per-mode container setup, exec's claude
│   └── docker-compose.yml    # volume mounts and security settings (build-from-source)
├── examples/
│   ├── run_all_tests.sh      # runs test_01 through test_05
│   ├── test_01_software.sh   # all tools installed
│   ├── test_02_isolation.sh  # host filesystem not accessible
│   ├── test_03_workdir.sh    # bidirectional /workspace mount
│   ├── test_04_auth_modes.sh # fresh/local/persist modes work
│   ├── test_05_multi_instance.sh # concurrent containers are independent
│   ├── security-tests/
│   │   └── test-isolation.sh # deep 7-point security property verification
│   └── README.md
└── README.md
```

- [ ] **Step 6: Remove the "Runs as root" limitation**

Find and delete this bullet from the Limitations section:
```
- **Runs as root inside the container.** The container user is root (node:latest default). This is standard for development containers but means if something escapes the container, it has root in that context.
```

- [ ] **Step 7: Commit**

```bash
git add README.md
git commit -m "Update README: auth modes, non-root user paths, updated structure"
```

---

## Task 9: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update the Dockerfile description**

Find:
```
- **`docker/Dockerfile`** — Minimal Node.js image with `@anthropic-ai/claude-code` installed globally.
```

Replace with:
```
- **`docker/Dockerfile`** — `node:lts-slim` image with `@anthropic-ai/claude-code`, yarn, pnpm, bun, and Rust installed globally. Runs as non-root user `claude` (UID 1000). Uses `entrypoint.sh` for per-mode container setup.
- **`docker/entrypoint.sh`** — Reads `AUTH_MODE` env var, creates `/home/claude/.claude` if persist mode, then `exec claude "$@"`.
```

- [ ] **Step 2: Update mount paths in the Architecture section**

Find:
```
  - `${HOME}/.claude:/root/.claude` — credentials and persistent Claude state
  - `${HOME}/.claude.json:/root/.claude.json` — Claude settings
```

Replace with:
```
  - `${HOME}/.claude:/home/claude/.claude` — credentials and persistent Claude state (--local mode)
  - `${HOME}/.claude.json:/home/claude/.claude.json` — Claude settings
```

- [ ] **Step 3: Update Key Commands to include both test runners**

Find this block in CLAUDE.md (under "Key Commands"):

~~~~
**Run isolation tests:**
```bash
bash examples/security-tests/test-isolation.sh
```
Expected: 10 passes, 3 warnings (no failures).
~~~~

Replace it with:

~~~~
**Run functional tests:**
```bash
bash examples/run_all_tests.sh
```
Expected: 5 test scripts, all passing.

**Run deep security tests:**
```bash
bash examples/security-tests/test-isolation.sh
```
Expected: 10 passes, 3 warnings (no failures).
~~~~

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "Update CLAUDE.md: Dockerfile description, mount paths, key commands"
```

---

## Task 10: Final verification

- [ ] **Step 1: Run the full functional test suite one more time**

```bash
bash examples/run_all_tests.sh
```

Expected: `Results: 5 passed, 0 failed`

- [ ] **Step 2: Run the security test**

```bash
bash examples/security-tests/test-isolation.sh
```

Expected: `Results: 10 passed  0 failed  3 warnings`

- [ ] **Step 3: Verify git log shows clean commit history**

```bash
git log --oneline -8
```

Expected — 5 new commits on top of the existing history:
```
<hash> Update CLAUDE.md: Dockerfile description, mount paths, key commands
<hash> Update README: auth modes, non-root user paths, updated structure
<hash> Extend claude-jail CLI with --fresh/--local/--persist auth modes
<hash> Add functional test suite: software, isolation, workdir, auth modes, multi-instance
<hash> Update docker-compose.yml mount paths for non-root claude user
<hash> Replace Dockerfile: lts-slim, non-root claude user, rust/bun/yarn, entrypoint
<hash> Add migration design spec: claude-jail → claude-jail-2
<hash> ... (existing history)
```

- [ ] **Step 4: Verify --help output one final time**

```bash
scripts/claude-jail --help
```

Confirm AUTH MODES section is present with all three modes documented.
