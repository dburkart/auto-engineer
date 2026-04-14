---
name: sdlc
description: The project's software-delivery workflow — how changes move from idea to merged on main. Use when starting a new task, committing, or opening/updating a PR.
---

# SDLC

{{#if PLAYBOOK_SDLC}}Read `{{PLAYBOOK_SDLC}}` first for repo-level branch, commit, push, and PR policy.

Read `{{PLAYBOOK_PR_REVIEW}}` when the task includes CI interpretation or review response.{{/if}}

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
- {{#if PLAYBOOK_PR_REVIEW}}Review classification still comes from `{{PLAYBOOK_PR_REVIEW}}`.{{else}}Classify review findings as: actionable bugs (must fix), in-scope nits (fix if quick), or out-of-scope nits (defer with a comment + follow-up issue).{{/if}}

{{#if SELF_REVIEW_REQUIRED}}## Self-review (required for this project)

This project has no {{SELF_REVIEW_REASON}}, so every PR must get an independent review before merge. Before requesting merge:

1. Spawn a review subagent via the `Agent` tool with a prompt framing it as a **{{SELF_REVIEW_EXPERT}}** reviewing the diff for correctness, security, performance, and adherence to project conventions.
2. Pass the agent the PR number and the full diff (`gh pr diff <N>`); instruct it to report blocking issues, in-scope nits, and out-of-scope suggestions separately, and to keep its reply under 400 words.
3. Triage its findings using the same actionable/nit/out-of-scope classification above. Address blockers in a new commit on the branch; file follow-up issues for deferred items.
4. Record in the PR body (under "Test plan") that a self-review was performed and link the resulting commits or issues.

Never merge a PR for this project without completing the self-review cycle.{{/if}}

## Never

- Commit directly to `main`.
- Force-push or rewrite reviewed commits unless the user explicitly approves.
- Merge a PR on the user's behalf unless asked.
