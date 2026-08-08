# syntax=docker/dockerfile:1.7

# Layered on the python variant's build image: everything in
# dockerfiles/python/ plus a headless browser for web-UI e2e evaluation (#40).
# Kept as a separate variant so pure-Python projects don't pay the ~700MB
# chromium + X11-library tail in their sandbox image; web-UI projects opt in
# by selecting this image (e.g. lithos-loom's per-project develop_image).
ARG BASE_IMAGE=ralph-sandbox:python-test
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
# them. The dir is left ralph-writable on purpose: browser builds are keyed to
# the playwright version, so a project pinning a different playwright can
# self-install its matching revision into the same cache path at run time
# (egress exists; the baked chromium serves the common case download-free).
# Headless only — no X/VNC.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright
RUN uv tool install playwright \
    && playwright --version \
    && playwright install --with-deps chromium \
    && test -n "$(ls -A /opt/playwright)" \
    && chown -R ralph:ralph /opt/playwright

USER ralph
