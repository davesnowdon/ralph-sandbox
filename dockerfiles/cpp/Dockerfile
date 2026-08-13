# syntax=docker/dockerfile:1.7

ARG DEBIAN_IMAGE=debian:trixie-slim
FROM ${DEBIAN_IMAGE}

LABEL org.opencontainers.image.title="ralph-sandbox-cpp"
LABEL org.opencontainers.image.description="Ralph agentic loop sandbox with Claude Code + OpenAI Codex CLI support and a native + cross C/C++ development environment (GCC + Clang, CMake/Ninja/Meson, Conan, gdb/lldb, clang-tidy/clang-format/cppcheck/valgrind)"
LABEL org.opencontainers.image.source="https://github.com/davesnowdon/ralph-sandbox"

ARG NODE_MAJOR=20
ARG RALPH_REF=6c53cb0
ARG RALPH_UID=1000
ARG RALPH_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    # Put uv + its tool shims on the global PATH, and store tool environments in a
    # world-readable location so the non-root ralph user can run conan (same trick
    # the python image uses; the default under /root mode 700 is unreadable).
    UV_INSTALL_DIR=/usr/local/bin \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    UV_TOOL_DIR=/opt/uv/tools

# ---- OS deps: shared base set + native/cross C/C++ toolchain ----
# Base set (bash/ca-certificates/curl/git/gnupg/jq/make/procps) matches the other
# variants and is required by the shared agent installer. The remainder is the
# C/C++ application development stack: both GCC (build-essential) and Clang, the
# CMake/Ninja/Meson build systems, debuggers, and static/dynamic analysis tools.
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
      clang \
      clang-tidy \
      clang-format \
      clang-tools \
      lld \
      lldb \
      libc++-dev \
      libc++abi-dev \
      cmake \
      ninja-build \
      meson \
      pkg-config \
      gdb \
      ccache \
      cppcheck \
      valgrind \
      autoconf \
      automake \
      libtool \
      python3 \
      python3-dev \
      file \
      patch \
      xz-utils \
      unzip \
      wget \
      rsync \
    && rm -rf /var/lib/apt/lists/*

# ---- Shared agent runtime (Node + Claude Code + Codex + Ralph + user + git) ----
ARG CLAUDE_CODE_VERSION=2.1.229
ARG CODEX_VERSION=0.147.0
COPY dockerfiles/common/install-agents.sh /tmp/install-agents.sh
RUN NODE_MAJOR="${NODE_MAJOR}" \
    RALPH_REF="${RALPH_REF}" \
    RALPH_UID="${RALPH_UID}" \
    RALPH_GID="${RALPH_GID}" \
    CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION}" \
    CODEX_VERSION="${CODEX_VERSION}" \
    bash /tmp/install-agents.sh \
    && rm -f /tmp/install-agents.sh

# ---- Conan (C/C++ package manager) via uv-managed tool ----
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && uv --version \
    && uv tool install conan \
    && conan --version

# ---- Cross-toolchain helper (generates CMake toolchain files + Conan profiles) ----
COPY --chmod=0755 dockerfiles/cpp/cross-env.sh /usr/local/bin/cross-env

# ---- Entrypoint (shared with the other variants) ----
COPY --chmod=0755 dockerfiles/common/ralph-entrypoint.sh /usr/local/bin/ralph-entrypoint

# ---- Build-time smoke: compilers work + cross-env generates config ----
RUN <<'SMOKE'
set -eu
tmp="$(mktemp -d)"
cd "${tmp}"
printf '#include <stdio.h>\nint main(void){puts("c-ok");return 0;}\n' >hello.c
printf '#include <iostream>\nint main(){std::cout<<"cpp-ok\\n";return 0;}\n' >hello.cpp
gcc hello.c -o hc_gcc && ./hc_gcc
clang hello.c -o hc_clang && ./hc_clang
g++ hello.cpp -o hx_gpp && ./hx_gpp
clang++ hello.cpp -o hx_clang && ./hx_clang
cmake --version | head -1
ninja --version
meson --version
conan --version
mkdir -p faketc/bin faketc/aarch64-linux-gnu/sysroot
printf '#!/bin/sh\n[ "$1" = "-dumpversion" ] && echo 13 && exit 0\nexit 0\n' >faketc/bin/aarch64-linux-gnu-gcc
chmod +x faketc/bin/aarch64-linux-gnu-gcc
CROSS_TOOLCHAIN_DIR="${tmp}/faketc" cross-env cmake-toolchain - | grep -q 'CMAKE_SYSTEM_PROCESSOR aarch64'
CROSS_TOOLCHAIN_DIR="${tmp}/faketc" cross-env conan-profile - | grep -q 'arch=armv8'
cd /
rm -rf "${tmp}"
echo "cpp smoke OK"
SMOKE

# ---- Workspace ----
RUN mkdir -p /workspace && chown -R ralph:ralph /workspace
WORKDIR /workspace
USER ralph

# ---- Seed a default Conan build profile for the ralph user ----
# A fresh Conan install has no `default` profile, so the documented cross-build
# (`conan install ... -pr:b=default`) fails until `conan profile detect` runs.
# Bake it in as the ralph user (in the default CONAN_HOME at /home/ralph/.conan2)
# so the feedback loop works out of the box. Runs after USER ralph so the profile
# is owned by, and lands in the home of, the runtime user.
RUN conan profile detect --force \
    && conan profile show >/dev/null \
    && echo "conan default profile ready"

ENTRYPOINT ["ralph-entrypoint"]
