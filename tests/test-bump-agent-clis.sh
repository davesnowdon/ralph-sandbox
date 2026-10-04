#!/usr/bin/env bash
# Tests for scripts/bump-agent-clis.sh against a throwaway dockerfiles/ tree and
# a fake `npm` (no network, no docker), so `make check` runs it on any host.
#
# Asserts the script:
#   - rewrites every Dockerfile's ARG pin to the registry version (all variants);
#   - leaves an up-to-date tree byte-identical;
#   - with --check, reports a bump (exit 3) without touching any file;
#   - refuses a registry answer that is not a plain x.y.z release, changing nothing.
#
# Usage:
#   tests/test-bump-agent-clis.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BUMP="${SCRIPT_DIR}/../scripts/bump-agent-clis.sh"
PASS=0
FAIL=0
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

log_pass() {
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

log_fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
}

# A fake npm answering `npm view <pkg> version` from FAKE_CLAUDE / FAKE_CODEX.
cat >"${WORK}/npm" <<'EOF'
#!/usr/bin/env bash
case "$2" in
  @anthropic-ai/claude-code) echo "${FAKE_CLAUDE}" ;;
  @openai/codex) echo "${FAKE_CODEX}" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "${WORK}/npm"

# A fresh two-variant tree pinned at claude 2.1.1 / codex 0.1.0.
make_tree() {
  rm -rf "${WORK}/dockerfiles"
  for v in python cpp; do
    mkdir -p "${WORK}/dockerfiles/${v}"
    printf 'FROM scratch\nARG CLAUDE_CODE_VERSION=2.1.1\nARG CODEX_VERSION=0.1.0\n' \
      >"${WORK}/dockerfiles/${v}/Dockerfile"
  done
}

snapshot() {
  cat "${WORK}"/dockerfiles/*/Dockerfile
}

bump() {
  NPM="${WORK}/npm" DOCKERFILES_DIR="${WORK}/dockerfiles" "${BUMP}" "$@"
}

echo "==> Test 1: stale pins are rewritten in every Dockerfile"
make_tree
if OUT="$(FAKE_CLAUDE=2.1.9 FAKE_CODEX=0.2.0 bump)" &&
  [[ "$(grep -c '^ARG CLAUDE_CODE_VERSION=2.1.9$' "${WORK}"/dockerfiles/*/Dockerfile | grep -c ':1$')" -eq 2 ]] &&
  [[ "$(grep -c '^ARG CODEX_VERSION=0.2.0$' "${WORK}"/dockerfiles/*/Dockerfile | grep -c ':1$')" -eq 2 ]] &&
  grep -q '@openai/codex: 0.1.0 -> 0.2.0' <<<"${OUT}"; then
  log_pass "both pins bumped in both variants, change reported"
else
  log_fail "pins not bumped as expected. Output: ${OUT:-}; tree: $(snapshot)"
fi

echo "==> Test 2: an up-to-date tree is left byte-identical"
make_tree
BEFORE="$(snapshot)"
if OUT="$(FAKE_CLAUDE=2.1.1 FAKE_CODEX=0.1.0 bump)" &&
  [[ "$(snapshot)" == "${BEFORE}" ]] && grep -q 'up to date' <<<"${OUT}"; then
  log_pass "no-op when current"
else
  log_fail "tree changed or no 'up to date' report. Output: ${OUT:-}"
fi

echo "==> Test 3: --check reports a bump (exit 3) and changes nothing"
make_tree
BEFORE="$(snapshot)"
set +e
FAKE_CLAUDE=2.1.9 FAKE_CODEX=0.1.0 bump --check >/dev/null
RC=$?
set -e
if [[ "${RC}" -eq 3 && "$(snapshot)" == "${BEFORE}" ]]; then
  log_pass "--check exits 3 with the tree untouched"
else
  log_fail "--check exited ${RC} or modified the tree"
fi

echo "==> Test 4: a registry answer that is not x.y.z is refused"
# Bad codex with a good claude too: claude must not be half-bumped first.
for bad in "" "2.2.0-beta.1" "1.2.3; rm -rf /"; do
  make_tree
  BEFORE="$(snapshot)"
  set +e
  FAKE_CLAUDE=2.1.9 FAKE_CODEX="${bad}" bump >/dev/null 2>&1
  RC=$?
  set -e
  if [[ "${RC}" -ne 0 && "$(snapshot)" == "${BEFORE}" ]]; then
    log_pass "refused codex '${bad}' with nothing changed (claude not half-bumped)"
  else
    log_fail "accepted '${bad}' (exit ${RC}) or modified the tree"
  fi
done

echo
echo "========================================"
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "========================================"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
