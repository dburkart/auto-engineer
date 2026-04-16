# SDLC Playbook — auto-engineer

## Branch naming

- Issue-tracked: `m<issue-number>-<slug>` (e.g. `m12-refactor-templates`)
- Untracked: `<verb>-<noun>` (e.g. `fix-probe-cache`, `add-python-snippet`)

Always branch from an up-to-date `main`:

```sh
git checkout main && git pull
git checkout -b <branch>
```

## Commit conventions

- Imperative mood subject line (`Add`, `Fix`, `Remove`).
- Group related changes into coherent commits — not one mega-commit, not micro-commits.
- Every commit includes the trailer:
  ```
  Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
  ```
- Never commit directly to `main`.

## PR conventions

Standard body structure:

```
## Summary
- <what changed and why>

## Test plan
- [ ] <concrete verification step>

Closes #<N>
```

- Open via `mcp__github__create_pull_request`.
- No "generated with Claude" footer.
- Always include `Closes #<N>` to auto-close the issue on squash-merge.

## Merge policy

- Prefer squash merge.
- Only merge when all CI checks pass and review is complete.
- Auto-engineer is allowed to merge its own PRs as part of the loop.
