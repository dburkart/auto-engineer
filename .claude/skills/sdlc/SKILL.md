---
name: sdlc
description: The project's software-delivery workflow — how changes move from idea to merged on main. Use when starting a new task, committing, or opening/updating a PR.
---

# SDLC

Read `docs/agent-playbooks/sdlc.md` first for repo-level branch, commit, push, and PR policy.

Read `docs/agent-playbooks/pr-review.md` when the task includes CI interpretation or review response.

## When to use this skill

Use this skill when the task involves:

- starting a new cohesive change on its own branch
- deciding what checks to run before push
- preparing a PR body and opening a PR
- responding to review feedback without rewriting reviewed history

## Branch naming

Create a branch per unit of work. Conventional patterns:
- `m<issue-number>-<slug>` for issue-tracked work
- `<verb>-<noun>` for untracked changes (e.g. `fix-login-timeout`, `add-metrics-endpoint`)

Always branch from an up-to-date `main`:

```sh
git checkout main && git pull
git checkout -b <branch>
```

## Commits

- Group related changes into coherent commits — not one mega-commit, not micro-commits per line.
- Use the imperative mood in the subject line (`Add`, `Fix`, `Remove`, not `Added`, `Fixed`).
- Each commit must include the trailer:
  ```
  Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
  ```
- Never commit directly to `main`.

## Opening a PR

Use the standard Summary + Test plan body structure:

```
## Summary
- <bullet describing what changed and why>

## Test plan
- [ ] <concrete test step>
- [ ] <edge case to verify>

Closes #<N>
```

Open via `mcp__github__create_pull_request`. No "generated with Claude" footer.

## CI and review follow-up

- If CI or review follow-up is needed, hand off to `wait-for-pr` for Claude-specific polling and automation.
- Review classification still comes from `docs/agent-playbooks/pr-review.md`.

## Self-review (required for this project)

This project has no review bots or CI tests, so every PR must get an independent review before merge. Before requesting merge:

1. Spawn a review subagent via the `Agent` tool with a prompt framing it as a **Senior prompt engineer** reviewing the diff for correctness, security, performance, and adherence to project conventions.
2. Pass the agent the PR number and the full diff (`gh pr diff <N>`); instruct it to report blocking issues, in-scope nits, and out-of-scope suggestions separately, and to keep its reply under 400 words.
3. Triage its findings using the same actionable/nit/out-of-scope classification above. Address blockers in a new commit on the branch; file follow-up issues for deferred items.
4. Record in the PR body (under "Test plan") that a self-review was performed and link the resulting commits or issues.

Never merge a PR for this project without completing the self-review cycle.

## Template vs. instance rule

This repo is a **toolkit factory**. There are two copies of most skills:

| Path | What it is |
|------|------------|
| `templates/skills/<skill>/SKILL.md` | The canonical source shipped to user projects via `seed` |
| `.claude/skills/<skill>/SKILL.md` | The local instance used to develop *this* repo |

**Issues and feature work always target `templates/`.** The local instance (`.claude/skills/`) is only touched when the task is explicitly about the development harness itself.

Before editing any skill file, confirm it lives under `templates/skills/`. If you find yourself reaching for `.claude/skills/`, stop and re-read the issue — you almost certainly have the wrong file.

**Exception — `seed`:** The seed skill does not seed itself. Its canonical source lives at `.claude/skills/seed/SKILL.md` (there is no `templates/skills/seed/`). Issue work targeting seed goes to `.claude/skills/seed/`.

## Never

- Commit directly to `main`.
- Force-push or rewrite reviewed commits unless the user explicitly approves.
- Merge a PR on the user's behalf unless asked.
- Edit `.claude/skills/<skill>/` for issue work — always edit the corresponding `templates/skills/<skill>/` file instead (except `seed`, which has no template copy).
