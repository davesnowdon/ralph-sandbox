#!/usr/bin/env bash
# ralph-sandbox entrypoint (shared across image variants).
#
# Installed at /usr/local/bin/ralph-entrypoint and set as the image ENTRYPOINT.
# Behaviour is identical for every variant: universal PROJECT_DIR/git validation,
# optional custom SESSION_RUNNER dispatch, then the default built-in Ralph loop.
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
  cd "${PROJECT_DIR}"
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
      # ls -t picks the newest backup by mtime; filenames are sandbox-generated.
      # shellcheck disable=SC2012
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
    CODEX_CFG="${CODEX_CONFIG_DIR:-}"
    if [[ -z "${CODEX_CFG}" ]]; then
      echo "ERROR: CODEX_CONFIG_DIR is not set (must be mounted in)." >&2
      exit 2
    fi
    if [[ ! -d "${CODEX_CFG}" ]]; then
      echo "ERROR: CODEX_CONFIG_DIR='${CODEX_CFG}' does not exist in container." >&2
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
# Only copy CLAUDE.md if it doesn't already exist — users may customise it.
cp -n /opt/ralph/CLAUDE.md "${RALPH_HOME}/CLAUDE.md" 2>/dev/null || true
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
