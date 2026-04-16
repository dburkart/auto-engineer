---
name: sync
description: Two-way sync between a seeded project and this auto-engineer repo's templates — covers skills, Dockerfile, and scripts. Detects drift in either direction, presents per-file diffs, and lets you pull from template, push to template, or skip. Harness-internal tool — never seeded into target projects. Invoked as /sync.
argument-hint: [<target-project-path>]
---

# sync

Two-way sync between a seeded project and this auto-engineer repo's templates. Detects drift in skills, Dockerfile, and scripts; lets you resolve each divergence interactively.

This is a harness-internal development tool. It lives only in `.claude/skills/sync/` — the `seed` skill never copies it to target projects.

## When to invoke

- User says "sync skills", "sync with project", "sync templates", or invokes `/sync`.
- Accepts an optional positional argument: path to the seeded project to sync with.

---

## Step 0 — Get the target path

If not provided as an argument, ask:

> "What's the path to the seeded project you want to sync with? (absolute path)"

Resolve to an absolute path. Verify the directory exists. Abort with a clear error if not found.

All reads and writes to the target project use `<target>/` as the root. The auto-engineer repo root (`<ae-repo>`) is the directory that contains both `.claude/` and `templates/` as direct children — from this skill file's location at `.claude/skills/sync/SKILL.md`, that is three levels up.

---

## Step 1 — Discover sync candidates

Sync covers three artifact groups:

### Group A — Skills

- **Template side:** subdirectories under `<ae-repo>/templates/skills/` that contain a `SKILL.md`.
- **Target side:** subdirectories under `<target>/.claude/skills/` that contain a `SKILL.md`.

Classify each skill name:

| Classification | Condition |
|---|---|
| **Paired** | Present in both `templates/skills/<name>/` and `<target>/.claude/skills/<name>/` |
| **Template-only** | In `templates/skills/` but not in target (never seeded, or intentionally absent) |
| **Target-only** | In `<target>/.claude/skills/` but no template counterpart (e.g. `seed`, `sync`, new user skills) |

All three groups participate in the interactive resolution loop:
- **Paired** skills: full pull / push / diff / skip menu.
- **Template-only** skills: offer `[p] pull` to seed the skill into the target, or `[s] skip`.
- **Target-only** skills: offer `[P] push` to promote to templates, or `[s] skip`.

Also sync companion files alongside `SKILL.md` where they exist (e.g. `usage/probe.sh`). Treat each companion file as its own sync unit with the same pull/push/skip logic.

### Group B — Dockerfile

Single file pair:

| Template | Target |
|---|---|
| `<ae-repo>/templates/Dockerfile` | `<target>/Dockerfile` |

Compare the two. Note: the template contains `{{TOOLCHAIN_SETUP}}` which seed replaces with a stack-specific snippet. If the target Dockerfile has that placeholder resolved, that is expected — do not treat it as a conflict. Flag only changes outside the toolchain block.

### Group C — Scripts

| Template | Target |
|---|---|
| `<ae-repo>/templates/sandbox.sh` | `<target>/scripts/sandbox.sh` |
| `<ae-repo>/templates/auto-engineer.sh` | `<target>/scripts/auto-engineer.sh` |
| `<ae-repo>/templates/restart-loop.sh` | `<target>/scripts/restart-loop.sh` |
| `<ae-repo>/templates/docker-entrypoint.sh` | `<target>/scripts/docker-entrypoint.sh` |

For each script, check whether the target file exists. If not, classify as "template-only" and offer to pull it in.

---

## Step 2 — Diff each paired artifact

For each paired file, read both with the Read tool and compare content. **Do not use shell diff commands.**

**For skills:** Compare section-by-section by splitting on `##` headings. For each heading:
- Present in template only → "inward available"
- Present in target only → "outward candidate"
- Present in both but with differing content → "conflict" or "minor drift"

**For Dockerfile and scripts:** Compare the full content. Assign one of:

| Status | Meaning |
|---|---|
| `in sync` | Files are identical (ignoring resolved `{{TOOLCHAIN_SETUP}}` in Dockerfile) |
| `inward available` | Template has changes absent from target |
| `outward candidate` | Target has changes absent from template |
| `conflict` | Both sides have unique changes |

---

## Step 3 — Present unified summary

Before asking for any action, print a full table grouped by artifact type:

```
Sync summary for <target>:

Skills — Paired:
  auto-engineer    conflict          (both sides have unique sections)
  sdlc             inward available  (template has new "Never" section)
  file-issue       in sync
  wait-for-pr      outward candidate (target has extra polling logic)
  usage            in sync

Skills — Template-only (offer to pull into target):
  context-reset    (not yet in target)

Skills — Target-only (offer to push to templates):
  seed             (harness-internal, push-only)
  sync             (this skill — always skipped)
  <any user-created skills>

Dockerfile:
  in sync | inward available | outward candidate | conflict

Scripts:
  sandbox.sh           in sync
  auto-engineer.sh     inward available  (template updated quota logic)
  restart-loop.sh      in sync
  docker-entrypoint.sh in sync
```

---

## Step 4 — Interactive resolution loop

Process each artifact that is NOT `in sync`, in the order shown in the summary (skills first, then Dockerfile, then scripts).

**For diverging paired artifacts:**

Present the diff (section headings for skills; changed lines for Dockerfile/scripts), then offer:

```
[p] pull  — overwrite target file with template version
[P] push  — overwrite template file with target version
[d] diff  — show full inline comparison (template vs target)
[s] skip  — leave both sides unchanged
```

For **conflict** and **outward candidate** artifacts: always show the diff first. Add a confirmation prompt before applying a pull — the target's changes would be destroyed:

> "This file has local changes that would be overwritten by the pull. Continue? [y/N]"

**For template-only artifacts** (offer to pull into target):

```
[p] pull  — copy template version into target
[s] skip  — leave as-is
```

**For target-only skills** (excluding `sync` itself):

```
[P] push  — copy target file into templates/skills/<name>/SKILL.md
[s] skip  — leave as-is
```

**Placeholder safety check (before any push):** Before pushing any target file back to templates, scan it for resolved project-specific values — e.g. a hardcoded repo name, a resolved `{{GITHUB_USER}}` value, or any literal that looks like it was a placeholder. If found, warn:

> "This file may contain resolved project-specific values. Pushing it to templates could bake them in. Continue anyway? [y/N]"

Only proceed with the push if the user confirms.

---

## Step 5 — Apply changes

Use the **Read** and **Write** tools only — no shell copy commands.

- **Pull (skill):** Read `<ae-repo>/templates/skills/<name>/SKILL.md`, Write to `<target>/.claude/skills/<name>/SKILL.md`.
- **Pull (Dockerfile):** Read `<ae-repo>/templates/Dockerfile`, Write to `<target>/Dockerfile`.
- **Pull (script):** Read `<ae-repo>/templates/<script>.sh`, Write to `<target>/scripts/<script>.sh`.
- **Push (paired skill):** Read `<target>/.claude/skills/<name>/SKILL.md`, Write to `<ae-repo>/templates/skills/<name>/SKILL.md`.
- **Push (target-only skill):** Read `<target>/.claude/skills/<name>/SKILL.md`, Write to `<ae-repo>/templates/skills/<name>/SKILL.md` (creates new template entry).
- **Push (Dockerfile):** Read `<target>/Dockerfile`, Write to `<ae-repo>/templates/Dockerfile`.
- **Push (script):** Read `<target>/scripts/<script>.sh`, Write to `<ae-repo>/templates/<script>.sh`.

Confirm each write succeeded before moving to the next file.

---

## Step 6 — Report

Print a final summary:

```
Sync complete:

  Pulled from template (target updated):
    Skills: sdlc
    Scripts: auto-engineer.sh

  Pushed to template (template updated):
    Skills: wait-for-pr

  Skipped:
    Skills: auto-engineer (conflict, deferred), seed (target-only, skipped)
    Dockerfile: skipped

  In sync (no action needed):
    Skills: file-issue, usage
    Scripts: sandbox.sh, restart-loop.sh, docker-entrypoint.sh

Reminder: pushed changes to templates/ should be committed and PR'd to
dburkart/auto-engineer so they benefit future seeded projects.
```

If any files were pushed to templates, remind the user to commit and open a PR.

---

## Never

- Auto-resolve conflicts — always surface them and let the user decide.
- Push a target file with resolved project-specific placeholder values without explicit user confirmation.
- Sync the `sync` skill itself — it has no template counterpart by design.
- Use shell `cp` or `rsync` — use the Read and Write tools only.
- Modify files outside `<ae-repo>/templates/` and `<target>/` (skills, Dockerfile, scripts) — do not touch playbooks, settings, or `.gitignore`.
- Create commits or push — the user should review and commit synced files themselves.
- Treat a resolved `{{TOOLCHAIN_SETUP}}` in the target Dockerfile as a conflict — that substitution is intentional and expected.
