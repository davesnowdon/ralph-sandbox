# AGENTS

## Repo Purpose

`ralph-sandbox` packages Ralph into a Docker sandbox with:

- a default built-in runner based on upstream `ralph.sh`
- Claude Code and OpenAI Codex CLI installed in every image variant
- two image variants, selected via `VARIANT` (Makefile) / `--variant` (wrapper):
  - `python` (default): Python tooling (`uv`, `hatch`, `ruff`, `pytest`, `mypy`, `pyright`, `coverage`) plus SAST (`bandit`, `pip-audit`, `semgrep`)
  - `crosstool-ng`: a crosstool-ng cross-compilation toolchain build environment (`ct-ng` plus the host build toolchain)
- a supported custom-runner mode via `SESSION_RUNNER`

Key files:

- `dockerfiles/common/ralph-entrypoint.sh`: the shared entrypoint contract (used by both variants)
- `dockerfiles/common/install-agents.sh`: shared agent-runtime install (Node, Claude Code, Codex, Ralph, non-root user, git config)
- `dockerfiles/python/Dockerfile`: python image build
- `dockerfiles/crosstool-ng/Dockerfile`: crosstool-ng image build
- `docker-compose.yml`: base runtime contract (variant-selectable via `SANDBOX_IMAGE` / `SANDBOX_DOCKERFILE`)
- `bin/ralph-sandbox`: local wrapper that prepares mounts and env
- `tests/test-entrypoint.sh`: integration test for entrypoint behavior (runs against any variant)
- `README.md`: user-facing contract and examples

## Runtime Contract

The sandbox supports two execution modes:

1. Default mode: run the built-in Ralph workflow.
2. Custom mode: set `SESSION_RUNNER` and run a caller-provided script instead.

Clients orchestrating this sandbox should expect and adhere to the following:

- `PROJECT_DIR` must be set to an absolute path and mounted into the container.
- `PROJECT_DIR` must be a functional git working tree inside the container.
- Linked worktrees require shared git metadata to be mounted so git works in-container.
- The stable in-container path for a custom runner is `/run/ralph/session-runner.sh`.
- If `SESSION_RUNNER` is set, the target script must exist in the container and be executable.
- In custom-runner mode, the entrypoint validates `PROJECT_DIR`, marks it as a git safe directory, validates `SESSION_RUNNER`, and then `exec`s the runner with the original command-line arguments.
- In custom-runner mode, callers should not assume the built-in Ralph loop runs at all.
- Tool config mounts are only required when the selected workflow actually uses them:
  - `/claude_config` for Claude Code
  - `/codex_config` for Codex

Custom runner assumptions:

- The working directory should be `PROJECT_DIR`.
- Git should be usable from `PROJECT_DIR`.
- The installed tools in the image are available on `PATH`.
- The runner receives raw arguments; the sandbox should not rewrite them in custom-runner mode.

## Change Rules For Agents

Agents making changes in this repo must preserve the documented contract across the Dockerfiles, the shared `dockerfiles/common/` scripts, compose config, wrapper script, tests, and `README.md`. The entrypoint and agent-runtime install are shared by both variants — a change to `dockerfiles/common/**` affects every image, so validate all variants.

When changing container startup, mounts, env vars, runner dispatch, or docs for orchestrators:

- update all affected surfaces together
- keep the default built-in runner working
- keep custom-runner mode explicit and documented
- prefer stable container-side paths over host-specific paths in documented interfaces
- do not silently introduce new required mounts or env vars without documenting them

If behavior changes, update `README.md` and `tests/test-entrypoint.sh` in the same change.

## Tooling Baseline

This repo uses shell- and Docker-focused validation rather than a Python
package workflow.

Primary commands (the default `VARIANT` is `python`; set `VARIANT=crosstool-ng`
to target the other image):

```bash
make lint
make fmt-check
make test                       # builds + tests the python image
make check                      # lint + fmt-check + test (python)
make check VARIANT=crosstool-ng # same, for the crosstool-ng image
```

`make check` currently runs:

- `shellcheck` on `bin/ralph-sandbox`, `tests/test-entrypoint.sh`, and the shared `dockerfiles/common/*.sh` scripts
- `shfmt -d` formatting verification for those shell files
- Docker image build validation for the selected `VARIANT`
- `tests/test-entrypoint.sh` against the built image

## Verification

Before a change can be considered done, run:

```bash
make check
```

At minimum, this is required for changes touching any of:

- `dockerfiles/common/ralph-entrypoint.sh` (shared entrypoint — run **both** variants)
- `dockerfiles/common/install-agents.sh` (shared install — run **both** variants)
- `dockerfiles/python/Dockerfile`
- `dockerfiles/crosstool-ng/Dockerfile`
- `docker-compose.yml`
- `docker-compose.claude.yml`
- `docker-compose.codex.yml`
- `bin/ralph-sandbox`
- `tests/test-entrypoint.sh`
- `README.md` sections describing runtime behavior

For a change to the shared `dockerfiles/common/**` scripts, run `make check`
**and** `make check VARIANT=crosstool-ng` so both images are validated.

If the change alters the contract consumed by `ralph-plus-plus`, also run the
relevant `ralph-plus-plus` checks and a manual cross-repo integration pass.
