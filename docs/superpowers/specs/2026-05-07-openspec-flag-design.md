# OpenSpec flag for claude-jail

**Date:** 2026-05-07
**Status:** Approved

## Summary

Add `--openspec` flag to `claude-jail` that runs `openspec` as the container's main process instead of `claude`. OpenSpec is a spec-driven workflow framework that uses Claude (or other LLMs) under the hood. This gives users the ability to choose which agent to run inside the sandbox.

## Context

`claude-jail` currently hardcodes `claude` as the container binary. The entrypoint receives `AUTH_MODE` via env var and branches on it, then always ends with `exec claude "$@"`. Adding a second binary requires parameterizing that final exec.

OpenSpec (`@fission-ai/openspec`) is installed globally in the image and uses Claude under the hood, so it needs the same credential mounts as Claude. Its project-level artifacts live in an `openspec/` folder inside the workspace, which is already mounted at `/workspace` — no extra volumes needed.

## Design

### Dockerfile

Add `@fission-ai/openspec@latest` to the existing global npm install line:

```dockerfile
RUN corepack disable && npm install -g yarn pnpm @anthropic-ai/claude-code @fission-ai/openspec@latest
```

No new layer, no structural change.

### `docker/entrypoint.sh`

Introduce an `AGENT` env var (default `claude`) and replace the hardcoded exec:

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

Existing behavior is fully preserved — when `AGENT` is not set, `claude` runs as before.

### `scripts/claude-jail` — flag parsing

`--openspec` is orthogonal to auth modes. Both can be combined freely.

Arg parsing loop change:

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

The `docker run` call gains `-e "AGENT=$AGENT"` alongside the existing `-e "AUTH_MODE=$AUTH_MODE"`.

Remaining args in `CLAUDE_ARGS` pass through to whichever binary runs:
- `claude-jail --openspec init` → `openspec init`
- `claude-jail --openspec --fresh` → fresh session running openspec
- `claude-jail -p "explain this"` → unchanged, runs claude

### Help text additions

New section in `--help` output:

```
AGENT
  (default)     Run Claude Code (claude)
  --openspec    Run OpenSpec (openspec) instead of Claude Code
```

New examples:
```
claude-jail --openspec init        Initialize OpenSpec in the current project
claude-jail --openspec --fresh     Run OpenSpec with a fresh session
```

### README additions

- New row in the auth modes table documenting `--openspec`
- Note that `--openspec` is combinable with all auth mode flags (`--fresh`, `--local`, `--persist`)

## Credential handling

OpenSpec uses Claude under the hood, so `--openspec` mode inherits the same auth mode behavior as `--local` by default. The `openspec/` project folder lives inside the workspace and is already mounted — no additional volumes required.

**Known unknown:** OpenSpec's exact credential requirements have not been tested. If it needs additional mounts or env vars beyond `~/.claude`, those can be added to the `--openspec` branch in a follow-up.

## What is not changing

- No new image tags or separate Dockerfile
- No changes to docker-compose.yml (it passes `AUTH_MODE` via env; `AGENT` follows the same pattern but is only needed for `docker run` direct invocations via the shell script)
- No changes to security posture — same user, same `no-new-privileges`, same volume set
- Version bump handled separately
