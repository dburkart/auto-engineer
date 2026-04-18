# Tracker playbook — Local to-do files

This project tracks work in local markdown files on an **orphan git branch** named `tracker`. Main and feature branches never contain issue files; only the `tracker` branch does. All access — for agents and humans alike — goes through a single CLI at `scripts/issues`, which manages a pinned worktree and handles push/pull plumbing under the hood.

This tracker is a good fit for small / solo projects where the overhead of a hosted tracker isn't worth it, and for exercising the auto-engineer loop in a greenfield repo. Code review and CI still live on GitHub; only *issue tracking* is local.

## Why an orphan branch

- Main stays clean: no `.auto-engineer/issues/*.md` files ever land on `main`, so feature branches don't drift or merge-conflict on unrelated issue churn.
- Worktree isolation: agents run in sandbox worktrees cut from `main`; they can still read/write issues because the CLI maintains its own worktree at `.auto-engineer/worktree/` pinned to the `tracker` branch.
- `.auto-engineer/` is gitignored on `main`; it is the CLI's private working area.

## The CLI

All operations — read, write, search — go through `scripts/issues`. Do **not** read, write, grep, or `cd` into `.auto-engineer/worktree/` directly. The CLI fetches `origin/tracker`, fast-forwards the worktree, mutates a file, commits, and pushes with rebase-retry.

If this is the first run in the repo, the CLI self-bootstraps: it creates the orphan `tracker` branch, pushes it to `origin`, and attaches a worktree. Subsequent calls reuse that state.

Bash invocation pattern: `scripts/issues <subcommand> [args]` from the repo root.

## Issue identity

- **Storage**: one markdown file per issue on the `tracker` branch.
- **ID format**: four-digit zero-padded integer: `0001`, `0042`, `0137`. Reference as `#<id>` in commits, PR bodies, and cross-refs (e.g. `#0042`). The CLI accepts `1`, `42`, `#42`, `0042` interchangeably and normalizes internally.
- IDs are monotonic; never re-used, even after close.

## Issue file format

(Informational — the CLI owns this; do not hand-edit.)

```markdown
---
id: "0042"
title: Short imperative title, ≤72 chars
state: open                  # open | closed
labels: [priority:P1, enhancement]
assignee: ""                 # github username or ""
created: 2026-04-17T14:03:00Z
updated: 2026-04-17T14:03:00Z
closed_by_pr: ""             # PR URL once closed by a merge
---

## Motivation
<1-3 sentences on why this matters>

## Work
- [ ] concrete sub-task 1
- [ ] concrete sub-task 2

## Context
<PR/commit/file refs, related issue IDs>

## Comments
<!-- appended by `scripts/issues comment`, newest last -->
```

All timestamps are ISO-8601 UTC (`YYYY-MM-DDTHH:MM:SSZ`).

## Operations

Every operation is a `scripts/issues` subcommand. Use `--json` on `list` and `show` when an agent needs to parse results.

### list_open_issues

```
scripts/issues list --json
```

Returns a JSON array: `[{"id","state","title","labels","assignee"}, ...]`. Filters to `state=="open"` by default. Pass `--all` to include closed issues.

Human-readable form: `scripts/issues list` (prints one line per issue).

### get_issue `<id>`

```
scripts/issues show <id> --json
```

Returns a JSON object with all frontmatter fields plus `body` (the full markdown body including comments). Human-readable form: `scripts/issues show <id>` (prints the raw markdown).

### search_issues `<query>`

```
scripts/issues search <query>
```

Greps open issues (titles + bodies) case-insensitively. Emits one line per match in the same format as `list`.

### create_issue `<title> <body> <labels...>`

```
scripts/issues new --title "<title>" --priority P<0-3> [--label <L>]... [--assignee <user>] --body -
<body on stdin, Ctrl-D / EOF>
```

Prints the new `#<id>` on stdout. `--priority` is required implicitly (defaults to P2 if omitted interactively, but agents should pass it explicitly). Extra `--label` flags add area/type labels beyond priority. `--body -` reads body from stdin; omit `--body` and the CLI writes a skeleton (Motivation / Work / Context / Comments).

### update_issue `<id>`

```
scripts/issues update <id> [--title "<new title>"] [--body -]
```

`--body -` replaces the entire body (everything after the frontmatter block) from stdin. Frontmatter is preserved; `updated` is bumped automatically.

### add_label `<id> <label>`

```
scripts/issues label <id> --add <label>
```

To remove: `scripts/issues label <id> --remove <label>`. Duplicate labels are ignored; removing an absent label is a no-op.

### comment_on_issue `<id> <text>`

```
scripts/issues comment <id> "<text>"
```

Appends under the `## Comments` section with a timestamp and the local `git config user.name`. Bumps `updated`.

### close_issue `<id>` [comment]

```
scripts/issues close <id> [--comment "<message>"]
```

Sets `state: closed`, bumps `updated`, and (if `--comment` is passed) appends the comment first.

### assign_issue `<id> <assignee>`

```
scripts/issues assign <id> <github-username>
```

Unassign: `scripts/issues assign <id> --unassign`.

## PR ↔ issue linking

GitHub does **not** auto-close local to-do issues when a PR merges. Auto-engineer must close the issue explicitly:

1. Include `Closes #<id>` in the PR body (human-readable cross-reference only — no GitHub magic).
2. After the PR merges, run `scripts/issues close <id> --comment "closed by <PR URL>"`. The CLI commits the state change to the `tracker` branch and pushes.

This is the one non-obvious divergence from the GitHub tracker — skip step 2 and the issue will sit open forever.

## Priority representation

Priority is encoded via the `labels` array: `priority:P0` / `priority:P1` / `priority:P2` / `priority:P3`. Exactly one per issue (the CLI enforces this when `new` is given `--priority`). Issues without a priority label are **un-triaged** and rank after `priority:P3` in auto-engineer's picker.

## Blocked issues

Mark a blocked issue by either:
- Adding `blocked` via `scripts/issues label <id> --add blocked`, or
- Referencing a still-open prerequisite in the body (e.g. "blocked on #0012").

Auto-engineer's picker skips both.

## Unassigned filter

Parse `list --json` and keep entries where `assignee == ""`.

## Storage model (reference)

- Orphan branch: `tracker` on `origin`. No shared history with `main`.
- Pinned worktree: `.auto-engineer/worktree/` (gitignored on `main`; the CLI creates and maintains it).
- Issue files: `.auto-engineer/issues/<id>.md` *on the tracker branch only*.
- Commit message shape: `[tracker] <op> #<id>[ — <title>]` with `[skip ci]` in the body so tracker commits never trigger CI.

If you see `.auto-engineer/issues/` directly under the repo root on `main`, something is wrong — that directory should only exist inside the pinned worktree.
