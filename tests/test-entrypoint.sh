#!/usr/bin/env bash
# Integration tests for the ralph-sandbox entrypoint.
# Requires Docker and builds the image before running.
#
# Usage:
#   tests/test-entrypoint.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SANDBOX_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"

IMAGE="ralph-sandbox:test"
PASS=0
FAIL=0
CLEANUP_DIRS=()

cleanup() {
  for dir in "${CLEANUP_DIRS[@]}"; do
    rm -rf -- "${dir}"
  done
}
trap cleanup EXIT

log_pass() {
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

log_fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
}

# Create a temporary git repo to use as PROJECT_DIR.
make_temp_repo() {
  local tmp
  tmp="$(mktemp -d)"
  CLEANUP_DIRS+=("${tmp}")
  git -C "${tmp}" init -q
  git -C "${tmp}" config user.email "test@test"
  git -C "${tmp}" config user.name "Test"
  git -C "${tmp}" commit --allow-empty -m "init" -q
  # Make the repo world-readable so the container's ralph user (UID 1000)
  # can access it when bind-mounted, even if the host UID differs.
  chmod -R a+rX "${tmp}"
  echo "${tmp}"
}

echo "==> Building image: ${IMAGE}"
docker build -t "${IMAGE}" -f "${SANDBOX_ROOT}/dockerfiles/python/Dockerfile" "${SANDBOX_ROOT}" --quiet

echo
echo "==> Test 1: SESSION_RUNNER runs a custom script"
REPO="$(make_temp_repo)"
RUNNER="$(mktemp)"
CLEANUP_DIRS+=("${RUNNER}")
cat >"${RUNNER}" <<'SCRIPT'
#!/usr/bin/env bash
echo "CUSTOM_RUNNER_OK"
echo "PROJECT_DIR=${PROJECT_DIR}"
echo "ARGS=$*"
SCRIPT
chmod +x "${RUNNER}"

OUTPUT="$(docker run --rm \
  -v "${REPO}:${REPO}" \
  -v "${RUNNER}:/run/ralph/session-runner.sh:ro" \
  -e "PROJECT_DIR=${REPO}" \
  -e "SESSION_RUNNER=/run/ralph/session-runner.sh" \
  --entrypoint ralph-entrypoint \
  "${IMAGE}" arg1 arg2 2>&1)" || true

if echo "${OUTPUT}" | grep -q "CUSTOM_RUNNER_OK"; then
  log_pass "Custom runner was executed"
else
  log_fail "Custom runner was not executed. Output: ${OUTPUT}"
fi

if echo "${OUTPUT}" | grep -q "PROJECT_DIR=${REPO}"; then
  log_pass "PROJECT_DIR passed to custom runner"
else
  log_fail "PROJECT_DIR not passed. Output: ${OUTPUT}"
fi

if echo "${OUTPUT}" | grep -q "ARGS=arg1 arg2"; then
  log_pass "Arguments forwarded to custom runner"
else
  log_fail "Arguments not forwarded. Output: ${OUTPUT}"
fi

echo
echo "==> Test 2: SESSION_RUNNER error when script does not exist"
REPO="$(make_temp_repo)"
OUTPUT="$(docker run --rm \
  -v "${REPO}:${REPO}" \
  -e "PROJECT_DIR=${REPO}" \
  -e "SESSION_RUNNER=/nonexistent/runner.sh" \
  --entrypoint ralph-entrypoint \
  "${IMAGE}" 2>&1)" && RC=0 || RC=$?

if [[ ${RC} -ne 0 ]] && echo "${OUTPUT}" | grep -q "does not exist"; then
  log_pass "Missing runner produces error"
else
  log_fail "Expected error for missing runner (rc=${RC}). Output: ${OUTPUT}"
fi

echo
echo "==> Test 3: SESSION_RUNNER error when script is not executable"
REPO="$(make_temp_repo)"
RUNNER_NX="$(mktemp)"
CLEANUP_DIRS+=("${RUNNER_NX}")
echo '#!/bin/bash' >"${RUNNER_NX}"
chmod -x "${RUNNER_NX}"

OUTPUT="$(docker run --rm \
  -v "${REPO}:${REPO}" \
  -v "${RUNNER_NX}:/run/ralph/session-runner.sh:ro" \
  -e "PROJECT_DIR=${REPO}" \
  -e "SESSION_RUNNER=/run/ralph/session-runner.sh" \
  --entrypoint ralph-entrypoint \
  "${IMAGE}" 2>&1)" && RC=0 || RC=$?

if [[ ${RC} -ne 0 ]] && echo "${OUTPUT}" | grep -q "not executable"; then
  log_pass "Non-executable runner produces error"
else
  log_fail "Expected error for non-executable runner (rc=${RC}). Output: ${OUTPUT}"
fi

echo
echo "==> Test 4: Default path (no SESSION_RUNNER) attempts to run ralph.sh"
REPO="$(make_temp_repo)"
# Without CLAUDE_CONFIG_DIR mounted, the default path should fail with a config error.
# This confirms the entrypoint took the default branch (not the SESSION_RUNNER branch).
OUTPUT="$(docker run --rm \
  -v "${REPO}:${REPO}" \
  -e "PROJECT_DIR=${REPO}" \
  -e "RALPH_TOOL=claude" \
  --entrypoint ralph-entrypoint \
  "${IMAGE}" 2>&1)" && RC=0 || RC=$?

if [[ ${RC} -ne 0 ]] && echo "${OUTPUT}" | grep -q "CLAUDE_CONFIG_DIR"; then
  log_pass "Default path validates CLAUDE_CONFIG_DIR (ralph.sh branch)"
else
  log_fail "Expected CLAUDE_CONFIG_DIR error on default path (rc=${RC}). Output: ${OUTPUT}"
fi

echo
echo "==> Test 5: PROJECT_DIR validation runs for both branches"
OUTPUT="$(docker run --rm \
  -e "PROJECT_DIR=/nonexistent" \
  -e "SESSION_RUNNER=/run/ralph/session-runner.sh" \
  --entrypoint ralph-entrypoint \
  "${IMAGE}" 2>&1)" && RC=0 || RC=$?

if [[ ${RC} -ne 0 ]] && echo "${OUTPUT}" | grep -q "PROJECT_DIR='/nonexistent' does not exist"; then
  log_pass "PROJECT_DIR validation runs before SESSION_RUNNER dispatch"
else
  log_fail "Expected PROJECT_DIR error (rc=${RC}). Output: ${OUTPUT}"
fi

echo
echo "========================================"
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "========================================"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
