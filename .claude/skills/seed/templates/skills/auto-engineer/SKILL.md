---
name: auto-engineer
description: Autonomously drive project work end-to-end — pick an unblocked issue, plan it, implement, push a PR, resolve CI and review-bot feedback, merge when green, then repeat. Use when the user says "auto-engineer", "auto-pilot", "go run the loop", or invokes `/auto-engineer`.
---

# auto-engineer

{{#if PLAYBOOK_SDLC}}Read these shared playbooks first:

- `{{PLAYBOOK_SDLC}}`
- `{{PLAYBOOK_BUILD}}`
- `{{PLAYBOOK_TEST}}`
- `{{PLAYBOOK_PR_REVIEW}}`
- `{{PLAYBOOK_PRIORITIZATION}}`
{{/if}}

Closes the full SDLC loop without prompting the user between steps. Each invocation runs **one cycle** (pick → plan → implement → PR → wait → merge), then reschedules itself via `ScheduleWakeup` with prompt `/auto-engineer` for the next cycle. Stops cleanly when it runs out of work or hits something it can't safely resolve.

This skill is a deliberate override of the project's default "don't merge your own PRs" rule — merging is the whole point of closing the loop. It only applies while auto-engineer is driving.

## When to invoke

- User says "run the loop", "auto-engineer", "auto-pilot the next issue", or similar.
- User types `/auto-engineer` (optionally with `#NN` to scope to a single issue for one cycle, no reschedule).
- This skill re-invokes itself at the end of each successful cycle via `ScheduleWakeup`.

## Entry flags and phase state

All persistent state lives in the wakeup prompt — `/compact` can summarize away conversation state, so nothing important should rely on being in context.

Parse these flags on every entry before doing any work:

| Flag | Meaning |
|---|---|
| `--iteration N` | Current cycle number (1-indexed). Absent → treat as 1. |
| `--phase wait` | Re-entry into the PR-wait poll loop (jump to step 6b). Requires `--pr`. |
| `--pr M` | PR number being waited on (only meaningful with `--phase wait`). |
| `#NN` | Scope to a single issue for one cycle, then stop without rescheduling. |

A bare `/auto-engineer` is iteration 1, phase "pick".

## Iteration budget

**Soft cap: 8 iterations per user-initiated run.** After the 8th merged PR, stop and wait for the user to restart. Prevents runaway loops.

The `--iteration N` flag is what enforces the cap across `/compact` boundaries — always carry it in every `ScheduleWakeup` call.

## Cycle

### 1. Pick an unblocked issue

{{#if PLAYBOOK_PRIORITIZATION}}The picking rules live in `{{PLAYBOOK_PRIORITIZATION}}` — this step is the mechanical implementation of that policy.{{else}}Pick the highest-priority unblocked issue from the backlog.{{/if}}

```sh
gh issue list --search 'no:assignee' --state open \
  --json number,title,labels,body,assignees
```

Filter out:
- Issues labeled `blocked`, `needs-discussion`, `question`, `wontfix`.
- Issues whose body references an unresolved dependency (e.g. "blocked on #NN" where #NN is still open).

Sort preference (apply in order):

1. `priority:P0` before `priority:P1` before `priority:P2` before `priority:P3`. Issues with no `priority:*` label rank **after** `priority:P3` — they are un-triaged.
2. Within a priority bucket, apply any project-specific area/track ordering from `{{PLAYBOOK_PRIORITIZATION}}` (or lowest-numbered first if no playbook).
3. Within a bucket, lowest-numbered first.

If the top candidate's prerequisites are still open, skip it and try the next one. If a candidate is un-triaged, prefer triaging it via the `file-issue` skill before working it.

If the candidate list is empty → **stop** with message *"no unblocked issues — auto-engineer idle."*

Assign and branch:

```sh
gh issue edit <N> --add-assignee {{GITHUB_USER}}
git checkout main && git pull
git checkout -b <branch>   # e.g. m<N>-<slug> or <verb>-<slug>
```

Then rename the tmux window so a human glancing at the terminal can see which
issue this cycle is on. `<slug>` is the same short slug used in the branch name
(3–4 words, kebab-case).

The mechanism differs by environment because Claude's Bash tool has no
controlling terminal, so OSC 2 escapes and `/dev/tty` writes can't reach the
host tmux pane from inside the container:

- **Inside the container**: write the slug to `$AUTO_ENGINEER_SLUG_FILE` (set by
  `scripts/sandbox.sh` to a bind-mounted path). A poller on the host tails that
  file and runs `tmux rename-window "AE -> <slug>"` against the host tmux.
- **On the host (no container)**: call `tmux rename-window` directly.
- **Outside tmux entirely**: no-op.

Unified command:

```sh
if [ -n "${AUTO_ENGINEER_SLUG_FILE:-}" ]; then
    printf '%s' "<slug>" > "$AUTO_ENGINEER_SLUG_FILE"
elif [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
    tmux rename-window "AE -> <slug>"
fi
```

### 2. Delegate planning to a sub-agent

Use the `Agent` tool with `subagent_type: "Plan"`. Pass the full issue body, its label list, and any linked issues you fetched. Ask for:

- Files to create / modify (absolute paths).
- Functions or types to add / change, with signatures.
- Tests to add.
- Risks and rollback plan.

Return format: plain markdown, ≤300 words. The parent reads the result as conversation text — **do not** enter plan mode for the sub-agent.

### 3. Auto-approve and implement

The parent proceeds directly with `Edit` / `Write` per the returned plan. No user confirmation. If the sub-agent's plan is clearly wrong (wrong file paths, contradicts code you read), re-spawn it once with a corrective prompt; if it's still wrong after that, **stop** and report.

### 4. Build + test

Run in order:

```sh
{{BUILD_CMD}}
{{TEST_CMD}}
```

On failure: diagnose and fix in place. **Maximum 3 fix attempts per cycle.** If the 3rd attempt still fails → **stop** with a summary of the failure and what was tried.

### 5. Commit and open PR

- Coherent commits (not a single mega-commit, not micro-commits). Each with the standard `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>` trailer.
- `git push -u origin <branch>`.
- Open the PR via `mcp__github__create_pull_request` with the standard Summary + Test plan body. **No "generated with" footer.**
- **Always include `Closes #<N>`** on its own line near the top of the PR body. Without it, the squash-merge won't auto-close the issue and the `no:assignee` candidate set stays polluted on the next cycle.
- Record the PR number and URL for the rest of the cycle.

### 6. Wait for CI and review

Auto-engineer owns the PR-wait loop directly — do **not** delegate to the `wait-for-pr` skill. Delegating would hand off the `ScheduleWakeup` thread and there would be no path back into this skill when CI finishes.

The `wait-for-pr` skill is for manual invocations only.

#### 6a. First poll tick (immediately after opening the PR)

Record the PR open time. Run one poll tick (step 6b below), then either proceed or sleep.

#### 6b. Poll tick (re-entry via `--phase wait --pr M`)

1. Check CI state:
   ```sh
   gh pr checks <M> --json name,state,bucket,link
   ```
2. Count review-bot activity:
   ```sh
   gh api "repos/{{GITHUB_OWNER}}/{{GITHUB_REPO}}/issues/<M>/comments" \
     --jq '[.[] | select(.user.login | test("{{REVIEW_BOT_LOGINS}}"))] | length'
   ```
   Also fetch formal reviews via `mcp__github__get_pull_request_reviews`.

3. Evaluate "done" criteria:
   - Every check is in a terminal state (`success`, `failure`, `skipped`, `cancelled`, `neutral`, `timed_out`, `stale`) — nothing `in_progress`, `queued`, or `pending`.
   - At least one review-bot comment exists **or** 30 minutes have elapsed since PR opened.

4. **If done**: proceed to step 6c.

5. **If not done**: schedule the next poll tick and end the turn — do not proceed further.
   ```
   ScheduleWakeup(
     delaySeconds=<cadence>,
     prompt="/auto-engineer --iteration N --phase wait --pr M",
     reason="auto-engineer: waiting on CI/review for PR #M (iteration N)"
   )
   ```
   Cadence:
   | Elapsed since PR opened | delaySeconds |
   |---|---|
   | 0–10 min | 120 |
   | 10–30 min | 180 |
   | 30 min+ (bots only) | 1200 |
   Never use 300 s — it's a cache-miss with no payoff.

   If any check is `action_required` → **stop** instead (human must approve).

#### 6c. Review-response

Carry a `--fix-round R` counter (default 0) forward in the wakeup prompt when looping back here. **Max 2 fix rounds** — if `R == 2` and findings remain, stop.

**Auto-fix CI failures** (before classifying review findings):

| Failed check pattern | Fix command | Canonical commit subject |
|---|---|---|
| format / lint check matching `{{FORMAT_FIX_COMMIT}}` sentinel | `{{FORMAT_CMD}}` | `{{FORMAT_FIX_COMMIT}}` |
| lint check matching `{{LINT_FIX_COMMIT}}` sentinel | `{{LINT_FIX_CMD}}` | `{{LINT_FIX_COMMIT}}` |

Before applying: check `git log origin/<base>..HEAD --format='%s'` — if the canonical subject is already there and the check still failed, do not re-apply. Flag as "auto-fix already attempted, did not resolve" and stop.

After applying a fix: commit with the canonical subject + `Co-Authored-By:` trailer, `git push`, then schedule another poll tick:
```
ScheduleWakeup(
  prompt="/auto-engineer --iteration N --phase wait --pr M --fix-round R",
  ...
)
```

**Classify review findings**:

- **All green, no actionable findings** → proceed to merge (step 7).
- **Actionable bugs** → apply follow-up commits (never amend), `git push`, then reschedule another poll tick with `--fix-round R+1`.
- **Out-of-scope nits** → reply on the PR via `mcp__github__add_issue_comment` ("deferred to future work"), open a follow-up issue via the `file-issue` skill, then proceed to merge.

### 7. Merge

Only merge when **all** are true:
- Every CI check is `success` or `skipped` (none `failure`, `action_required`, `timed_out`, `pending`).
- No unresolved actionable review findings.
- Either ≥1 review bot posted and every actionable finding is addressed, **or** 30 min elapsed since PR open with nothing actionable.

Use the repo's configured merge method (check `gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed` and prefer squash if available, otherwise the repo default):

```
mcp__github__merge_pull_request(pull_number=<N>, merge_method="squash")
```

Post-merge:

```sh
git checkout main && git pull
git branch -d <branch>
```

### 8. Capture follow-ups

Before reloading the next issue, scan for work that surfaced during this cycle but wasn't in scope. Sources to check:

- The merged diff for new `TODO`, `FIXME`, or `XXX` markers added in this PR (`git log -p -1`).
- Deferred review comments posted in step 6 ("deferred to future work") that didn't already get an issue opened.
- Build/test warnings observed during step 4 that weren't blocking but deserve follow-up.
- Anything the sub-agent's plan (step 2) explicitly listed as "out of scope" or "risks."

For each distinct follow-up, **invoke the `file-issue` skill** — do not call `mcp__github__create_issue` directly. The `file-issue` skill handles dedupe against existing issues and enforces the label taxonomy. Feed it:

- A specific title.
- A 1–3 sentence motivation, including `discovered while merging #<PR>` so the origin is recoverable later.
- Concrete work items.
- Context (file paths, commit SHAs, related issue numbers).

If nothing worth filing, skip silently. **Do not file speculative or "nice-to-have" issues** — only things with concrete motivation.

### 9. Check session quota

Before compacting and kicking off the next cycle, run `/usage` (the `usage` skill). It emits two machine-readable lines — `remaining_pct: <float>` and `reset_ts: <ISO>` — plus a human summary. Parse `remaining_pct`.

- **≥ 10% remaining** → proceed to step 10.
- **< 10% remaining** → don't start a new cycle; the next one could tip over mid-PR and leave an orphaned branch. Instead:
  1. Read `reset_ts` from `/usage` output.
  2. Compute `secondsUntilReset = reset_ts - now`. Add a 60 s buffer.
  3. **Compaction decision:**
     - If `secondsUntilReset ≤ 90 min`: skip `/compact`. Wait is short enough that compaction itself would waste quota.
     - If `secondsUntilReset > 90 min`: run `/compact` first to avoid paying full token cost for a large idle prompt across many hops.
  4. `ScheduleWakeup` with `delaySeconds = min(secondsUntilReset + 60, 3300)`, `prompt = "/auto-engineer --iteration <N>"`, `reason = "auto-engineer: paused for quota reset at <ts>"`.
  5. End the turn.

### 10. Compact and re-enter

If iteration budget not exhausted and no stop condition tripped:

1. Run `/compact` to shrink the context before the next cycle. **Do not** use `/clear` — it wipes the iteration counter and stop-reason history.
2. Schedule the next cycle:
   ```
   ScheduleWakeup(
     delaySeconds=60,
     prompt="/auto-engineer --iteration <N+1>",
     reason="auto-engineer: next cycle (iteration N+1 of 8)"
   )
   ```
   Never carry `--phase`, `--pr`, or `--fix-round` into a fresh cycle; those are intra-cycle state.
3. End the turn.

## Stopping

On any stop condition:

1. Leave the current branch and PR in place — do **not** delete or close anything.
2. If a PR exists for the current cycle, post one comment on it via `mcp__github__add_issue_comment` summarizing why auto-engineer paused and what it tried.
3. End the turn with a plain-text status to the user. **Do not** call `ScheduleWakeup`.

Stop conditions:

- No unblocked issues remain.
- 3 consecutive build/test fix attempts failed.
- `--fix-round` reached 2 and actionable findings remain.
- Any check in `action_required` state (needs human approval).
- Any security / advisory finding from `github-advanced-security[bot]`.
- Merge conflict against `main` that isn't cleanly resolvable by `git pull --rebase`.
- Iteration budget of 8 reached.
- The issue was reassigned away from `{{GITHUB_USER}}` while auto-engineer held it.

## Never

- Force-push, rebase pushed branches, or rewrite reviewed commits.
- Edit `main` directly.
- Merge without green CI.
- Delegate the PR-wait loop to the `wait-for-pr` skill — it would steal the `ScheduleWakeup` thread.
- Continue past 8 iterations without a fresh user invocation.
- Auto-fix test or build logic in step 6c (format and lint only; real fixes are follow-up commits).
- Close an issue manually — let the merge do it via the PR body's `Closes #N`.
- Ask the user for input — **never use `AskUserQuestion` or pause for a response**. If information is missing, make the most defensible choice and continue; if a stop condition applies, stop and report but do not ask.
