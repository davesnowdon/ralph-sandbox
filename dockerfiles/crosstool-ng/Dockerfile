# syntax=docker/dockerfile:1.7

ARG DEBIAN_IMAGE=debian:bookworm-slim
FROM ${DEBIAN_IMAGE}

LABEL org.opencontainers.image.title="ralph-sandbox-crosstool-ng"
LABEL org.opencontainers.image.description="Ralph agentic loop sandbox with Claude Code + OpenAI Codex CLI support and a crosstool-ng cross-compilation toolchain build environment"
LABEL org.opencontainers.image.source="https://github.com/davesnowdon/ralph-sandbox"

ARG NODE_MAJOR=20
ARG RALPH_REF=6c53cb0
ARG RALPH_UID=1000
ARG RALPH_GID=1000

ENV DEBIAN_FRONTEND=noninteractive

# ---- OS deps: shared base set + crosstool-ng host build prerequisites ----
# Base set (bash/ca-certificates/curl/git/gnupg/jq/make/procps) matches the
# python variant and is required by the shared agent installer. The remainder is
# the crosstool-ng toolchain build environment (build-essential provides the
# host gcc/g++/make/libc-dev).
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      git \
      gnupg \
      jq \
      make \
      procps \
      build-essential \
      autoconf \
      automake \
      libtool \
      libtool-bin \
      gawk \
      bison \
      flex \
      gperf \
      patch \
      perl \
      texinfo \
      help2man \
      libncurses-dev \
      python3 \
      python3-dev \
      wget \
      rsync \
      unzip \
      bzip2 \
      xz-utils \
      file \
      zlib1g-dev \
      meson \
      ninja-build \
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

# ---- crosstool-ng ----
# Built and installed as root at image-build time. `ct-ng build` itself refuses
# to run as root, but the container drops to the non-root `ralph` user (below),
# so agent-driven toolchain builds run as ralph without CT_ALLOW_BUILD_AS_ROOT.
ARG CROSSTOOL_NG_VERSION=1.28.0
RUN cd /tmp \
    && wget -q "https://github.com/crosstool-ng/crosstool-ng/releases/download/crosstool-ng-${CROSSTOOL_NG_VERSION}/crosstool-ng-${CROSSTOOL_NG_VERSION}.tar.xz" \
    && tar xf "crosstool-ng-${CROSSTOOL_NG_VERSION}.tar.xz" \
    && cd "crosstool-ng-${CROSSTOOL_NG_VERSION}" \
    && ./configure --prefix=/usr/local \
    && make \
    && make install \
    && cd /tmp \
    && rm -rf "crosstool-ng-${CROSSTOOL_NG_VERSION}" "crosstool-ng-${CROSSTOOL_NG_VERSION}.tar.xz" \
    && ct-ng version

# ---- Entrypoint (shared with the python variant) ----
COPY --chmod=0755 dockerfiles/common/ralph-entrypoint.sh /usr/local/bin/ralph-entrypoint

# ---- Workspace ----
RUN mkdir -p /workspace && chown -R ralph:ralph /workspace
WORKDIR /workspace
USER ralph

ENTRYPOINT ["ralph-entrypoint"]
