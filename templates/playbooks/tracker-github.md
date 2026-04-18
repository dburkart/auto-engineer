# Tracker playbook — GitHub Issues

This project tracks work as GitHub Issues in `{{GITHUB_OWNER}}/{{GITHUB_REPO}}`. Every skill that touches issues (`file-issue`, `auto-engineer`, `auto-manager`) calls the operations below instead of invoking `gh`/`mcp__github__*` directly.

## Issue identity

- **ID format**: `#<N>` where `<N>` is the GitHub-assigned issue number (e.g. `#18`). Always include the `#` when writing IDs in commits, PR bodies, or comments — that's what renders as a live link on GitHub.
- **Source of truth**: `https://github.com/{{GITHUB_OWNER}}/{{GITHUB_REPO}}/issues`

## Operations

### list_open_issues

Enumerate every open issue with enough metadata to filter, sort, and pick.

```sh
gh issue list --state open --limit 200 \
  --json number,title,labels,body,assignees,createdAt
```

### get_issue `<N>`

```sh
gh issue view <N> --json number,title,body,labels,state,assignees,comments
```

### search_issues `<query>`

Used by `file-issue` to dedupe before creating.

```
mcp__github__search_issues(
  query="repo:{{GITHUB_OWNER}}/{{GITHUB_REPO}} is:open <keywords>"
)
```

### create_issue `<title> <body> <labels...>`

```
mcp__github__create_issue(
  owner="{{GITHUB_OWNER}}",
  repo="{{GITHUB_REPO}}",
  title="<title>",
  body="<body>",
  labels=["priority:PN", ...]
)
```

Returns the issue number + URL.

### update_issue `<N>`

```sh
gh issue edit <N> --title "<new title>" --body "<new body>"
```

### add_label `<N> <label>`

```sh
gh issue edit <N> --add-label "<label>"
```

### comment_on_issue `<N> <text>`

```
mcp__github__add_issue_comment(
  owner="{{GITHUB_OWNER}}",
  repo="{{GITHUB_REPO}}",
  issue_number=<N>,
  body="<text>"
)
```

### close_issue `<N>` [comment]

```sh
gh issue close <N> --comment "<optional comment>"
```

Prefer letting a PR close the issue via `Closes #<N>` — see below.

### assign_issue `<N> <assignee>`

```sh
gh issue edit <N> --add-assignee <assignee>
```

## PR ↔ issue linking

- **Auto-close on merge**: include `Closes #<N>` on its own line near the top of every PR body. GitHub closes the issue automatically when the PR merges. Do **not** call `close_issue` after such a merge — it's redundant and clutters the issue timeline.
- **Cross-reference**: GitHub auto-links the PR on the issue once `Closes #<N>` is present. No manual comment needed.

## Priority representation

Priority is encoded via labels: `priority:P0` / `priority:P1` / `priority:P2` / `priority:P3`. Exactly one per issue. Issues without a priority label are **un-triaged** and rank after `priority:P3` in auto-engineer's picker.

## Blocked issues

Mark a blocked issue by either:
- Applying the `blocked` label, or
- Referencing a still-open prerequisite in the body (e.g. "blocked on #12").

Auto-engineer's picker respects both — it skips any candidate with the `blocked` label or an unresolved dep reference.

## Unassigned filter

`list_open_issues` returns issues with their `assignees` array. Filter in memory for `assignees: []` to find unclaimed work — do not rely on `gh issue list --search 'no:assignee'` since its query syntax shifts across `gh` versions.
