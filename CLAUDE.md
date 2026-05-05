# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**claude-jail** is a Docker-based sandbox that runs Claude Code in an isolated container, limiting it to a single project directory while preserving access to Claude credentials (`~/.claude/`, `~/.claude.json`). It intentionally blocks host filesystem paths like `~/.ssh`, `~/.aws`, and other projects.

The image is published to Docker Hub as `oakblu/claude-jail`.

## Key Commands

**Build the Docker image locally:**
```bash
docker compose -f docker/docker-compose.yml build
```

**Run functional tests:**
```bash
bash examples/run_all_tests.sh
```
Expected: 5 test scripts, all passing.

**Run deep security tests:**
```bash
bash examples/security-tests/test-isolation.sh
```
Expected: 11 passes, 2 warnings (no failures).

**CI/CD:**
- `.github/workflows/ci.yml` — runs on every branch push and PR; builds the image and runs all 5 functional tests.
- `.github/workflows/docker-publish.yml` — runs on push to `main` or `v*.*.*` tags; builds, tests, then publishes `:latest` / versioned tags to Docker Hub.

## Architecture

- **`docker/Dockerfile`** — `node:lts-slim` image with `@anthropic-ai/claude-code`, yarn, pnpm, bun, and Rust installed globally. Runs as non-root user `claude` (UID 1000). Uses `entrypoint.sh` for per-mode container setup.
- **`docker/entrypoint.sh`** — Reads `AUTH_MODE` env var (`fresh`/`local`/`persist`), creates `/home/claude/.claude` if persist mode, then `exec claude "$@"`.
- **`docker/docker-compose.yml`** — Mounts three host paths into the container:
  - `${WORKSPACE_PATH}:/workspace` — the project being worked on
  - `${HOME}/.claude:/home/claude/.claude` — credentials and persistent Claude state (--local mode)
  - `${HOME}/.claude.json:/home/claude/.claude.json` — Claude settings (mounted if present)
  - Security: runs with `no-new-privileges`, no other host paths exposed.
- **`examples/security-tests/test-isolation.sh`** — Validates 7 isolation properties: host filesystem invisibility, path traversal confinement, sensitive file inaccessibility, workspace write-through, credential availability, privilege escalation prevention, and symlink safety.

## User Installation

Users add a shell function (from README) to their shell profile, then run `claude-jail` from any project directory. No local build required — the pre-built image is pulled from Docker Hub.
