# ralph-sandbox

A Docker-based sandbox for running the [Ralph](https://github.com/snarktank/ralph) autonomous AI agent loop with support for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [OpenAI Codex CLI](https://developers.openai.com/codex/cli) as coding tools.

Ralph is an autonomous agent loop that iteratively implements software features by reading a structured PRD (`prd.json`), selecting the highest-priority incomplete story, implementing it, running quality checks, committing changes, and repeating until all stories pass. Each iteration spawns a fresh AI instance with clean context -- only git history, a learnings file (`progress.txt`), and task statuses carry forward between iterations.

This sandbox wraps Ralph in a hardened Docker container with modern Python tooling pre-installed, making it straightforward to point at any project directory and let Ralph work autonomously.

## How It Works

```
ralph-sandbox (Docker container)
  └─ ralph.sh (orchestration loop from upstream Ralph)
       └─ Claude Code CLI or OpenAI Codex CLI (selected via RALPH_TOOL)
            └─ Claude / OpenAI (LLM)
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

By default the wrapper:

- uses the current git repository root as `PROJECT_DIR` (or the current directory if you're not in a repo)
- uses `CLAUDE_CONFIG_DIR` from the environment, falling back to `~/.claude`
- when `--tool codex` is specified, mounts `CODEX_CONFIG_DIR` (or `~/.codex`) into the container
- invokes `docker compose` against this sandbox repo, so you do not need to `cd` here first
- detects git worktrees and mounts the shared git metadata so `git status`, commits, and branch operations work inside the container

To pass Ralph arguments through:

```bash
ralph-sandbox -- 10
```

If you run the wrapper from inside a pre-existing git worktree, the sandbox automatically detects and mounts the shared git metadata so that `git status`, commits, and branch operations work inside the container. No extra flags needed.

You can still call Compose directly if you want:

```bash
PROJECT_DIR=/absolute/path/to/your/project docker compose up ralph
```

Or with an explicit Claude config path:

```bash
PROJECT_DIR=/absolute/path/to/your/project \
CLAUDE_CONFIG_DIR=$HOME/.claude \
docker compose up ralph
```

To use Codex via Compose directly, you need to mount the Codex config directory yourself via an override file, since the base `docker-compose.yml` does not include the Codex mount (to avoid failing when `~/.codex` doesn't exist):

```bash
PROJECT_DIR=/absolute/path/to/your/project \
RALPH_TOOL=codex \
docker compose -f docker-compose.yml -f docker-compose.codex.yml up ralph
```

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
| `CLAUDE_CONFIG_DIR` | No | `~/.claude` | Path to Claude Code configuration directory |
| `CODEX_CONFIG_DIR` | No | `~/.codex` | Path to OpenAI Codex configuration directory |

### Build Arguments

| Argument | Default | Description |
|---|---|---|
| `NODE_MAJOR` | `20` | Node.js major version |
| `RALPH_REF` | `main` | Git ref for the upstream Ralph repository (use a commit SHA for reproducibility) |
| `RALPH_UID` | `1000` | UID for the non-root `ralph` user inside the container |
| `RALPH_GID` | `1000` | GID for the non-root `ralph` group inside the container |

To pin Ralph to a specific version:

```yaml
# docker-compose.yml
args:
  RALPH_REF: "a1b2c3d"  # commit SHA
```

## Container Details

### What's included

- **Python 3.12** (slim base)
- **Node.js 20** (for Claude Code CLI)
- **Claude Code CLI** (`@anthropic-ai/claude-code`)
- **OpenAI Codex CLI** (`@openai/codex`)
- **Python tooling**: uv, hatch, ruff, pytest, mypy

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
