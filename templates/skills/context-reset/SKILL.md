---
name: context-reset
description: Guidance on shrinking or fully resetting conversation context between auto-engineer iterations — when to use /compact (built-in summarise), /clear (built-in wipe), or a full process restart via scripts/restart-loop.sh.
---

# context-reset

> **This skill is a reference document, not an executable action.** `/compact` and `/clear` are built-in Claude Code CLI commands — they cannot be invoked by the `Skill` tool from within a running session. Reading this skill brings the guidance into context so you can apply the right approach for the situation.

## Why context accumulates

Each auto-engineer iteration reads playbooks, fetches issues, reads source files, runs sub-agents, and produces diffs. That context stays in the conversation window across iterations unless explicitly trimmed. After several cycles the window grows large, cache misses become expensive, and prior-cycle residue (old branch names, resolved bugs, superseded plans) can subtly corrupt decisions.

## Three options

| Situation | Action |
|---|---|
| Normal end-of-cycle, session still healthy, just want to trim cost | `/compact` (built-in) |
| Prior cycles are actively corrupting decisions — Claude is replaying resolved issues or hallucinating old state | `/clear` (built-in), then restart auto-engineer with explicit `--iteration N` |
| Container run requiring a truly clean process (token ceiling hit, env/credential refresh needed) | `scripts/restart-loop.sh --iteration N` (run on the host) |

## `/compact` — the default (auto-engineer step 10)

Summarises the conversation in place. The iteration counter, stop-reason history, and current PR state survive in the summary. This is why auto-engineer step 10 calls `/compact` rather than `/clear` — the `ScheduleWakeup` prompt carries `--iteration N` forward, but the surrounding rationale lives in the summary.

**How to invoke:** type `/compact` directly in the Claude Code CLI. It cannot be called from a skill or tool.

## `/clear` — full wipe

Erases the entire conversation. Use only when context corruption is confirmed — you will lose the iteration counter and any uncarried state. After `/clear`, restart auto-engineer explicitly:

```
/auto-engineer --iteration <N>
```

**How to invoke:** type `/clear` directly in the Claude Code CLI.

## `scripts/restart-loop.sh` — process restart

Kills the current container and launches a fresh one. The new Claude process starts with zero context. Use when `/compact` is insufficient (e.g. the context window is full even after compaction) or when you need a clean environment (fresh credentials, updated Docker image, memory hygiene).

```sh
# Start from iteration 1
scripts/restart-loop.sh

# Resume at a specific iteration
scripts/restart-loop.sh --iteration <N>
```

The `--iteration N` flag is passed through to `/auto-engineer` so the loop continues from where it left off with a clean slate.

## Decision guide

1. End of a healthy cycle with plenty of quota → `/compact` (auto-engineer does this automatically in step 10).
2. Claude is making decisions based on stale prior-cycle context → `/clear` + `/auto-engineer --iteration N`.
3. Context window is full even after `/compact`, or you need a fresh container → `scripts/restart-loop.sh --iteration N`.
