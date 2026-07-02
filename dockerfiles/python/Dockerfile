# syntax=docker/dockerfile:1.7

ARG PYTHON_IMAGE=python:3.12.11-slim-bookworm
FROM ${PYTHON_IMAGE}

LABEL org.opencontainers.image.title="ralph-sandbox"
LABEL org.opencontainers.image.description="Ralph agentic loop sandbox with Claude Code + OpenAI Codex CLI support and modern Python tooling (uv/hatch/ruff/pytest/mypy/pyright/coverage) plus SAST (bandit/pip-audit/semgrep)"
LABEL org.opencontainers.image.source="https://github.com/davesnowdon/ralph-sandbox"

ARG NODE_MAJOR=20
ARG RALPH_REF=6c53cb0
ARG RALPH_UID=1000
ARG RALPH_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    # Install uv itself to /usr/local/bin (instead of ~/.local/bin)
    UV_INSTALL_DIR=/usr/local/bin \
    # Install uv-managed tool shims to /usr/local/bin so they're on PATH for all users
    UV_TOOL_BIN_DIR=/usr/local/bin \
    # Store uv-managed tool environments in a world-readable location. The default
    # (~/.local/share/uv/tools under /root, mode 700) is unreadable by the non-root
    # ralph user, which breaks the shims at runtime. /opt is traversable by all users.
    UV_TOOL_DIR=/opt/uv/tools

# ---- OS deps (keep tight) ----
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      git \
      gnupg \
      jq \
      make \
      procps \
    && rm -rf /var/lib/apt/lists/*

# ---- Shared agent runtime (Node + Claude Code + Codex + Ralph + user + git) ----
ARG CLAUDE_CODE_VERSION=2.1.177
ARG CODEX_VERSION=0.139.0
COPY dockerfiles/common/install-agents.sh /tmp/install-agents.sh
RUN NODE_MAJOR="${NODE_MAJOR}" \
    RALPH_REF="${RALPH_REF}" \
    RALPH_UID="${RALPH_UID}" \
    RALPH_GID="${RALPH_GID}" \
    CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION}" \
    CODEX_VERSION="${CODEX_VERSION}" \
    bash /tmp/install-agents.sh \
    && rm -f /tmp/install-agents.sh

# ---- Modern Python tooling (uv + hatch/ruff/pytest/mypy) ----
# Install uv (standalone), then install tools into /usr/local/bin so they're on PATH for all users.
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && uv --version \
    && uv tool install hatch \
    && uv tool install ruff \
    && uv tool install pytest \
    && uv tool install mypy \
    && uv tool install coverage \
    && hatch --version \
    && ruff --version \
    && pytest --version \
    && mypy --version \
    && coverage --version

# ---- Pyright (Python type checker, via npm so it shares the installed Node) ----
# Installed via npm rather than the pyright PyPI wrapper: the wrapper downloads
# its own per-user nodeenv on first run (which would re-download for the ralph
# user at runtime). The npm package is the real Node-based pyright on PATH for
# all users and verifies at build time.
RUN npm install -g pyright \
    && pyright --version

# ---- Security / SAST tooling (bandit + pip-audit + semgrep) ----
# Installed as uv-managed tools (shims on PATH in /usr/local/bin, like the block
# above) so the lithos-loom deterministic gate can run them as gate checks.
# bandit is self-contained; pip-audit and semgrep fetch advisory/rule data at run
# time (the gate container has egress) and cache it under the mounted gate cache.
RUN uv tool install bandit \
    && uv tool install pip-audit \
    && uv tool install semgrep \
    && bandit --version \
    && pip-audit --version \
    && semgrep --version

# ---- Entrypoint (shared with the crosstool-ng variant) ----
COPY --chmod=0755 dockerfiles/common/ralph-entrypoint.sh /usr/local/bin/ralph-entrypoint

# ---- Workspace ----
RUN mkdir -p /workspace && chown -R ralph:ralph /workspace
WORKDIR /workspace
USER ralph

ENTRYPOINT ["ralph-entrypoint"]
