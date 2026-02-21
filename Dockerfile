# syntax=docker/dockerfile:1.7

FROM python:3.12-slim

LABEL org.opencontainers.image.title="ralph-sandbox"
LABEL org.opencontainers.image.description="Ralph agentic loop sandbox pinned to Claude Code only + modern Python tooling (uv/hatch/ruff/pytest/mypy)"
LABEL org.opencontainers.image.source="https://github.com/davesnowdon/ralph-sandbox"

ARG NODE_MAJOR=20
ARG RALPH_REF=main
ARG RALPH_UID=1000
ARG RALPH_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    # Install uv itself to /usr/local/bin (instead of ~/.local/bin)
    UV_INSTALL_DIR=/usr/local/bin \
    # Install uv-managed tool shims to /usr/local/bin so they're on PATH for all users
    UV_TOOL_BIN_DIR=/usr/local/bin

# ---- OS deps (keep tight) ----
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      git \
      gnupg \
      jq \
      procps \
    && rm -rf /var/lib/apt/lists/*

# ---- Node.js (for Claude Code) ----
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && node --version && npm --version

# ---- Claude Code CLI ----
RUN npm install -g @anthropic-ai/claude-code \
    && claude --version

# ---- Modern Python tooling (uv + hatch/ruff/pytest/mypy) ----
# Install uv (standalone), then install tools into /usr/local/bin so they're on PATH for all users.
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && uv --version \
    && uv tool install hatch \
    && uv tool install ruff \
    && uv tool install pytest \
    && uv tool install mypy \
    && hatch --version \
    && ruff --version \
    && pytest --version \
    && mypy --version

# ---- Non-root user ----
RUN groupadd --gid ${RALPH_GID} ralph \
    && useradd --uid ${RALPH_UID} --gid ${RALPH_GID} --shell /bin/bash --create-home ralph

# ---- Upstream Ralph (no local copy) ----
RUN git clone https://github.com/snarktank/ralph.git /opt/ralph \
    && cd /opt/ralph \
    && git checkout "${RALPH_REF}" \
    && chmod +x /opt/ralph/ralph.sh

# ---- Git defaults (agent-friendly) ----
RUN git config --global user.email "ralph@local" \
    && git config --global user.name "Ralph" \
    && git config --global core.autocrlf false \
    && git config --global pull.rebase false \
    && git config --global --add safe.directory /workspace

# ---- Entrypoint wrapper (forces --tool claude, supports PROJECT_DIR + CLAUDE_CONFIG_DIR) ----
RUN cat > /usr/local/bin/ralph-entrypoint <<'EOF' \
 && chmod +x /usr/local/bin/ralph-entrypoint
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/workspace}"
CLAUDE_CFG="${CLAUDE_CONFIG_DIR:-}"

if [[ -z "${CLAUDE_CFG}" ]]; then
  echo "ERROR: CLAUDE_CONFIG_DIR is not set (must be mounted in)." >&2
  exit 2
fi
if [[ ! -d "${CLAUDE_CFG}" ]]; then
  echo "ERROR: CLAUDE_CONFIG_DIR='${CLAUDE_CFG}' does not exist in container." >&2
  exit 2
fi
if [[ ! -d "${PROJECT_DIR}" ]]; then
  echo "ERROR: PROJECT_DIR='${PROJECT_DIR}' does not exist in container." >&2
  exit 2
fi

# Ralph expects prd.json/progress.txt/CLAUDE.md relative to ralph.sh's directory.
# Keep those project-local under `scripts/ralph` so state stays with the mounted project.
RALPH_HOME="${PROJECT_DIR}/scripts/ralph"
mkdir -p "${RALPH_HOME}"

cp -f /opt/ralph/ralph.sh "${RALPH_HOME}/ralph.sh"
cp -f /opt/ralph/CLAUDE.md "${RALPH_HOME}/CLAUDE.md"
chmod +x "${RALPH_HOME}/ralph.sh"

# Strip any user-provided --tool flags and force --tool claude.
FILTERED_ARGS=()
skip_next=0
for arg in "$@"; do
  if [[ $skip_next -eq 1 ]]; then
    skip_next=0
    continue
  fi
  case "$arg" in
    --tool) skip_next=1 ;;
    --tool=*) ;;
    *) FILTERED_ARGS+=("$arg") ;;
  esac
done

exec "${RALPH_HOME}/ralph.sh" --tool claude "${FILTERED_ARGS[@]}"
EOF

# ---- Workspace ----
RUN mkdir -p /workspace && chown -R ralph:ralph /workspace
WORKDIR /workspace
USER ralph

ENTRYPOINT ["ralph-entrypoint"]