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

**Run isolation tests:**
```bash
bash examples/security-tests/test-isolation.sh
```
Expected: 10 passes, 3 warnings (no failures).

**CI/CD** is handled by `.github/workflows/docker-publish.yml` — pushes to `main` publish `:latest`; `v*.*.*` tags publish versioned images.

## Architecture

- **`docker/Dockerfile`** — Minimal Node.js image with `@anthropic-ai/claude-code` installed globally.
- **`docker/docker-compose.yml`** — Mounts three host paths into the container:
  - `${WORKSPACE_PATH}:/workspace` — the project being worked on
  - `${HOME}/.claude:/root/.claude` — credentials and persistent Claude state
  - `${HOME}/.claude.json:/root/.claude.json` — Claude settings
  - Security: runs with `no-new-privileges`, no other host paths exposed.
- **`examples/security-tests/test-isolation.sh`** — Validates 7 isolation properties: host filesystem invisibility, path traversal confinement, sensitive file inaccessibility, workspace write-through, credential availability, privilege escalation prevention, and symlink safety.

## User Installation

Users add a shell function (from README) to their shell profile, then run `claude-jail` from any project directory. No local build required — the pre-built image is pulled from Docker Hub.
