# claude-jail

Run [Claude Code](https://claude.ai/code) inside a Docker container so it can only touch the project you hand it — nothing else on your machine.

## Quick start — Homebrew (recommended)

```bash
brew install oakblu/claude-jail/claude-jail
```

That's it. The installer checks for Docker, adds `claude-jail` to your PATH, and sets up your shell automatically.

---

## Quick start — no clone needed

The image is published to Docker Hub as [`oakblu/claude-jail`](https://hub.docker.com/r/oakblu/claude-jail). You only need Docker installed.

**Step 1 — log in to Claude Code once on your host** (skip if you already have `~/.claude/` with credentials):

```bash
npm install -g @anthropic-ai/claude-code
claude   # follow the login flow; credentials are saved to ~/.claude/
```

**Step 2 — add the shell function to your `~/.zshrc` (or `~/.bashrc`):**

```bash
# claude-jail: run Claude Code sandboxed via Docker Hub image
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

Reload your shell (`source ~/.zshrc`), then use it from any project:

```bash
cd ~/my-project
claude-jail                        # interactive session
claude-jail -p "explain this code" # one-shot print mode
```

> **Prefer `docker compose`?** Save this as `compose.yml` anywhere and run `WORKSPACE_PATH=/path/to/project docker compose run --rm claude-jail claude`:
>
> ```yaml
> services:
>   claude-jail:
>     image: oakblu/claude-jail:latest
>     stdin_open: true
>     tty: true
>     working_dir: /workspace
>     security_opt:
>       - no-new-privileges
>     volumes:
>       - ${WORKSPACE_PATH:-.}:/workspace
>       - ${HOME}/.claude:/home/claude/.claude
>       - ${HOME}/.claude.json:/home/claude/.claude.json
> ```

---

## What it is

Claude Code is a powerful AI coding assistant with access to your filesystem, shell, and editor. By default it runs as your user with full access to your home directory, dotfiles, SSH keys, and secrets. **claude-jail** wraps Claude Code in a Docker container and limits it to a single directory you choose.

## Who it is for

- Developers who want to use Claude Code on a project without giving it access to the rest of their system
- Teams that want to run Claude Code in CI or on shared machines with a predictable, auditable footprint
- Anyone curious about what Claude Code can actually reach on their disk

## How it works

The container mounts exactly three things from your host:

| Mount | Purpose |
|---|---|
| `WORKSPACE_PATH` → `/workspace` | The project you want Claude to work on |
| `~/.claude/` → `/home/claude/.claude/` | Claude credentials and configuration (--local mode) |
| `~/.claude.json` → `/home/claude/.claude.json` | Claude settings file (mounted if present, --local mode) |

Everything else on your host — `~/.ssh`, `~/.zshrc`, `~/.aws`, other projects — is invisible to the container.

## Build from source (contributors)

**Prerequisites:** Docker Desktop (Mac/Windows) or Docker Engine (Linux), Node.js.

**1. Clone and build:**

```bash
git clone https://github.com/pablohpsilva/claude-jail.git
cd claude-jail
docker compose -f docker/docker-compose.yml build
```

**2. Add the shell function pointing at your local clone:**

```bash
claude-jail() {
  WORKSPACE_PATH="$(pwd)" docker compose \
    -f "$HOME/path/to/claude-jail/docker/docker-compose.yml" \
    run --rm claude-jail claude "$@"
}
```

## Usage

Navigate to any project directory and run `claude-jail` the same way you would run `claude`:

```bash
cd ~/my-project
claude-jail                        # interactive session
claude-jail -p "explain this code" # one-shot print mode
claude-jail --help                 # show all Claude flags
```

## Auth modes

| Flag | Behavior |
|---|---|
| *(default / `--local`)* | Mounts `~/.claude` from your host machine. Uses your existing login. Token refreshes and preference changes persist back to the host. |
| `--fresh` | No config mounted. Claude prompts for login every run. Credentials never touch the host. |
| `--persist` | Mounts `./.claude-jail/` as the Claude config directory. Created on first run. Subsequent runs from the same directory skip the login prompt. |

**Tip:** When using `--persist`, add `.claude-jail/` to your `.gitignore`:

```bash
echo '.claude-jail/' >> .gitignore
```

Claude Code runs inside the container. It can read and write files in `~/my-project` but cannot see anything else on your host.

## Security tests

To verify the isolation is working correctly, run the test suite from the repo root:

```bash
bash examples/security-tests/test-isolation.sh
```

The script spins up a container and checks:

1. **Host filesystem visibility** — `/Users`, `/host`, and host home directories are not present inside the container
2. **Path traversal** — `../../` from `/workspace` or `/root/.claude` stays inside the container, not on your host
3. **Sensitive file access** — `~/.zshrc`, `~/.ssh`, `~/.aws/credentials` are unreachable from inside
4. **Workspace writes** — files written to `/workspace` appear on the host (expected, by design)
5. **Claude credentials** — `~/.claude/.credentials.json` is accessible (required for authentication)
6. **Privilege escalation** — `sudo` is absent and `no-new-privileges` is enforced
7. **Symlink safety** — scans for symlinks inside `~/.claude` that point outside the config directory

Expected output:

```
Results: 11 passed  0 failed  2 warnings
```

Warnings (not failures) are expected for:
- `/home` directory exists inside the container but is empty
- Default Docker capabilities are non-zero (no-new-privileges limits escalation but does not drop caps)
- Absolute symlinks inside `~/.claude/debug/` that point to a path that does not exist inside the container

## What the container can and cannot do

| Action | Possible? | Notes |
|---|---|---|
| Read/write files in `WORKSPACE_PATH` | Yes | This is the whole point |
| Read/write `~/.claude/` | Yes | Required for persistent login |
| Read `~/.ssh` | No | Not mounted |
| Read `~/.zshrc`, `~/.gitconfig`, etc. | No | Not mounted |
| Read `~/.aws/credentials` | No | Not mounted |
| Access other projects outside `WORKSPACE_PATH` | No | Not mounted |
| Access the internet | Yes | Docker default; restrict with `--network none` if needed |
| Escalate privileges | No | `no-new-privileges` security option is set |

## Directory structure

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

## Limitations

- **Network is unrestricted by default.** Claude Code needs internet access to call the Anthropic API, but the container has no other network restrictions. Add `network_mode: none` with a local proxy if you need full network isolation.
- **`~/.claude/` is read-write.** Claude needs to refresh its OAuth token and write session data. If you want to lock this down further, you can experiment with read-only mounts for the credentials file specifically.
