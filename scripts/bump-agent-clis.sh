#!/usr/bin/env bash
# Bump the pinned agent CLIs to the latest npm releases.
#
# Every Dockerfile that installs the agents pins them with
#   ARG CLAUDE_CODE_VERSION=<x.y.z>   (@anthropic-ai/claude-code)
#   ARG CODEX_VERSION=<x.y.z>         (@openai/codex)
# The pins keep image builds reproducible; this script keeps them fresh. It
# rewrites every such ARG line under dockerfiles/ to the registry's current
# version and prints one line per CLI. Run by
# .github/workflows/bump-agent-clis.yml on a schedule; safe to run by hand.
#
# Usage:
#   scripts/bump-agent-clis.sh          rewrite stale pins in place
#   scripts/bump-agent-clis.sh --check  report only; exit 3 when a bump exists
#
# Environment (for tests):
#   NPM              npm executable (default: npm)
#   DOCKERFILES_DIR  tree to rewrite (default: <repo>/dockerfiles)
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
NPM="${NPM:-npm}"
DOCKERFILES_DIR="${DOCKERFILES_DIR:-${SCRIPT_DIR}/../dockerfiles}"

CHECK_ONLY=0
case "${1:-}" in
  "") ;;
  --check) CHECK_ONLY=1 ;;
  *)
    echo "usage: $0 [--check]" >&2
    exit 2
    ;;
esac

# ARG name -> npm package.
ARGS=(CLAUDE_CODE_VERSION CODEX_VERSION)
PACKAGES=(@anthropic-ai/claude-code @openai/codex)

# A registry answer goes straight into a sed replacement and a Dockerfile, so
# accept only a plain x.y.z release (no pre-release tags, nothing else).
is_release() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Every Dockerfile carrying the ARG, as NUL-separated paths.
files_with_arg() {
  grep -rlZ --include=Dockerfile -E "^ARG $1=" "${DOCKERFILES_DIR}" || true
}

# Resolve and validate every version BEFORE rewriting anything, so a bad
# registry answer for one CLI never leaves the other half-bumped.
LATEST=()
for i in "${!ARGS[@]}"; do
  pkg="${PACKAGES[$i]}"
  latest="$("${NPM}" view "${pkg}" version)"
  if ! is_release "${latest}"; then
    echo "error: ${pkg}: registry returned '${latest}', not an x.y.z release" >&2
    exit 1
  fi
  LATEST+=("${latest}")
done

stale=0
for i in "${!ARGS[@]}"; do
  arg="${ARGS[$i]}"
  pkg="${PACKAGES[$i]}"
  latest="${LATEST[$i]}"
  current="$(grep -rhE --include=Dockerfile "^ARG ${arg}=" "${DOCKERFILES_DIR}" |
    sed -E "s/^ARG ${arg}=//" | sort -u | paste -sd, -)"
  if [[ -z "${current}" ]]; then
    echo "error: no 'ARG ${arg}=' line under ${DOCKERFILES_DIR}" >&2
    exit 1
  fi
  if [[ "${current}" == "${latest}" ]]; then
    echo "${pkg}: ${latest} (up to date)"
    continue
  fi
  stale=1
  echo "${pkg}: ${current} -> ${latest}"
  if [[ "${CHECK_ONLY}" -eq 0 ]]; then
    while IFS= read -r -d '' f; do
      sed -i -E "s/^ARG ${arg}=.*/ARG ${arg}=${latest}/" "$f"
    done < <(files_with_arg "${arg}")
  fi
done

if [[ "${CHECK_ONLY}" -eq 1 && "${stale}" -eq 1 ]]; then
  exit 3
fi
