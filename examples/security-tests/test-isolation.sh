#!/usr/bin/env bash
# Security isolation tests for claude-jail.
# Verifies that the Docker container cannot access host files outside the declared mounts.

set -euo pipefail

COMPOSE_FILE="$(cd "$(dirname "$0")/../.." && pwd)/docker/docker-compose.yml"
PASS=0
FAIL=0
WARN=0

green() { printf '\033[0;32m  PASS\033[0m %s\n' "$1"; }
red()   { printf '\033[0;31m  FAIL\033[0m %s\n' "$1"; }
warn()  { printf '\033[0;33m  WARN\033[0m %s\n' "$1"; }
header(){ printf '\n\033[1m%s\033[0m\n' "$1"; }

run_in_container() {
  WORKSPACE_PATH="$(pwd)" docker compose -f "$COMPOSE_FILE" run --rm claude-jail bash -c "$1" 2>/dev/null
}

header "Building image (if needed)..."
docker compose -f "$COMPOSE_FILE" build --quiet 2>/dev/null

# ---------------------------------------------------------------------------
header "1. Host filesystem visibility"
# ---------------------------------------------------------------------------

if run_in_container 'ls /Users 2>/dev/null' | grep -q .; then
  red "/Users is visible inside the container"; ((++FAIL))
else
  green "/Users is not visible inside the container"; ((++PASS))
fi

if run_in_container 'ls /host 2>/dev/null' | grep -q .; then
  red "/host is visible inside the container"; ((++FAIL))
else
  green "/host mount does not exist"; ((++PASS))
fi

if run_in_container 'ls /home 2>/dev/null' | grep -qv "^$"; then
  warn "/home exists but is expected to be empty in the container"; ((++WARN))
else
  green "/home contains no host user directories"; ((++PASS))
fi

# ---------------------------------------------------------------------------
header "2. Path traversal via mount points"
# ---------------------------------------------------------------------------

traversal_output=$(run_in_container 'ls /workspace/../../ 2>/dev/null')
if echo "$traversal_output" | grep -q "Users\|pablohpsilva"; then
  red "Path traversal from /workspace exposes host directories"; ((++FAIL))
else
  green "/workspace/../../ stays inside container filesystem"; ((++PASS))
fi

claude_traversal=$(run_in_container 'ls /root/.claude/../ 2>/dev/null | wc -l | tr -d " "')
if [ "${claude_traversal:-0}" -gt 20 ]; then
  warn "/root/.claude/../ shows many files — check if host ~ is exposed (${claude_traversal} entries)"; ((++WARN))
else
  green "/root/.claude/../ does not expose host home directory"; ((++PASS))
fi

# ---------------------------------------------------------------------------
header "3. Sensitive host file access"
# ---------------------------------------------------------------------------

if run_in_container 'cat /root/.claude/../.zshrc 2>/dev/null' | grep -q .; then
  red "Container can read ~/.zshrc via .claude mount traversal"; ((++FAIL))
else
  green "Cannot read ~/.zshrc via mount traversal"; ((++PASS))
fi

if run_in_container 'ls /root/.claude/../.ssh 2>/dev/null' | grep -q .; then
  red "Container can see ~/.ssh via mount traversal"; ((++FAIL))
else
  green "Cannot access ~/.ssh via mount traversal"; ((++PASS))
fi

if run_in_container 'cat /root/.claude/../.aws/credentials 2>/dev/null' | grep -q .; then
  red "Container can read ~/.aws/credentials via mount traversal"; ((++FAIL))
else
  green "Cannot read ~/.aws/credentials via mount traversal"; ((++PASS))
fi

# ---------------------------------------------------------------------------
header "4. Workspace write access (expected behavior)"
# ---------------------------------------------------------------------------

SENTINEL="__jail_test_$$"
run_in_container "touch /workspace/${SENTINEL}" >/dev/null 2>&1
if [ -f "$(pwd)/${SENTINEL}" ]; then
  green "Writes to /workspace are visible on the host (by design)"; ((++PASS))
  rm -f "$(pwd)/${SENTINEL}"
else
  warn "Could not verify workspace write-through (running from unexpected directory?)"; ((++WARN))
fi

# ---------------------------------------------------------------------------
header "5. Claude credentials accessible (expected behavior)"
# ---------------------------------------------------------------------------

if run_in_container 'test -f /root/.claude/.credentials.json && echo yes' | grep -q yes; then
  green "Claude credentials are accessible inside the container (required for auth)"; ((++PASS))
else
  warn "Claude credentials not found — you may need to log in once on the host"; ((++WARN))
fi

# ---------------------------------------------------------------------------
header "6. Privilege escalation"
# ---------------------------------------------------------------------------

if run_in_container 'sudo -l 2>/dev/null' | grep -qv "not found"; then
  warn "sudo is available inside the container"; ((++WARN))
else
  green "sudo is not available inside the container"; ((++PASS))
fi

if run_in_container 'cat /proc/1/status 2>/dev/null | grep "^CapEff"' | grep -qv "0000000000000000"; then
  warn "Container process has non-zero capabilities — review security_opt settings"; ((++WARN))
else
  green "no-new-privileges is enforced"; ((++PASS))
fi

# ---------------------------------------------------------------------------
header "7. Symlink safety inside .claude mount"
# ---------------------------------------------------------------------------

bad_symlinks=$(run_in_container 'find /root/.claude -type l 2>/dev/null | while read link; do
  target=$(readlink "$link")
  case "$target" in
    /Users/*|/home/*|/root/[^.]*) echo "$link -> $target" ;;
  esac
done')

if [ -n "$bad_symlinks" ]; then
  warn "Absolute symlinks in .claude pointing outside the config dir:"; ((++WARN))
  echo "$bad_symlinks" | while read -r line; do printf '         %s\n' "$line"; done
else
  green "No dangerous symlinks found inside .claude"; ((++PASS))
fi

# ---------------------------------------------------------------------------
printf '\n\033[1m─────────────────────────────────────────\033[0m\n'
printf '\033[1mResults: \033[0;32m%d passed\033[0m  \033[0;31m%d failed\033[0m  \033[0;33m%d warnings\033[0m\n' "$PASS" "$FAIL" "$WARN"
printf '\033[1m─────────────────────────────────────────\033[0m\n\n'

[ "$FAIL" -eq 0 ]
