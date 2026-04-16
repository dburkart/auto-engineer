# Build & Run Playbook — auto-engineer

## Project type

This is a template/skill-only project. There is no compiled code, no build step, and no test suite. The project consists of:

- Claude Code skill definitions (`.claude/skills/*/SKILL.md`)
- Template files for seeding other projects (`templates/`)
- Shell scripts for Docker-based autonomous execution (`scripts/`)
- A Dockerfile for containerized runs

## "Building"

No build step required. To verify the Docker image builds:

```sh
scripts/sandbox.sh --build-only
```

## Running

- **Sandbox mode**: `scripts/sandbox.sh /some-skill` — builds and runs the container
- **Auto-engineer loop**: `scripts/auto-engineer.sh` — convenience wrapper for the autonomous loop
- **Local (no container)**: invoke skills directly via Claude Code CLI

## Dependencies

- Docker (for containerized execution)
- `gh` CLI (for GitHub operations)
- Claude Code CLI (installed in the container, or locally)

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `GITHUB_TOKEN` | Yes (in container) | GitHub personal access token for `gh` |
| `ANTHROPIC_API_KEY` | No | Only needed if using API key auth instead of OAuth |
| `GIT_AUTHOR_NAME` | No | Defaults to `auto-engineer` |
| `GIT_AUTHOR_EMAIL` | No | Defaults to `noreply@anthropic.com` |
| `PROJECT_REPO` | No | Defaults to `dburkart/auto-engineer` |
