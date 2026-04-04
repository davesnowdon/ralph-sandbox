# syntax=docker/dockerfile:1.7

ARG PYTHON_IMAGE=python:3.12.11-slim-bookworm
FROM ${PYTHON_IMAGE}

LABEL org.opencontainers.image.title="ralph-sandbox"
LABEL org.opencontainers.image.description="Ralph agentic loop sandbox with Claude Code + OpenAI Codex CLI support and modern Python tooling (uv/hatch/ruff/pytest/mypy)"
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

# ---- Node.js (for Claude Code + Codex CLI) ----
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && node --version && npm --version

# ---- Claude Code CLI ----
ARG CLAUDE_CODE_VERSION=2.1.92
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
    && claude --version

# ---- OpenAI Codex CLI ----
ARG CODEX_VERSION=0.118.0
RUN npm install -g @openai/codex@${CODEX_VERSION} \
    && codex --version

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
RUN git config --system user.email "ralph@local" \
    && git config --system user.name "Ralph" \
    && git config --system core.autocrlf false \
    && git config --system pull.rebase false \
    && git config --system --add safe.directory '*'

# ---- Entrypoint wrapper (configurable tool via RALPH_TOOL, supports PROJECT_DIR + config dirs + SESSION_RUNNER) ----
RUN cat > /usr/local/bin/ralph-entrypoint <<'EOF' \
 && chmod +x /usr/local/bin/ralph-entrypoint
#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0

PROJECT_DIR="${PROJECT_DIR:-/workspace}"

# ---- Phase A: Universal validation (always runs) ----

if [[ ! -d "${PROJECT_DIR}" ]]; then
  echo "ERROR: PROJECT_DIR='${PROJECT_DIR}' does not exist in container." >&2
  exit 2
fi

if ! git -C "${PROJECT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: PROJECT_DIR='${PROJECT_DIR}' is not inside a valid Git working tree in the container." >&2
  echo "Check your bind mounts. Linked git worktrees need the shared git metadata mounted too." >&2
  exit 2
fi

if ! git_dir="$(git -C "${PROJECT_DIR}" rev-parse --git-dir 2>/dev/null)"; then
  echo "ERROR: Unable to resolve git dir for PROJECT_DIR='${PROJECT_DIR}'." >&2
  exit 2
fi

if ! common_dir="$(git -C "${PROJECT_DIR}" rev-parse --git-common-dir 2>/dev/null)"; then
  echo "ERROR: Unable to resolve git common dir for PROJECT_DIR='${PROJECT_DIR}'." >&2
  exit 2
fi

if ! git -C "${PROJECT_DIR}" status --short >/dev/null 2>&1; then
  echo "ERROR: Git is not functional for PROJECT_DIR='${PROJECT_DIR}' inside the container." >&2
  echo "Resolved git dir: ${git_dir}" >&2
  echo "Resolved git common dir: ${common_dir}" >&2
  exit 2
fi

# ---- Phase B: Custom session runner (if provided) ----

SESSION_RUNNER="${SESSION_RUNNER:-}"

if [[ -n "${SESSION_RUNNER}" ]]; then
  if [[ ! -f "${SESSION_RUNNER}" ]]; then
    echo "ERROR: SESSION_RUNNER='${SESSION_RUNNER}' does not exist." >&2
    exit 2
  fi
  if [[ ! -x "${SESSION_RUNNER}" ]]; then
    echo "ERROR: SESSION_RUNNER='${SESSION_RUNNER}' is not executable." >&2
    exit 2
  fi
  exec "${SESSION_RUNNER}" "$@"
fi

# ---- Phase C: Default runner (built-in Ralph loop) ----

RALPH_TOOL="${RALPH_TOOL:-claude}"

# Validate config directory for the selected tool.
case "${RALPH_TOOL}" in
  claude)
    CLAUDE_CFG="${CLAUDE_CONFIG_DIR:-}"
    if [[ -z "${CLAUDE_CFG}" ]]; then
      echo "ERROR: CLAUDE_CONFIG_DIR is not set (must be mounted in)." >&2
      exit 2
    fi
    if [[ ! -d "${CLAUDE_CFG}" ]]; then
      echo "ERROR: CLAUDE_CONFIG_DIR='${CLAUDE_CFG}' does not exist in container." >&2
      exit 2
    fi
    # Restore .claude.json from backup if missing (e.g. after interrupted config write)
    if [[ ! -f "${CLAUDE_CFG}/.claude.json" ]]; then
      latest_backup="$(ls -t "${CLAUDE_CFG}/backups/".claude.json.backup.* 2>/dev/null | head -1)"
      if [[ -n "${latest_backup}" ]]; then
        echo "WARNING: ${CLAUDE_CFG}/.claude.json missing — restoring from backup: ${latest_backup}" >&2
        cp "${latest_backup}" "${CLAUDE_CFG}/.claude.json"
      else
        echo "WARNING: ${CLAUDE_CFG}/.claude.json not found and no backups available." >&2
      fi
    fi
    ;;
  codex)
    CODEX_CFG="${CODEX_HOME:-}"
    if [[ -z "${CODEX_CFG}" ]]; then
      echo "ERROR: CODEX_HOME is not set (must be mounted in)." >&2
      exit 2
    fi
    if [[ ! -d "${CODEX_CFG}" ]]; then
      echo "ERROR: CODEX_HOME='${CODEX_CFG}' does not exist in container." >&2
      exit 2
    fi
    ;;
  *)
    echo "ERROR: RALPH_TOOL='${RALPH_TOOL}' is not supported. Use 'claude' or 'codex'." >&2
    exit 2
    ;;
esac

# Ralph expects prd.json/progress.txt/CLAUDE.md relative to ralph.sh's directory.
# Keep those project-local under `scripts/ralph` so state stays with the mounted project.
RALPH_HOME="${PROJECT_DIR}/scripts/ralph"
mkdir -p "${RALPH_HOME}"

cp -f /opt/ralph/ralph.sh "${RALPH_HOME}/ralph.sh"
cp -f /opt/ralph/CLAUDE.md "${RALPH_HOME}/CLAUDE.md"
chmod +x "${RALPH_HOME}/ralph.sh"

# Strip any user-provided --tool flags and inject --tool $RALPH_TOOL.
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

exec "${RALPH_HOME}/ralph.sh" --tool "${RALPH_TOOL}" "${FILTERED_ARGS[@]}"
EOF

# ---- Workspace ----
RUN mkdir -p /workspace && chown -R ralph:ralph /workspace
WORKDIR /workspace
USER ralph

ENTRYPOINT ["ralph-entrypoint"]
