# ralph-sandbox

A Docker-based sandbox for running the [Ralph](https://github.com/snarktank/ralph) autonomous AI agent loop with support for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [OpenAI Codex CLI](https://developers.openai.com/codex/cli) as coding tools.

Ralph is an autonomous agent loop that iteratively implements software features by reading a structured PRD (`prd.json`), selecting the highest-priority incomplete story, implementing it, running quality checks, committing changes, and repeating until all stories pass. Each iteration spawns a fresh AI instance with clean context -- only git history, a learnings file (`progress.txt`), and task statuses carry forward between iterations.

This sandbox wraps Ralph in a hardened Docker container, making it straightforward to point at any project directory and let Ralph work autonomously. Two image variants are provided:

- **`python`** (default) — modern Python tooling (uv, hatch, ruff, pytest, mypy, pyright, coverage) plus SAST (bandit, pip-audit, semgrep).
- **`crosstool-ng`** — a cross-compilation toolchain build environment built around [crosstool-ng](https://crosstool-ng.github.io/), for producing GCC cross-toolchains.

Both variants bundle the same Claude Code and Codex agents behind an identical runtime contract (entrypoint, `SESSION_RUNNER` dispatch, git/`PROJECT_DIR` handling); they differ only in the pre-installed tooling. Select a variant with `--variant` (see below).

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

`--variant` selects which image the wrapper builds/runs (`python` by default, or `crosstool-ng`). It is independent of `--tool`: both variants support `claude` and `codex`. See [crosstool-ng image](#crosstool-ng-image) for toolchain-build guidance.

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

### Build Arguments

| Argument | Default | Description |
|---|---|---|
| `NODE_MAJOR` | `20` | Node.js major version (both variants) |
| `RALPH_REF` | `6c53cb0` | Pinned upstream Ralph commit used by default (both variants) |
| `RALPH_UID` | `1000` | UID for the non-root `ralph` user inside the container (both variants) |
| `RALPH_GID` | `1000` | GID for the non-root `ralph` group inside the container (both variants) |
| `CLAUDE_CODE_VERSION` | `2.1.177` | Pinned Claude Code CLI version (both variants) |
| `CODEX_VERSION` | `0.139.0` | Pinned OpenAI Codex CLI version (both variants) |
| `CROSSTOOL_NG_VERSION` | `1.28.0` | Pinned crosstool-ng release (crosstool-ng image only) |

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
- Shared CLI tools are available on **both** variants: `claude`, `codex`, `node`, `bash`, `git`, `make`, `jq`
  - the **python** image adds: `python`, `uv`, `hatch`, `ruff`, `pytest`, `mypy`, `pyright`, `coverage`, `bandit`, `pip-audit`, `semgrep`
  - the **crosstool-ng** image adds: `ct-ng`, `gcc`, `g++`, `python3`, and the crosstool-ng host build toolchain (`bison`, `flex`, `gawk`, `makeinfo`, `libtool`, …)
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

Each image variant has its own build workflow (`publish-python.yml`, `publish-crosstool-ng.yml`). Pull requests build the affected image(s) to validate they still compile. Docker Hub pushes only happen from GitHub Releases:

- the **python** image publishes `davesnowdon/ralph-sandbox:python` and `:<release-tag>`
- the **crosstool-ng** image publishes `davesnowdon/ralph-sandbox:crosstool-ng` and `:crosstool-ng-<release-tag>`

There is no Docker Hub `:latest` tag — with more than one image variant it would be ambiguous. The local build is still tagged `ralph-sandbox:latest` (via `make tag`) so local tooling and the compose default keep working.

`make check` runs in CI across both variants (`make check VARIANT=python` and `VARIANT=crosstool-ng`): it lints the shell files and runs the entrypoint integration suite against each image.

## Container Details

### What's included

Shared across both variants (installed by `dockerfiles/common/install-agents.sh`):

- **Node.js 20** (runtime for the agent CLIs)
- **Claude Code CLI** (`@anthropic-ai/claude-code`)
- **OpenAI Codex CLI** (`@openai/codex`)
- **Upstream Ralph** (`ralph.sh`) and the shared entrypoint (`dockerfiles/common/ralph-entrypoint.sh`)
- **make**, **git**, **jq**

**python** image (default — Docker Hub `davesnowdon/ralph-sandbox:python`; local build tagged `ralph-sandbox:latest`):

- **Python 3.12** (slim base)
- **Python tooling**: uv, hatch, ruff, pytest, mypy, pyright, coverage
- **SAST / security tooling**: bandit, pip-audit, semgrep

**crosstool-ng** image (`davesnowdon/ralph-sandbox:crosstool-ng`):

- **Debian bookworm** (slim base)
- **crosstool-ng** (`ct-ng`) for building GCC cross-compilation toolchains
- **Host build toolchain**: build-essential (gcc/g++/make), autoconf, automake, libtool, bison, flex, gperf, gawk, texinfo/makeinfo, help2man, ncurses, python3, meson, ninja, plus the archive/util deps crosstool-ng needs

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
