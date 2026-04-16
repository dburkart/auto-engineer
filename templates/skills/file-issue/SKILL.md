---
name: file-issue
description: File a new GitHub issue with the correct priority and area labels applied up front. Use whenever an agent needs to capture a new unit of work — follow-ups from a merged PR, TODOs discovered while coding, or manually-requested issues. Invoked as `/file-issue`.
---

# file-issue

Files a single GitHub issue against `{{GITHUB_OWNER}}/{{GITHUB_REPO}}` with priority and classification labels applied on creation. Keeps the backlog triaged in one step instead of leaving un-labeled issues that pollute the auto-engineer candidate set.

{{#if PLAYBOOK_PRIORITIZATION}}Read `{{PLAYBOOK_PRIORITIZATION}}` before running — the label taxonomy, priority rules, and triage policy all live there. This skill is the mechanical front-end for that policy.{{/if}}

## Label taxonomy

{{LABEL_TAXONOMY}}

## When to invoke

- A merged PR surfaced out-of-scope follow-up work that needs its own issue (auto-engineer step 8, or a human reviewer deferring a nit).
- A `TODO`/`FIXME` was introduced that deserves tracking.
- The user says "file an issue for …" or invokes `/file-issue` directly.

Do **not** use this skill to edit an existing issue — use `mcp__github__update_issue` for that.

## Inputs

Either accept them as free-form arguments after `/file-issue`, or infer from the invoking context:

- **title** — imperative phrase, ≤ 72 chars, no emoji.
- **motivation** — 1–3 sentences on why this matters and what it unblocks.
- **work** — bulleted sub-tasks, concrete enough to act on cold in a week (file paths, type names, function signatures when known).
- **context** — relevant commit SHAs, file paths, existing issue numbers, or the PR that surfaced the follow-up.

If any of those are missing and **cannot be reasonably inferred**, skip the issue silently — do not ask the user. This skill may be called from auto-engineer or other agents where user interaction is not available; asking would block the loop.

## Cycle

### 1. Dedupe

Search open issues for overlap before filing:

```
mcp__github__search_issues(
  query="repo:{{GITHUB_OWNER}}/{{GITHUB_REPO}} is:open <keywords from title>",
)
```

If a strong duplicate exists, **do not** file. Instead, add a comment on the existing issue linking the new context (via `mcp__github__add_issue_comment`) and return its URL.

### 2. Decide labels

Follow the triage rules above ({{#if PLAYBOOK_PRIORITIZATION}}and in `{{PLAYBOOK_PRIORITIZATION}}`{{/if}}):

1. Assign exactly one `priority:P0` / `P1` / `P2` / `P3` label.
2. Assign any area, type, or classification labels appropriate to the work.
3. Never invent a new label from this skill. If the taxonomy is missing a dimension, stop and update the label set in a separate step first.

### 3. Compose the body

Use the canonical template:

```
## Motivation
<1-3 sentences>

## Work
- [ ] <concrete sub-task 1>
- [ ] <concrete sub-task 2>

## Context
<PR/commit/issue references and file paths>
```

### 4. File

```
mcp__github__create_issue(
  owner="{{GITHUB_OWNER}}",
  repo="{{GITHUB_REPO}}",
  title="<title>",
  body="<templated body>",
  labels=["priority:PN", ...],
)
```

Report the new issue number and URL back to the caller.

### 5. Record

If the issue was filed from auto-engineer's follow-up capture pass (step 8), include it in the "captured follow-ups" summary that auto-engineer emits before re-entering its loop.

## Never

- File an issue without at least one `priority:*` label.
- File an issue that duplicates an open one.
- Invent new label values in-flight.
- File speculative "nice-to-have" items with no concrete motivation — they clutter the backlog and degrade the auto-engineer candidate set.
- Close, reassign, or relabel issues other than the one being filed.
