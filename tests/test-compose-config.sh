#!/usr/bin/env bash
# Static contract tests for docker-compose.yml (resolved via `docker compose
# config` -- no image build needed, so `make check` runs this before the
# per-variant build+test loop).
#
# Asserts the compose file keeps:
#   - shm_size resolved to 1 GiB on BOTH services. Chromium in the python-ui
#     variant needs more than Docker's default 64MB /dev/shm; the entrypoint
#     suite's Test 8 mirrors this with --shm-size on its docker run, so only
#     this test fails if the compose config itself regresses.
#   - The BASE_IMAGE null-form passthrough: when $BASE_IMAGE is unset the arg
#     must be ABSENT from the resolved build args (so the python-ui
#     Dockerfile's published-base default applies on clean hosts); when set it
#     must be forwarded verbatim (how the Makefile layers on a local base).
#
# Usage:
#   tests/test-compose-config.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SANDBOX_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
PASS=0
FAIL=0

log_pass() {
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

log_fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
}

# Resolve the compose config. PROJECT_DIR is mandatory in the compose file but
# only interpolated, so any absolute path satisfies `config`. Callers control
# BASE_IMAGE through the environment; the $(...) subshells below keep the
# unset/set variants isolated from each other.
compose_config() {
  docker compose \
    --project-directory "${SANDBOX_ROOT}" \
    -f "${SANDBOX_ROOT}/docker-compose.yml" \
    config 2>&1
}

echo "==> Test 1: both services resolve shm_size to 1 GiB"
CONFIG_UNSET="$(
  unset BASE_IMAGE
  PROJECT_DIR=/tmp compose_config
)" || {
  echo "ERROR: docker compose config failed: ${CONFIG_UNSET}" >&2
  exit 1
}
SHM_COUNT="$(grep -c 'shm_size: "1073741824"' <<<"${CONFIG_UNSET}" || true)"
if [[ "${SHM_COUNT}" -eq 2 ]]; then
  log_pass "shm_size 1 GiB on both ralph and ralph-login"
else
  log_fail "Expected shm_size 1073741824 on 2 services, found ${SHM_COUNT}. Config: ${CONFIG_UNSET}"
fi

echo
echo "==> Test 2: BASE_IMAGE omitted from resolved build args when unset"
if ! grep -q "BASE_IMAGE" <<<"${CONFIG_UNSET}"; then
  log_pass "BASE_IMAGE absent when unset (Dockerfile published-base default applies)"
else
  log_fail "BASE_IMAGE leaked into resolved config despite being unset. Config: ${CONFIG_UNSET}"
fi

echo
echo "==> Test 3: BASE_IMAGE forwarded verbatim when set"
CONFIG_SET="$(
  BASE_IMAGE=ralph-sandbox:compose-test-base PROJECT_DIR=/tmp compose_config
)" || {
  echo "ERROR: docker compose config failed: ${CONFIG_SET}" >&2
  exit 1
}
if grep -q "BASE_IMAGE: ralph-sandbox:compose-test-base" <<<"${CONFIG_SET}"; then
  log_pass "BASE_IMAGE forwarded into build args when set"
else
  log_fail "BASE_IMAGE not forwarded. Config: ${CONFIG_SET}"
fi

echo
echo "========================================"
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "========================================"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
