# syntax=docker/dockerfile:1.7

# Layered on the python variant's image: everything in dockerfiles/python/
# plus a headless browser for web-UI e2e evaluation (#40). Kept as a separate
# variant so pure-Python projects don't pay the ~700MB chromium + X11-library
# tail in their sandbox image; web-UI projects opt in by selecting this image
# (e.g. lithos-loom's per-project develop_image).
#
# Two-tier base resolution:
#   - Default: the PUBLISHED python image, so a clean host (wrapper --build,
#     plain `docker build`, CI PR validation) resolves without a local build.
#   - The Makefile overrides BASE_IMAGE=ralph-sandbox:python-test after building
#     the python base from the current checkout, so `make check VARIANT=python-ui`
#     tests this source tree, not the last release.
ARG BASE_IMAGE=docker.io/davesnowdon/ralph-sandbox:python
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="ralph-sandbox"
LABEL org.opencontainers.image.description="ralph-sandbox python variant plus headless-browser e2e tooling (playwright + chromium) for web-UI projects"
LABEL org.opencontainers.image.source="https://github.com/davesnowdon/ralph-sandbox"

# The python base image ends as the non-root ralph user; installing the
# browser and its OS deps needs root, then we drop back.
USER root

# ---- Headless browser (playwright + chromium) for web-UI e2e evaluation ----
# Coder/reviewer agents and gate checks (e.g. a `make e2e` step folded into a
# repo-parity command) need a real headless browser in-container. Browsers
# land at a FIXED, non-$HOME path so per-run home/config mounts can't shadow
# them. Headless only — no X/VNC.
#
# The playwright CLI is installed as an isolated uv tool: the image deliberately
# does NOT provide an importable Python `playwright` library. Consuming projects
# declare playwright as their own (dev) dependency and `uv sync` it in-tree.
#
# Version skew: installing a playwright package does NOT download a browser —
# browser builds are keyed to the playwright version, and only the
# PLAYWRIGHT_VERSION revision is baked. A project pinning any other version
# must run `uv run playwright install chromium` as part of its environment
# setup or e2e command (it no-ops when the matching revision is already
# present). That works because egress exists and /opt/playwright is left
# ralph-writable on purpose; the baked chromium serves the PLAYWRIGHT_VERSION
# common case download-free. The limit: that command runs as ralph and
# installs BROWSER FILES only — it cannot add system packages (root-installed
# at build time via --with-deps, keyed to PLAYWRIGHT_VERSION), so the pinned
# version must stay compatible with the baked OS deps. Nearby versions are
# likely fine (1.61.0 verified against the 1.62.0 deps); substantially
# older/newer is not guaranteed — for those, rebuild this image with a
# matching PLAYWRIGHT_VERSION build-arg.
#
# PLAYWRIGHT_VERSION is pinned so the baked browser revision is reproducible
# (the chromium revision is derived from the playwright version). Upgrades are
# deliberate: bump the pin and rely on the python-ui browser smoke test in
# tests/test-entrypoint.sh to prove the new revision still renders headlessly.
ARG PLAYWRIGHT_VERSION=1.62.0
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright
RUN uv tool install "playwright==${PLAYWRIGHT_VERSION}" \
    && playwright --version \
    && playwright install --with-deps chromium \
    && test -n "$(ls -A /opt/playwright)" \
    && chown -R ralph:ralph /opt/playwright

USER ralph
