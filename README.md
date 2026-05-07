# claude-jail

Run [Claude Code](https://claude.ai/code) inside a Docker sandbox — it can only touch the project you point it at.

## Install

```bash
brew install oakblu/claude-jail/claude-jail
```

Requires Docker to be installed and running ([Docker Desktop](https://www.docker.com/products/docker-desktop), [OrbStack](https://orbstack.dev), or `brew install colima && colima start`).

## Use

```bash
cd ~/my-project
claude-jail          # start a session
```

That's it. Claude Code runs inside a container with access only to the current directory.

## Auth modes

By default, `claude-jail` mounts your host credentials so you don't need to log in each time. You can change this with a flag:

| Flag | Behavior |
|---|---|
| *(default / `--local`)* | Mounts `~/.claude` from your host. Uses your existing login. |
| `--fresh` | No credentials mounted. Claude prompts for login every run. |
| `--persist` | Credentials stored in `./.claude-jail/` in the current project. Login once per project. |
| `--openspec` | Runs [OpenSpec](https://github.com/Fission-AI/OpenSpec) instead of Claude Code. Combinable with any auth mode flag. OpenSpec calls Claude internally, so credentials are still required. |

```bash
claude-jail                        # use your host login (default)
claude-jail --fresh                # fresh session, no credentials
claude-jail --persist              # per-project credentials
claude-jail --openspec init        # initialize OpenSpec in the current project
claude-jail --openspec --fresh     # run OpenSpec with a fresh session
```

**Tip:** When using `--persist`, add `.claude-jail/` to your `.gitignore`:

```bash
echo '.claude-jail/' >> .gitignore
```

You can also pass any Claude Code flags through:

```bash
claude-jail -p "explain this code"
claude-jail --help
```

---

## What it is

Claude Code is a powerful AI coding assistant with access to your filesystem, shell, and editor. By default it runs as your user with full access to your home directory, dotfiles, SSH keys, and secrets.

**claude-jail** wraps it in a Docker container and limits it to a single directory you choose. The rest of your machine is invisible to it.

## Who it is for

- Developers who want to use Claude Code on a project without giving it access to their whole system
- Teams running Claude Code in CI or on shared machines
- Anyone who wants a predictable, auditable boundary around what Claude can reach

---

## How it works

The container mounts only what Claude needs:

| Host path | Container path | When |
|---|---|---|
| `$(pwd)` | `/workspace` | always |
| `~/.claude/` | `/home/claude/.claude/` | `--local` (default) |
| `~/.claude.json` | `/home/claude/.claude.json` | `--local`, if present |
| `./.claude-jail/` | `/home/claude/.claude/` | `--persist` |

Everything else — `~/.ssh`, `~/.aws`, other projects, your dotfiles — is not mounted and not visible.

The container runs as a non-root user (`claude`, UID 1000) with `no-new-privileges` enforced.

## What it can and cannot do

| Action | Possible? |
|---|---|
| Read/write files in the current directory | Yes |
| Read/write `~/.claude/` | Yes (required for login) |
| Read `~/.ssh`, `~/.aws`, `~/.zshrc`, etc. | No |
| Access other projects | No |
| Access the internet | Yes (Claude needs the Anthropic API) |
| Escalate privileges | No |

---

## Without Homebrew

If you prefer not to use Homebrew, you can add a shell function directly to your `~/.zshrc` or `~/.bashrc`:

```bash
claude-jail() {
  local auth_mode="local"
  local agent="claude"
  local volumes=(-v "$(pwd):/workspace")
  local args=()

  for arg in "$@"; do
    case "$arg" in
      --fresh)   auth_mode="fresh" ;;
      --persist) auth_mode="persist"
                 mkdir -p "$(pwd)/.claude-jail"
                 volumes+=(-v "$(pwd)/.claude-jail:/home/claude/.claude:rw") ;;
      --openspec) agent="openspec" ;;
      *)         args+=("$arg") ;;
    esac
  done

  if [[ "$auth_mode" == "local" ]]; then
    volumes+=(-v "$HOME/.claude:/home/claude/.claude:rw")
    [[ -f "$HOME/.claude.json" ]] && volumes+=(-v "$HOME/.claude.json:/home/claude/.claude.json:rw")
  fi

  docker run -it --rm \
    --security-opt no-new-privileges \
    "${volumes[@]}" \
    -e "AUTH_MODE=$auth_mode" \
    -e "AGENT=$agent" \
    -w /workspace \
    oakblu/claude-jail:latest \
    "${args[@]+"${args[@]}"}"
}
```

Reload your shell (`source ~/.zshrc`) and use it the same way.

---

## Build from source

```bash
git clone https://github.com/oakblu/claude-jail.git
cd claude-jail
docker compose -f docker/docker-compose.yml build
```

Then run tests:

```bash
bash examples/run_all_tests.sh        # functional tests
bash examples/security-tests/test-isolation.sh  # isolation verification
```

Expected: 6 test scripts all passing, and `11 passed  2 warnings` for the security test.
