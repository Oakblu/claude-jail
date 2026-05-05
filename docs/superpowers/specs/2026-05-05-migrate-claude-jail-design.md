# Migration: claude-jail → claude-jail-2

**Date:** 2026-05-05
**Status:** Approved

## Goal

Bring the superior Docker setup, auth modes, and test suite from `claude-jail` into `claude-jail-2` (the git repo with CI/CD, Homebrew tap, and standalone CLI) — without replacing `claude-jail-2`'s distribution infrastructure. The result is one unified, production-quality project.

## Background

`claude-jail` (non-git local directory) has:
- `node:lts-slim` Dockerfile with rust, bun, yarn, pnpm, non-root user (`claude`, UID 1000), and `entrypoint.sh`
- Three auth modes (fresh/local/persist) implemented via docker-compose overlays
- Five test scripts covering software, isolation, workdir, auth modes, and multi-instance behavior

`claude-jail-2` (git repo) has:
- Homebrew tap, GitHub Actions CI/CD, package.json, logos
- Standalone CLI script (`scripts/claude-jail`) with `--install`/`--uninstall`/`--help`/`--version`
- A comprehensive 7-point security test suite
- A minimal Dockerfile (Alpine, runs as root, no rust/bun/yarn)

The three-compose-file auth mode overlay from `claude-jail` is **dropped**. Auth mode selection moves entirely into the standalone CLI.

## Architecture

### Approach: Atomic migration

All changes land in a single commit. The Dockerfile and CLI changes are coupled — switching from root to non-root user changes all mount paths (`/root/.claude` → `/home/claude/.claude`), so they cannot be split without creating a broken intermediate state.

### Files changed

| File | Action |
|---|---|
| `docker/Dockerfile` | Replace with `node:lts-slim` version |
| `docker/entrypoint.sh` | Create — handles per-mode setup, exec's `claude "$@"` |
| `docker/docker-compose.yml` | Update mount paths to `/home/claude/.claude` |
| `scripts/claude-jail` | Extend with `--fresh`/`--local`/`--persist` auth modes |
| `examples/run_all_tests.sh` | Create — runs test_01 through test_05 |
| `examples/test_01_software.sh` | Create — verifies all tools installed |
| `examples/test_02_isolation.sh` | Create — verifies filesystem isolation |
| `examples/test_03_workdir.sh` | Create — verifies bidirectional /workspace mount |
| `examples/test_04_auth_modes.sh` | Create — verifies all three auth modes |
| `examples/test_05_multi_instance.sh` | Create — verifies concurrent containers don't share state |
| `README.md` | Update: auth modes table, structure section, remove "runs as root" limitation |
| `CLAUDE.md` | Update: Dockerfile description, mount paths, key commands |

## Component Design

### docker/Dockerfile

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

### docker/entrypoint.sh

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

### scripts/claude-jail — auth mode extension

Three new flags parsed before the `check_docker_*` calls:

```
--local    Mount ~/.claude + ~/.claude.json from host. Uses existing login. (CLI default — preserves current behavior)
--fresh    No credentials mounted. Claude prompts for login every run.
--persist  Mount $PWD/.claude-jail/ as credentials dir. Created if absent.
```

> Note: `entrypoint.sh` defaults `AUTH_MODE` to `fresh` for direct `docker run` invocations that omit `-e AUTH_MODE`. The CLI always passes `-e AUTH_MODE=$AUTH_MODE`, so the entrypoint default is never reached in normal use.

Argument parsing:

```bash
AUTH_MODE="local"

for arg in "$@"; do
  case "$arg" in
    --fresh)   AUTH_MODE="fresh";   set -- "${@/$arg}"; break ;;
    --local)   AUTH_MODE="local";   set -- "${@/$arg}"; break ;;
    --persist) AUTH_MODE="persist"; set -- "${@/$arg}"; break ;;
  esac
done
```

Volume selection replacing the hardcoded `-v` flags:

```bash
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
  "$@"
```

Note: `claude "$@"` is removed from the `docker run` invocation — the `ENTRYPOINT` handles it.

The `cmd_help()` text gets a new **Auth modes** section:

```
AUTH MODES
  (default / --local)   Mount ~/.claude from host. Uses your existing login.
  --fresh               No credentials mounted. Login required every run.
  --persist             Credentials stored in $PWD/.claude-jail/. Persists across runs.
```

### examples/ — test structure

```
examples/
  run_all_tests.sh           runs test_01 through test_05
  test_01_software.sh        node, npm, yarn, pnpm, bun, cargo, rustc, python3, claude
  test_02_isolation.sh       host paths unreachable, path traversal stays in container
  test_03_workdir.sh         bidirectional read/write through /workspace
  test_04_auth_modes.sh      fresh/local/persist mount behavior
  test_05_multi_instance.sh  concurrent containers see only their own workdir
  security-tests/
    test-isolation.sh        existing 7-point deep security check (unchanged)
  README.md                  existing (unchanged)
```

All new test files use `docker run` directly (no compose). All respect `CLAUDE_JAIL_IMAGE` env var. All already reference `/home/claude/.claude` paths — no adaptation needed.

### docker/docker-compose.yml

Mount paths updated to match non-root user. Used only for "build from source" contributors:

```yaml
volumes:
  - ${WORKSPACE_PATH:-.}:/workspace
  - ${HOME}/.claude:/home/claude/.claude
  - ${HOME}/.claude.json:/home/claude/.claude.json
```

## Error Handling

- `--persist` mode: `mkdir -p "$(pwd)/.claude-jail"` in the CLI ensures the dir exists before mounting
- `--local` with missing `~/.claude.json`: Docker will error naturally; no special handling needed
- Unknown flags: passed through to `claude` inside the container unchanged

## Testing

Two independent test suites coexist:

1. `bash examples/run_all_tests.sh` — functional tests (software, isolation, workdir, auth, multi-instance)
2. `bash examples/security-tests/test-isolation.sh` — deep security property verification

Both can be run against a custom image: `CLAUDE_JAIL_IMAGE=my-image bash examples/run_all_tests.sh`

## What is explicitly NOT changing

- Homebrew tap (`homebrew-tap/`)
- GitHub Actions CI/CD (`.github/workflows/docker-publish.yml`)
- `package.json`
- Logos (`logo.png`, `logo.svg`)
- `.gitignore`
- `examples/security-tests/test-isolation.sh`
- `examples/README.md`
- `scripts/claude-jail` install/uninstall/help/version commands
