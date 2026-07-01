#!/usr/bin/env bash
# Shared agent-runtime install for ralph-sandbox image variants.
#
# Installs the pieces every variant shares: Node.js (the runtime for Claude Code
# and Codex), the Claude Code CLI, the OpenAI Codex CLI, a pinned checkout of
# upstream Ralph, the non-root `ralph` user, and agent-friendly system git
# config. Each variant's Dockerfile COPYs this in and RUNs it once.
#
# Assumes the base image already provides: bash, curl, ca-certificates, gnupg,
# git (installed by each variant's apt layer before this script runs).
#
# Configuration comes from the environment (passed from Dockerfile ARGs):
#   NODE_MAJOR           Node.js major version for the NodeSource repo (default 20)
#   CLAUDE_CODE_VERSION  pinned @anthropic-ai/claude-code version (required)
#   CODEX_VERSION        pinned @openai/codex version (required)
#   RALPH_REF            pinned upstream Ralph git ref (required)
#   RALPH_UID/RALPH_GID  uid/gid for the non-root ralph user (default 1000)
set -euo pipefail

NODE_MAJOR="${NODE_MAJOR:-20}"
RALPH_UID="${RALPH_UID:-1000}"
RALPH_GID="${RALPH_GID:-1000}"
RALPH_REF="${RALPH_REF:?RALPH_REF must be set}"
CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:?CLAUDE_CODE_VERSION must be set}"
CODEX_VERSION="${CODEX_VERSION:?CODEX_VERSION must be set}"

# ---- Node.js (for Claude Code + Codex CLI) ----
curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
apt-get update
apt-get install -y --no-install-recommends nodejs
rm -rf /var/lib/apt/lists/*
node --version
npm --version

# ---- Claude Code CLI ----
npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"
claude --version

# ---- OpenAI Codex CLI ----
npm install -g "@openai/codex@${CODEX_VERSION}"
codex --version

# ---- Non-root user ----
groupadd --gid "${RALPH_GID}" ralph
useradd --uid "${RALPH_UID}" --gid "${RALPH_GID}" --shell /bin/bash --create-home ralph

# ---- Upstream Ralph (no local copy) ----
git clone --depth 1 --no-single-branch https://github.com/snarktank/ralph.git /opt/ralph
git -C /opt/ralph checkout "${RALPH_REF}"
chmod +x /opt/ralph/ralph.sh

# ---- Git defaults (agent-friendly) ----
git config --system user.email "ralph@local"
git config --system user.name "Ralph"
git config --system core.autocrlf false
git config --system pull.rebase false
git config --system --add safe.directory '*'
