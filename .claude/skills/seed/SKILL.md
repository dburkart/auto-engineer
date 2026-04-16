---
name: seed
description: Seed the auto-engineer SDLC toolkit into a project. Asks for the target project path, detects the tech stack and GitHub configuration, collects any missing values interactively, then writes customized skill files and Docker infrastructure into that project. Use when the user says "seed a project", "set up auto-engineer", "install the loop", or invokes `/seed`.
argument-hint: [<target-path>]
---

# seed

Configures the auto-engineer toolkit for a target project. Always runs from within this auto-engineer repo — it never copies itself. Reads templates from `templates/` (relative to this repo's root), substitutes `{{PLACEHOLDER}}` values, and writes the results into the target project.

**Does not touch any pre-existing `.claude/` directory in the target.** Skills are written into `.claude/skills/` but only for skill names that don't already exist there. `settings.local.json` and `.claude/.gitignore` are only created if absent.

## When to invoke

- User says "seed a project", "set up auto-engineer", "configure the loop", or `/seed`.
- Accepts an optional positional argument: the path to the target project.
- If no path is given as an argument, ask for it as the **first** action (before any detection).

---

## Step 0 — Get the target path

If the user did not provide a path as an argument, ask:

> "What's the path to the project you want to seed? (absolute or relative to your home directory)"

Resolve to an absolute path. Verify the directory exists. If it doesn't exist, ask whether to create it. Abort with a clear error if the user declines creation and the path is missing.

All subsequent file reads and writes use `<target>/` as the root.

---

## Phase 1 — Detect project state

`cd` into the target directory for all detection commands. Determine whether this is an **existing project** (has `.git`) or a **new project** (no git history yet).

### Existing project detection

Run these in parallel from `<target>/`:

```sh
# GitHub owner/repo
gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"'

# Current authenticated user (for assignee default)
gh api user --jq .login

# Existing labels
gh label list --json name,description --limit 100

# CI workflows
ls .github/workflows/*.yml 2>/dev/null || true
```

Also scan for tech stack indicators by checking for file existence in `<target>/`:

| File | Stack | Default commands |
|---|---|---|
| `Cargo.toml` | Rust | build: `cargo build`, test: `cargo test`, format: `cargo fmt --all`, lint-fix: `cargo clippy --fix --allow-dirty --allow-staged && cargo fmt --all` |
| `go.mod` | Go | build: `go build ./...`, test: `go test ./...`, format: `gofmt -w .`, lint-fix: `golangci-lint run --fix` |
| `package.json` | Node/TS | build: `npm run build`, test: `npm test`, format: `npm run format`, lint-fix: `npm run lint --fix` |
| `pyproject.toml` or `setup.py` | Python | build: `python -m build`, test: `pytest`, format: `ruff format .`, lint-fix: `ruff check --fix .` |
| `Makefile` | Make-based | Read the Makefile for targets: look for `build`, `test`, `lint`, `format` |
| None of the above | Unknown | Will need to prompt user |

If a `Makefile` is present with standard targets, prefer `make <target>` over language-specific commands.

### Existing `.claude/` detection

Check what already exists in `<target>/.claude/skills/`:

```sh
ls <target>/.claude/skills/ 2>/dev/null
```

Note which skill names are already present — those will be skipped during write.

### Review bot detection

Check recent PRs for known review bot logins:

```sh
gh pr list --state merged --limit 5 --json number --jq '.[].number' \
  | xargs -I{} gh api "repos/{owner}/{repo}/issues/{}/comments" \
      --jq '[.[].user.login] | .[]' 2>/dev/null \
  | sort -u
```

Known bots: `coderabbitai`, `coderabbitai[bot]`, `greptile-apps`, `greptile-bot`, `github-advanced-security[bot]`.

If detection is ambiguous — greenfield repo, no merged PRs to inspect, or the scan turns up nothing — **do not silently default**. Ask the user directly:

> "I couldn't detect any review bots on this repo. Do you have a review bot (CodeRabbit, Greptile, GHAS, etc.) configured, or should the auto-engineer self-review PRs via a subagent expert?"

Record the answer. Set `REVIEW_BOT_LOGINS` to the confirmed bots (pipe-separated) or leave it empty if none.

### CI test detection

Also determine whether the repo runs automated tests in CI. Check for:

- `.github/workflows/*.yml` containing any of: `test`, `pytest`, `cargo test`, `go test`, `npm test`, `jest`, `vitest`
- Non-workflow CI configs: `.circleci/config.yml`, `.gitlab-ci.yml`, `azure-pipelines.yml`

If no CI test job is found (or the repo is greenfield with no workflows at all), record this — it feeds the self-review decision below.

### Self-review decision

If **any** of the following are true, enable the SDLC self-review section for this project:

- No review bots configured (per the question above), **or**
- No CI test job detected, **or**
- Greenfield repo (no merged PRs, no `.git` history beyond the initial commit)

When enabling self-review, ask the user:

> "What kind of expert reviewer should the auto-engineer impersonate for self-reviews? (e.g. 'senior Go backend engineer', 'security-focused Python reviewer', 'React accessibility reviewer')"

Use their answer for `SELF_REVIEW_EXPERT`. Set `SELF_REVIEW_REASON` to the triggering condition (`"review bots"`, `"CI tests"`, or `"review bots or CI tests"`).

---

## Phase 2 — Collect configuration

### For existing projects

Present detected values and ask the user to confirm or override using `AskUserQuestion`:

**Group A — Identity** (auto-detected, confirm):
- `GITHUB_OWNER` / `GITHUB_REPO` (from `gh repo view`)
- `GITHUB_USER` (from `gh api user`)

**Group B — Build commands** (auto-detected from tech stack, confirm or override):
- `BUILD_CMD`
- `TEST_CMD`
- `FORMAT_CMD` (for auto-fix on format CI failures)
- `LINT_FIX_CMD` (full lint-fix command, e.g. linter + formatter together)
- `FORMAT_FIX_COMMIT` — canonical commit subject for format-only fixes (e.g. `"fix: apply rustfmt"`)
- `LINT_FIX_COMMIT` — canonical commit subject for lint fixes (e.g. `"fix: address clippy lints"`)

**Group C — Labels** (show existing GitHub labels, ask which map to priority):
- Does the repo have `priority:P0` / `priority:P1` / `priority:P2` / `priority:P3` labels?
  - If yes: use them. Set `LABEL_TAXONOMY` to a description based on the existing label set.
  - If no: ask whether to create a standard P0–P3 label set, or describe custom priority labels.
- Ask for any area/classification labels the user wants the auto-engineer to use.

**Group D — Playbooks** (ask):
- Should playbook files be created? (yes/no)
- If yes: what path prefix within the target? (e.g. `docs/agent-playbooks`, `.claude/playbooks`)
- If no: policy will be inlined into skills as concise summaries

### For new projects

Ask the user:

1. **Project description**: "What does this project do? (one sentence)"
2. **Tech stack**: offer detected guesses (from any files already present) + "other"
3. **GitHub owner/repo**: default to `<gh-user>/<dirname>` — confirm or override
4. **Create label set**: offer to create standard P0–P3 + `bug`/`enhancement` labels
5. **Playbooks**: same as Group D above

---

## Phase 3 — Resolve placeholders

Build a substitution map from the collected values:

```
GITHUB_OWNER        → detected or user-provided
GITHUB_REPO         → detected or user-provided
GITHUB_USER         → gh api user login
PROJECT_DESCRIPTION → user-provided or README first line
BUILD_CMD           → detected or user-provided
TEST_CMD            → detected or user-provided
FORMAT_CMD          → detected or user-provided
LINT_FIX_CMD        → detected or user-provided
FORMAT_FIX_COMMIT   → detected or user-provided
LINT_FIX_COMMIT     → detected or user-provided
PLAYBOOK_SDLC       → path if playbooks enabled, else ""
PLAYBOOK_BUILD      → path if playbooks enabled, else ""
PLAYBOOK_TEST       → path if playbooks enabled, else ""
PLAYBOOK_PR_REVIEW  → path if playbooks enabled, else ""
PLAYBOOK_PRIORITIZATION → path if playbooks enabled, else ""
LABEL_TAXONOMY      → inline description of the project's label scheme
PROJECT_IMAGE       → "<GITHUB_REPO>-auto-engineer"
PROJECT_WORKDIR     → "/home/agent/work"
REVIEW_BOT_LOGINS   → detected or user-confirmed (empty if none)
SELF_REVIEW_REQUIRED → "true" when no review bots, no CI tests, or greenfield (gates the SDLC self-review block)
SELF_REVIEW_EXPERT  → user-provided expert persona for the review subagent (e.g. "senior Go backend engineer")
SELF_REVIEW_REASON  → short phrase naming what's missing ("review bots", "CI tests", "review bots or CI tests")
TOOLCHAIN_SETUP     → Dockerfile snippet installing the target project's language toolchain (see below)
```

### `TOOLCHAIN_SETUP` — per-stack Dockerfile snippets

The base Dockerfile is intentionally language-agnostic. Based on the detected stack (Phase 1), substitute `{{TOOLCHAIN_SETUP}}` in `templates/Dockerfile` with the appropriate snippet. If the user confirmed/overrode the stack in Phase 2, use that. Ask the user to confirm the exact toolchain version when the repo pins one (e.g. `go.mod` `go` directive, `rust-toolchain.toml`, `.nvmrc`, `.python-version`).

| Stack | Snippet (run as `USER agent`, before `WORKDIR`) |
|---|---|
| Rust | `COPY --chown=agent:agent rust-toolchain.toml /tmp/toolchain/ 2>/dev/null || true`<br>`RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh -s -- -y --default-toolchain stable --profile minimal --component clippy,rustfmt`<br>`ENV PATH=/home/agent/.cargo/bin:$PATH` |
| Go | `USER root`<br>`RUN curl -fsSL https://go.dev/dl/go{{GO_VERSION}}.linux-$(dpkg --print-architecture).tar.gz \| tar -C /usr/local -xz`<br>`ENV PATH=/usr/local/go/bin:/home/agent/go/bin:$PATH GOPATH=/home/agent/go`<br>`RUN go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest` *(then `USER agent`)* |
| Node/TS | `# Node is already installed in the base image via nodesource; no extra toolchain needed.`<br>*(If the project pins a Node version via `.nvmrc` or `engines.node`, install `nvm` or swap to that version instead.)* |
| Python | `RUN pip install --user --no-cache-dir uv ruff pytest build`<br>*(If the repo uses Poetry/Hatch/PDM, install that instead of `uv`.)* |
| Make-based (no detectable language) | Ask the user which language toolchains the Makefile drives, then use the matching snippet(s) above. |
| Unknown | Ask the user: "What language/runtime does this project need in the container?" and construct the snippet from their answer. |

Detect pinned versions when possible and substitute them into the snippet (e.g. read the `go` line from `go.mod` for `GO_VERSION`, default to the latest stable if absent). Never leave `{{GO_VERSION}}` or similar placeholders in the final Dockerfile.

For all `{{#if VAR}}...{{/if}}` blocks in templates: evaluate each against the collected values and either include or strip the block. Key conditionals:

| Block | Include when | Strip when |
|---|---|---|
| `{{#if PLAYBOOK_X}}` | playbook path is non-empty | playbook path is empty |
| `{{#if REVIEW_BOT_LOGINS}}` | `REVIEW_BOT_LOGINS` is non-empty | `REVIEW_BOT_LOGINS` is empty (self-review mode) |
| `{{#if HITL_MODE}}` | HITL mode enabled | HITL mode not enabled |

Never leave raw `{{#if ...}}` / `{{/if}}` markers in the written output — the rendered skill must be plain markdown with no template syntax remaining.

---

## Phase 4 — Write files

Templates are read from this repo at `templates/`. All output paths are relative to `<target>/`.

### Skills

Write only skill files that do **not** already exist in `<target>/.claude/skills/<name>/`:

| Template | Output path |
|---|---|
| `templates/skills/auto-engineer/SKILL.md` | `<target>/.claude/skills/auto-engineer/SKILL.md` |
| `templates/skills/sdlc/SKILL.md` | `<target>/.claude/skills/sdlc/SKILL.md` |
| `templates/skills/file-issue/SKILL.md` | `<target>/.claude/skills/file-issue/SKILL.md` |
| `templates/skills/wait-for-pr/SKILL.md` | `<target>/.claude/skills/wait-for-pr/SKILL.md` |
| `templates/skills/usage/SKILL.md` | `<target>/.claude/skills/usage/SKILL.md` |
| `templates/skills/usage/probe.sh` | `<target>/.claude/skills/usage/probe.sh` |

### Config files (only if not already present)

| Template | Output path |
|---|---|
| `templates/.gitignore` | `<target>/.claude/.gitignore` |
| `templates/settings.local.json` | `<target>/.claude/settings.local.json` |

If `settings.local.json` already exists, **do not overwrite** — note in the report that the user should manually add the permissions from `templates/settings.local.json` if needed.

### Docker infrastructure (always write, ask before overwriting)

| Template | Output path |
|---|---|
| `templates/Dockerfile` | `<target>/Dockerfile` |
| `templates/sandbox.sh` | `<target>/scripts/sandbox.sh` |
| `templates/auto-engineer.sh` | `<target>/scripts/auto-engineer.sh` |
| `templates/docker-entrypoint.sh` | `<target>/scripts/docker-entrypoint.sh` |

If any of these already exist, ask the user before overwriting (a quick single prompt listing all conflicts).

When writing `Dockerfile`, substitute `{{TOOLCHAIN_SETUP}}` with the per-stack snippet resolved in Phase 3. The final Dockerfile must contain a working toolchain install for the target project's language — never leave the placeholder unresolved and never ship a Dockerfile that lacks the language runtime the target project needs to build/test.

After writing scripts:

```sh
chmod +x <target>/scripts/sandbox.sh <target>/scripts/auto-engineer.sh <target>/scripts/docker-entrypoint.sh
```

### Permissions to add to settings.local.json

If `settings.local.json` was freshly created, add tech-stack-specific build permissions on top of the base set:

| Stack | Additional permissions |
|---|---|
| Rust | `"Bash(cargo build:*)"`, `"Bash(cargo test:*)"`, `"Bash(cargo fmt:*)"`, `"Bash(cargo clippy:*)"` |
| Go | `"Bash(go build:*)"`, `"Bash(go test:*)"`, `"Bash(gofmt:*)"` |
| Node | `"Bash(npm run:*)"`, `"Bash(npm test:*)"` |
| Python | `"Bash(pytest:*)"`, `"Bash(ruff:*)"`, `"Bash(python -m build:*)"` |
| Make | `"Bash(make:*)"` |

### Playbook stubs

If the user chose to create playbooks, first ask:

> "Should I fill in the playbooks with sane defaults based on what I know about this project, or leave `{{FILL_IN}}` markers for you to complete manually?"

**If the user chooses defaults**: generate each playbook's content using everything collected so far — the tech stack, build/test/lint commands, GitHub labels, repo structure, and any CI workflows found. Write complete, immediately-usable content. Do not leave any `{{FILL_IN}}` markers in the output.

**If the user chooses manual**: write stub files with `{{FILL_IN}}` markers and a clear header in each explaining what to fill in and why it matters for the auto-engineer loop.

Either way, write to `<target>/<prefix>/`:

- `<prefix>/sdlc.md` — branch naming, commit format, PR process
- `<prefix>/build-run.md` — how to build and run the project locally
- `<prefix>/testing.md` — test strategy, how to run tests, CI matrix
- `<prefix>/pr-review.md` — CI readiness criteria, review classification rules
- `<prefix>/prioritization.md` — issue labels, priority definitions, triage rules

Never overwrite stubs that already exist.

### Label creation

If the user requested a standard label set:

```sh
gh label create "priority:P0" --color "B60205" --description "Critical — blocks core functionality" --repo <GITHUB_OWNER>/<GITHUB_REPO>
gh label create "priority:P1" --color "D93F0B" --description "High — required for next milestone" --repo <GITHUB_OWNER>/<GITHUB_REPO>
gh label create "priority:P2" --color "E4E669" --description "Medium — polish and hardening" --repo <GITHUB_OWNER>/<GITHUB_REPO>
gh label create "priority:P3" --color "0E8A16" --description "Low — nice-to-have or future work" --repo <GITHUB_OWNER>/<GITHUB_REPO>
gh label create "bug"         --color "d73a4a" --description "Something isn't working" --repo <GITHUB_OWNER>/<GITHUB_REPO>
gh label create "enhancement" --color "a2eeef" --description "New feature or improvement" --repo <GITHUB_OWNER>/<GITHUB_REPO>
```

---

## Phase 5 — Report

Print a summary scoped to `<target>/`:

```
Seeded auto-engineer into <target>:

  Skills written:
    .claude/skills/auto-engineer/SKILL.md
    .claude/skills/sdlc/SKILL.md
    ...

  Skills skipped (already existed):
    <none> | <list>

  Docker:
    Dockerfile
    scripts/sandbox.sh
    scripts/auto-engineer.sh
    scripts/docker-entrypoint.sh

  Config:
    .claude/settings.local.json (created)  |or|  .claude/settings.local.json (already exists — see note below)
    .claude/.gitignore

  [If playbooks created:]
  Playbook stubs (fill these in before running the loop):
    <prefix>/sdlc.md
    <prefix>/build-run.md
    <prefix>/testing.md
    <prefix>/pr-review.md
    <prefix>/prioritization.md

[If settings.local.json was skipped:]
  Note: .claude/settings.local.json already existed and was not modified.
  To allow auto-engineer to run without prompts, merge these permissions:
    <path-to-this-repo>/templates/settings.local.json

Next steps:
  1. cd <target> && review the written files
  2. Fill in any playbook stubs marked {{FILL_IN}}
  3. Run `scripts/auto-engineer.sh` to start the autonomous loop
     or `scripts/sandbox.sh /some-skill` for a one-off skill invocation
```

---

## Never

- Copy this seed skill or its templates into the target project.
- Overwrite existing playbook files — those are user-managed.
- Overwrite a pre-existing `.claude/skills/<name>/` directory — skip it and note it in the report.
- Create commits or push during seeding — the user should review and commit the seeded files.
- Ask the user for the same information twice — collect everything in Phase 2 before writing.
