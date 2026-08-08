# ralph-sandbox

A Docker-based sandbox for running the [Ralph](https://github.com/snarktank/ralph) autonomous AI agent loop with support for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [OpenAI Codex CLI](https://developers.openai.com/codex/cli) as coding tools.

Ralph is an autonomous agent loop that iteratively implements software features by reading a structured PRD (`prd.json`), selecting the highest-priority incomplete story, implementing it, running quality checks, committing changes, and repeating until all stories pass. Each iteration spawns a fresh AI instance with clean context -- only git history, a learnings file (`progress.txt`), and task statuses carry forward between iterations.

This sandbox wraps Ralph in a hardened Docker container, making it straightforward to point at any project directory and let Ralph work autonomously. Four image variants are provided:

- **`python`** (default) — modern Python tooling (uv, hatch, ruff, pytest, mypy, pyright, coverage) plus SAST (bandit, pip-audit, semgrep).
- **`python-ui`** — everything in `python` plus a headless browser for web-UI e2e evaluation (playwright + chromium). Layered on the `python` image; select it for projects whose checks or agents need to drive a real browser.
- **`crosstool-ng`** — a cross-compilation toolchain build environment built around [crosstool-ng](https://crosstool-ng.github.io/), for producing GCC cross-toolchains.
- **`cpp`** — a native + cross C/C++ application dev environment: GCC **and** Clang, CMake/Ninja/Meson, Conan, gdb/lldb, and clang-tidy/clang-format/cppcheck/valgrind. Can mount a cross toolchain (see [cpp image](#cpp-image)) to build for non-host targets.

All variants bundle the same Claude Code and Codex agents behind an identical runtime contract (entrypoint, `SESSION_RUNNER` dispatch, git/`PROJECT_DIR` handling); they differ only in the pre-installed tooling. Select a variant with `--variant` (see below).

## How It Works

```
ralph-sandbox (Docker container)
  ├─ [default] ralph.sh (orchestration loop from upstream Ralph)
  │    └─ Claude Code CLI or OpenAI Codex CLI (selected via RALPH_TOOL)
  │         └─ Claude / OpenAI (LLM)
  └─ [custom] SESSION_RUNNER script (full control, replaces ralph.sh)
```

Each iteration of the loop:

1. Spawns a fresh Claude Code instance (clean context window)
2. Reads `prd.json` and selects the highest-priority incomplete story
3. Implements the feature in the mounted project
4. Runs quality checks (type-checking, tests)
5. Commits successful changes via git
6. Updates task status in `prd.json`
7. Records learnings to `progress.txt` for future iterations
8. Repeats until all stories pass

## Prerequisites

- Docker and Docker Compose
- A valid Claude Code configuration directory (typically `~/.claude`) with API credentials, **and/or** a valid Codex configuration directory (typically `~/.codex`) with credentials
- A project directory with a `scripts/ralph/prd.json` file (generate one using the `/prd` and `/ralph` Claude Code skills)

## Quick Start

### 1. Build the image

```bash
docker compose build
```

### 2. Prepare your project

Your project needs a `prd.json` file at `<your-project>/scripts/ralph/prd.json` that defines the work for Ralph. The upstream Ralph repo ships with Claude Code skills to help generate this:

1. **Generate a PRD** -- In Claude Code, use the `/prd` skill to create a structured Product Requirements Document from a feature description.
2. **Convert to prd.json** -- Use the `/ralph` skill to convert the PRD into the `prd.json` format that Ralph's loop consumes.

To install the skills, follow the instructions in the [upstream Ralph repository](https://github.com/snarktank/ralph).

Keep stories small and focused -- each should complete within a single context window. Good examples: "Add database migration for X column", "Create Y component", "Add Z API endpoint". Avoid broad stories like "Build entire dashboard".

### 3. Run Ralph

The simplest way is to use the wrapper from anywhere:

```bash
ralph-sandbox
```

To use OpenAI Codex instead of Claude Code:

```bash
ralph-sandbox --tool codex
```

To run the cross-compilation toolchain image instead of the default python image:

```bash
ralph-sandbox --variant crosstool-ng
```

To run the C/C++ dev image, optionally mounting a cross toolchain:

```bash
ralph-sandbox --variant cpp
ralph-sandbox --variant cpp --toolchain-dir ~/x-tools/aarch64-unknown-linux-gnu
```

To run the web-UI image (python plus headless playwright/chromium):

```bash
ralph-sandbox --variant python-ui
```

`--variant` selects which image the wrapper builds/runs (`python` by default, or `python-ui` / `crosstool-ng` / `cpp`). It is independent of `--tool`: every variant supports `claude` and `codex`. See [python-ui image](#python-ui-image), [crosstool-ng image](#crosstool-ng-image) and [cpp image](#cpp-image) for variant-specific guidance.

By default the wrapper:

- uses the current git repository root as `PROJECT_DIR` (or the current directory if you're not in a repo)
- when `--tool claude` is specified, mounts `CLAUDE_CONFIG_DIR` from the environment, falling back to `~/.claude`
- when `--tool codex` is specified, mounts `CODEX_CONFIG_DIR` (or `~/.codex`) into the container
- invokes `docker compose` against this sandbox repo, so you do not need to `cd` here first
- supports running inside an existing linked git worktree by mounting the shared git metadata so `git status`, commits, and branch operations work inside the container

To pass Ralph arguments through:

```bash
ralph-sandbox -- 10
```

To run Ralph from inside an already-created linked git worktree:

```bash
ralph-sandbox --project-dir /path/to/your/project-worktree
```

You can still call Compose directly if you want, but the base `docker-compose.yml` intentionally leaves tool config mounts to the wrapper or an override file:

```bash
PROJECT_DIR=/absolute/path/to/your/project \
docker compose -f docker-compose.yml -f docker-compose.claude.yml up ralph
```

For Claude Code, add an override that mounts your Claude config directory:

```yaml
# docker-compose.claude.yml
services:
  ralph:
    volumes:
      - type: bind
        source: ${CLAUDE_CONFIG_DIR:-${HOME}/.claude}
        target: /claude_config
```

For Codex, use a similar override that mounts `${CODEX_CONFIG_DIR:-${HOME}/.codex}` to `/codex_config`.

Pass iteration count and other arguments after the service name:

```bash
PROJECT_DIR=/absolute/path/to/your/project docker compose run ralph 10
```

### 4. Interactive shell (debugging)

To drop into the container for manual inspection:

```bash
PROJECT_DIR=/absolute/path/to/your/project docker compose run ralph-login
```

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `PROJECT_DIR` | Yes | -- | Absolute path to the project directory on the host |
| `RALPH_TOOL` | No | `claude` | Coding tool to use: `claude` or `codex` |
| `SESSION_RUNNER` | No | -- | Absolute path to a custom runner script inside the container (replaces the built-in Ralph loop) |
| `RALPH_PROMPT_FILE` | No | -- | Path to a custom prompt file (relative to `PROJECT_DIR`). Used by orchestrated mode to pass per-iteration or fixer prompts to the session runner. Falls back to `scripts/ralph/CLAUDE.md` when unset. |
| `CLAUDE_CONFIG_DIR` | No | `~/.claude` | Path to Claude Code configuration directory |
| `CODEX_CONFIG_DIR` | No | `~/.codex` | Path to OpenAI Codex configuration directory |
| `CROSS_TOOLCHAIN_DIR` | No | -- | (cpp) In-container path to a mounted cross toolchain. Set automatically by the wrapper's `--toolchain-dir`; consumed by `cross-env`. |

### Build Arguments

| Argument | Default | Description |
|---|---|---|
| `NODE_MAJOR` | `20` | Node.js major version (base images¹) |
| `RALPH_REF` | `6c53cb0` | Pinned upstream Ralph commit used by default (base images¹) |
| `RALPH_UID` | `1000` | UID for the non-root `ralph` user inside the container (base images¹) |
| `RALPH_GID` | `1000` | GID for the non-root `ralph` group inside the container (base images¹) |
| `CLAUDE_CODE_VERSION` | `2.1.177` | Pinned Claude Code CLI version (base images¹) |
| `CODEX_VERSION` | `0.139.0` | Pinned OpenAI Codex CLI version (base images¹) |
| `CROSSTOOL_NG_VERSION` | `1.28.0` | Pinned crosstool-ng release (crosstool-ng image only) |
| `BASE_IMAGE` | `docker.io/davesnowdon/ralph-sandbox:python` | (python-ui only) The python image that python-ui layers `FROM`. See [python-ui image](#python-ui-image) for the two-tier resolution. |
| `PLAYWRIGHT_VERSION` | `1.62.0` | (python-ui only) Pinned playwright CLI version; the baked chromium revision derives from it. Upgrades are deliberate and validated by the python-ui browser smoke test. |

¹ These apply when a **base** image (`python`, `crosstool-ng`, `cpp`) is built. **python-ui** starts `FROM` an already-built `BASE_IMAGE`, so passing them to a python-ui build has no effect — they are inherited from, and fixed by, the selected `BASE_IMAGE` (with the published default: the published image's values, e.g. UID/GID 1000). To customize them for python-ui, build a local python base first — see [python-ui image](#python-ui-image).

To pin Ralph to a specific version:

```yaml
# docker-compose.yml
args:
  RALPH_REF: "a1b2c3d"  # commit SHA
```

## Custom Session Runner

By default, the container runs the built-in Ralph loop (`ralph.sh`). External orchestrators can replace this with a custom runner script by setting the `SESSION_RUNNER` environment variable. This allows ralph-sandbox to serve as a general-purpose agentic coding sandbox with all tools pre-installed.

### Interface contract

The stable container path for a custom runner is `/run/ralph/session-runner.sh`. The CLI wrapper mounts the host script there automatically.

When `SESSION_RUNNER` is set, the entrypoint:

1. Validates `PROJECT_DIR` (exists, is a git repo, git is functional)
2. Adds `PROJECT_DIR` to git's `safe.directory`
3. Validates the runner script exists and is executable
4. Execs the runner with all remaining command-line arguments

The custom runner **can assume**:

- Working directory is `PROJECT_DIR`
- Git is configured and functional
- Shared CLI tools are available on **all** variants: `claude`, `codex`, `node`, `bash`, `git`, `make`, `jq`
  - the **python** image adds: `python`, `uv`, `hatch`, `ruff`, `pytest`, `mypy`, `pyright`, `coverage`, `bandit`, `pip-audit`, `semgrep`
  - the **python-ui** image adds everything in **python** plus `playwright` (headless chromium baked at `PLAYWRIGHT_BROWSERS_PATH=/opt/playwright`)
  - the **crosstool-ng** image adds: `ct-ng`, `gcc`, `g++`, `python3`, and the crosstool-ng host build toolchain (`bison`, `flex`, `gawk`, `makeinfo`, `libtool`, …)
  - the **cpp** image adds: `gcc`/`g++`, `clang`/`clang++`, `cmake`, `ninja`, `meson`, `pkg-config`, `conan`, `gdb`/`lldb`, `clang-tidy`, `clang-format`, `cppcheck`, `valgrind`, `ccache`, and `cross-env`
- All environment variables (`PROJECT_DIR`, `RALPH_TOOL`, config dirs) are available but `RALPH_TOOL` and tool config dirs are **not validated** -- the custom runner decides what it needs

The custom runner **receives**:

- Raw command-line arguments (no `--tool` stripping)
- Full control over execution -- the built-in Ralph loop is not involved

### Mandatory mounts in custom-runner mode

| Mount | Target | Description |
|---|---|---|
| Project directory | `PROJECT_DIR` (same path as host) | The git repo to work in |
| Runner script | `/run/ralph/session-runner.sh` | The custom runner to execute |

Tool config mounts (`/claude_config`, `/codex_config`) are **optional** -- only needed if your runner invokes Claude Code or Codex.

### Usage via the CLI wrapper

```bash
bin/ralph-sandbox --session-runner ./my-runner.sh --project-dir /path/to/project -- arg1 arg2
```

The wrapper resolves the script path, mounts it read-only into the container at `/run/ralph/session-runner.sh`, and sets `SESSION_RUNNER` automatically.

### Usage via docker compose

```bash
PROJECT_DIR=/absolute/path/to/project \
SESSION_RUNNER=/run/ralph/session-runner.sh \
docker compose run --rm \
  -v /path/to/runner.sh:/run/ralph/session-runner.sh:ro \
  ralph arg1 arg2
```

### Example: external orchestrator integration

An external orchestrator (e.g. "ralph++") might:

```bash
# 1. Create a worktree and prepare config
git worktree add /tmp/feature-branch feature-branch

# 2. Generate a session runner script
cat > /tmp/session-runner.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
# Custom workflow: apply config, run claude with specific instructions, etc.
cd "${PROJECT_DIR}"
claude --print "Implement the feature described in TASK.md"
SCRIPT
chmod +x /tmp/session-runner.sh

# 3. Run the sandbox with the custom runner
bin/ralph-sandbox \
  --session-runner /tmp/session-runner.sh \
  --project-dir /tmp/feature-branch
```

## CI/CD

Each base image variant has its own build workflow (`publish-python.yml`, `publish-crosstool-ng.yml`, `publish-cpp.yml`); **python-ui** is built and published by a chained job inside `publish-python.yml`, since it layers `FROM` the python image (on release it pins the just-pushed python base by digest; on pull requests it validates against the published base — the clean-host contract). Pull requests build the affected image(s) to validate they still compile. Docker Hub pushes only happen from GitHub Releases:

- the **python** image publishes `davesnowdon/ralph-sandbox:python` and `:<release-tag>`
- the **python-ui** image publishes `davesnowdon/ralph-sandbox:python-ui` and `:python-ui-<release-tag>`
- the **crosstool-ng** image publishes `davesnowdon/ralph-sandbox:crosstool-ng` and `:crosstool-ng-<release-tag>`
- the **cpp** image publishes `davesnowdon/ralph-sandbox:cpp` and `:cpp-<release-tag>`

There is no Docker Hub `:latest` tag — with more than one image variant it would be ambiguous. Repo scripts and the compose default use the local `ralph-sandbox:python` tag. `make tag` additionally stamps a local `ralph-sandbox:latest` alias, kept only for backward-compatibility with external local scripts that still reference it.

`make check` covers **every** image variant by default — it lints the shell files once, runs the static compose-config contract tests (`tests/test-compose-config.sh`: `shm_size` on both services, `BASE_IMAGE` passthrough semantics), then builds each image and runs the entrypoint integration suite against it. Pass `VARIANT=<name>` to scope a run to a single image; CI uses that to fan the variants out across a matrix (`make check VARIANT=python`, `VARIANT=python-ui`, `VARIANT=crosstool-ng`, `VARIANT=cpp`). The same fan-out applies to `make docker-build`, `make test`, `make tag`, and `make push`.

## Container Details

### What's included

Shared across all variants (installed by `dockerfiles/common/install-agents.sh`):

- **Node.js 20** (runtime for the agent CLIs)
- **Claude Code CLI** (`@anthropic-ai/claude-code`)
- **OpenAI Codex CLI** (`@openai/codex`)
- **Upstream Ralph** (`ralph.sh`) and the shared entrypoint (`dockerfiles/common/ralph-entrypoint.sh`)
- **make**, **git**, **jq**

**python** image (default — Docker Hub `davesnowdon/ralph-sandbox:python`; local build tagged `ralph-sandbox:python`, plus a `ralph-sandbox:latest` compat alias):

- **Python 3.12** (slim base)
- **Python tooling**: uv, hatch, ruff, pytest, mypy, pyright, coverage
- **SAST / security tooling**: bandit, pip-audit, semgrep

**python-ui** image (`davesnowdon/ralph-sandbox:python-ui`) — layered `FROM` the python image, adding:

- **Headless browser e2e**: playwright CLI (pinned via `PLAYWRIGHT_VERSION`) + chromium (with OS deps), baked at the fixed non-`$HOME` path `PLAYWRIGHT_BROWSERS_PATH=/opt/playwright` so per-run home/config mounts can't shadow it. Headless only — no X/VNC.

Kept separate from `python` so pure-Python projects don't carry the ~700MB chromium + X11-library tail. See [python-ui image](#python-ui-image) for its base-image and playwright contracts.

**crosstool-ng** image (`davesnowdon/ralph-sandbox:crosstool-ng`):

- **Debian bookworm** (slim base)
- **crosstool-ng** (`ct-ng`) for building GCC cross-compilation toolchains
- **Host build toolchain**: build-essential (gcc/g++/make), autoconf, automake, libtool, bison, flex, gperf, gawk, texinfo/makeinfo, help2man, ncurses, python3, meson, ninja, plus the archive/util deps crosstool-ng needs

**cpp** image (`davesnowdon/ralph-sandbox:cpp`):

- **Debian trixie** (slim base) — GCC 14 and Clang 19 from the distro
- **Build systems**: CMake, Ninja, Meson, Make, autotools, pkg-config
- **Package manager**: Conan 2
- **Debug + analysis**: gdb, lldb, clang-tidy, clang-format, cppcheck, valgrind, ccache
- **Cross-compilation**: `cross-env` helper + mountable toolchain (see below)

### python-ui image

**Projects declare their own playwright.** The image deliberately does **not** provide an importable Python `playwright` library — the CLI is an isolated uv tool, so `python -c 'import playwright'` fails by design. A consuming project declares playwright as its own (dev) dependency and `uv sync`s it in-tree; the image contributes the baked browser revision, the browser OS deps, and the standalone CLI.

**Version skew needs an explicit browser install.** Installing a playwright package does **not** download a browser: browser builds are keyed to the playwright version, and only the `PLAYWRIGHT_VERSION` revision is baked. A project pinning any **other** version must run `uv run playwright install chromium` as part of its environment setup or e2e command (e.g. the first step of a `make e2e` target) — the command no-ops when the matching revision is already present, and it works in-container because egress exists and `/opt/playwright` is writable by the `ralph` user. The baked chromium serves the `PLAYWRIGHT_VERSION` common case download-free. Note the limit: that command runs as `ralph` and installs **browser files only** — it cannot add system packages (those are root-installed at build time via `--with-deps`, keyed to `PLAYWRIGHT_VERSION`), so the pinned version must stay compatible with the baked OS dependencies. Nearby versions are likely fine (1.61.0 verified against the 1.62.0 deps); substantially older or newer versions are not guaranteed — for those, rebuild the image with a matching `PLAYWRIGHT_VERSION` build-arg.

**Two-tier base resolution.** `dockerfiles/python-ui/Dockerfile` layers `FROM ${BASE_IMAGE}`:

- The **default** is the published `docker.io/davesnowdon/ralph-sandbox:python`, so clean-host builds — `bin/ralph-sandbox --variant python-ui --build`, a plain `docker build`, CI PR validation — resolve by pulling the published base.
- The **make targets** (`make check VARIANT=python-ui` etc.) build the python base from the current checkout first and pass `--build-arg BASE_IMAGE=ralph-sandbox:python-test`, so local builds and CI test the source tree, not the last release. `docker-compose.yml` passes `BASE_IMAGE` through from the environment for the same purpose (unset ⇒ the published default applies).

**Inherited build arguments are fixed by the base.** The agent/base build args (`NODE_MAJOR`, `RALPH_REF`, `RALPH_UID`/`RALPH_GID`, `CLAUDE_CODE_VERSION`, `CODEX_VERSION`) only take effect when a *base* image is built; a python-ui build starts `FROM` the already-built `BASE_IMAGE`, so they cannot affect it. With the published default they are fixed at the published image's values — notably the `ralph` user stays UID/GID 1000, so on a host whose user is not 1000 a bind-mounted project may not be writable in-container. To customize, build a local python base with the desired args first, then point `BASE_IMAGE` at it:

```bash
docker build -f dockerfiles/python/Dockerfile \
  --build-arg RALPH_UID="$(id -u)" --build-arg RALPH_GID="$(id -g)" \
  -t ralph-sandbox:python-custom .
BASE_IMAGE=ralph-sandbox:python-custom bin/ralph-sandbox --variant python-ui --build
```

**/dev/shm.** Chromium can exhaust Docker's default 64MB `/dev/shm` under real e2e load, so the compose services set a bounded `shm_size: 1gb` (not `ipc: host` — this is a hardened sandbox).

### crosstool-ng image

The crosstool-ng image builds GCC cross-compilation toolchains with [`ct-ng`](https://crosstool-ng.github.io/docs/). A few things to know:

- **Non-root by design.** crosstool-ng refuses to run `ct-ng build` as root. The container already runs as the non-root `ralph` user, so builds work without the experimental `CT_ALLOW_BUILD_AS_ROOT` override.
- **Persist output and the source cache under `PROJECT_DIR`.** `ct-ng build` writes the finished toolchain to `CT_PREFIX_DIR` and downloads component tarballs (gcc, binutils, glibc, gmp, mpfr, mpc, isl) into a cache. Point both at paths inside the bind-mounted project so they survive the container:

  ```bash
  # inside the container (e.g. from a custom session runner)
  export CT_PREFIX_DIR="${PROJECT_DIR}/x-tools"
  export CT_LOCAL_TARBALLS_DIR="${PROJECT_DIR}/.ct-ng-cache"
  ct-ng aarch64-unknown-linux-gnu   # pick a sample config
  ct-ng build
  ```

- **Network egress is required** during a build to download component tarballs, unless you pre-seed `CT_LOCAL_TARBALLS_DIR` (e.g. via `ct-ng source`).
- **Builds are slow and disk-heavy** — a single toolchain can take many minutes and consume gigabytes; building all samples can take a day or more.

### cpp image

The `cpp` image is a native + cross C/C++ application dev environment. For host builds, just use `gcc`/`clang`/`cmake`/`conan` as normal. It pairs a compiler with a feedback loop (clang-tidy/clang-format/cppcheck/gdb) the way the python image pairs one with ruff/mypy/pytest.

**Cross-compiling for another target.** Mount a prebuilt cross toolchain — one produced by the `crosstool-ng` image, or any existing GCC toolchain (`bin/<tuple>-gcc` layout) — with `--toolchain-dir`. The wrapper mounts it read-only at its host path and sets `CROSS_TOOLCHAIN_DIR`; the `cross-env` helper turns it into ready-to-use build config:

```bash
ralph-sandbox --variant cpp --toolchain-dir ~/x-tools/aarch64-unknown-linux-gnu
# then, inside the container:
cross-env info                                   # detected tuple / versions / next steps
eval "$(cross-env env)"                           # toolchain on PATH + CC/CXX/AR/...
cross-env cmake-toolchain build/cross.cmake
cmake -S . -B build --toolchain build/cross.cmake && cmake --build build
# or with Conan:
cross-env conan-profile build/host.profile
conan install . -pr:b=default -pr:h=build/host.profile --build=missing
```

Notes:
- The toolchain is mounted at its **original host path** (not relocated) — crosstool-ng toolchains are not reliably relocatable. If the toolchain lives under `PROJECT_DIR` (e.g. built at `${PROJECT_DIR}/x-tools` by the crosstool-ng image) it is already mounted; `--toolchain-dir` still sets `CROSS_TOOLCHAIN_DIR` and skips the redundant mount.
- A trixie-based cpp image can run bookworm-built crosstool-ng toolchains (glibc is backward-compatible).
- `cross-env`'s Conan arch mapping is best-effort for common tuples (aarch64/arm/x86_64/riscv64); edit the generated profile if your target differs.
- A default Conan build profile is pre-seeded in the image (via `conan profile detect`), so `-pr:b=default` works out of the box.
- Point `CONAN_HOME` under `PROJECT_DIR` (e.g. `export CONAN_HOME="${PROJECT_DIR}/.conan2"`) to persist the Conan cache across container runs. If you point it at a fresh directory, run `conan profile detect` once there to recreate the default profile.

### Security

The container runs with a non-root `ralph` user and applies the following security constraints:

- All Linux capabilities dropped (`cap_drop: ALL`)
- No privilege escalation (`no-new-privileges`)
- Project directory is bind-mounted (not copied into the image)
- Secrets are never baked into the image

### Tool enforcement

The entrypoint wrapper strips any user-provided `--tool` flags and injects `--tool $RALPH_TOOL`, ensuring the sandbox uses the configured tool (defaulting to `claude`). Set `RALPH_TOOL=codex` to use OpenAI Codex instead. The wrapper script's `--tool` flag sets this automatically.

### State files

Ralph stores its working state in `<project>/scripts/ralph/`:

| File | Purpose |
|---|---|
| `ralph.sh` | Copied from upstream Ralph at container start |
| `CLAUDE.md` | Prompt template for Claude Code, copied from upstream |
| `prd.json` | User stories and completion status (generated via `/prd` and `/ralph` skills) |
| `progress.txt` | Append-only log of learnings across iterations |

If you do not want the copied runtime files tracked in your project, add these entries to your project's `.gitignore`:

```gitignore
scripts/ralph/ralph.sh
scripts/ralph/CLAUDE.md
```

## Tips

- **Write an AGENTS.md** (or `CLAUDE.md`) in your project root. Ralph's AI instances read these files automatically, so documenting project conventions, patterns, and gotchas improves quality across iterations.
- **Keep stories small.** Each story should be completable in a single AI context window. If a story is too broad, Ralph may produce partial implementations that compound errors.
- **Ensure feedback loops exist.** Type-checking, tests, and linting help Ralph catch its own mistakes. Projects without automated checks will see lower quality output.
- **Review commits between runs.** Ralph commits after each successful iteration. Use `git log` and `git diff` to review what changed.

## License

This project is licensed under the [MIT License](LICENSE).
