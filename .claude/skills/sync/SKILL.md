---
name: sync
description: Two-way sync between a seeded project's .claude/skills/ and this auto-engineer repo's templates/skills/. Detects drift in either direction, presents per-skill diffs, and lets you pull from template, push to template, or skip. Harness-internal tool — never seeded into target projects. Invoked as /sync.
argument-hint: [<target-project-path>]
---

# sync

Two-way sync between a seeded project and this auto-engineer repo's templates. Detects drift in either direction and lets you resolve it interactively, skill by skill.

This is a harness-internal development tool. It lives only in `.claude/skills/sync/` — the `seed` skill never copies it to target projects.

## When to invoke

- User says "sync skills", "sync with project", "sync templates", or invokes `/sync`.
- Accepts an optional positional argument: path to the seeded project to sync with.

---

## Step 0 — Get the target path

If not provided as an argument, ask:

> "What's the path to the seeded project you want to sync with? (absolute path)"

Resolve to an absolute path. Verify the directory exists and contains `.claude/skills/` inside it. Abort with a clear error if not found.

All reads and writes to the target project use `<target>/` as the root. All reads and writes to templates use `<ae-repo>/templates/skills/` where `<ae-repo>` is the directory containing this skill file (two levels up from `.claude/skills/sync/`).

---

## Step 1 — Discover skill pairs

Enumerate all skill names on both sides:

- **Template side:** list subdirectory names under `<ae-repo>/templates/skills/` (each subdir with a `SKILL.md` is a syncable skill).
- **Target side:** list subdirectory names under `<target>/.claude/skills/` that have a `SKILL.md`.

Classify each skill name:

| Classification | Condition |
|---|---|
| **Paired** | Present in both `templates/skills/<name>/` and `<target>/.claude/skills/<name>/` |
| **Template-only** | In `templates/skills/` but not in target (never seeded, or intentionally absent) |
| **Target-only** | In `<target>/.claude/skills/` but no template counterpart (e.g. `seed`, `sync`, new user skills) |

Note template-only and target-only skills in the summary, but only paired skills participate in inward sync. Target-only skills are outward-sync candidates.

---

## Step 2 — Diff each paired skill

For each paired skill, read both files with the Read tool and compare content.

**Do not use shell diff commands.** Compare section-by-section by splitting on `##` headings. For each section heading:

- Present in template only → "inward available" (template has content the target is missing)
- Present in target only → "outward candidate" (target has content the template is missing)
- Present in both but with differing content → "conflict" or "minor drift" depending on extent

Assign an overall status per skill:

| Status | Meaning |
|---|---|
| `in sync` | Files are identical |
| `inward available` | Template has additions/changes absent from target |
| `outward candidate` | Target has additions/changes absent from template |
| `conflict` | Both sides have unique changes |

---

## Step 3 — Present unified summary

Before asking for any action, print a full table of all skills:

```
Sync summary for <target>:

Paired skills:
  auto-engineer    conflict          (both sides have unique sections)
  sdlc             inward available  (template has new "Never" section)
  file-issue       in sync
  wait-for-pr      outward candidate (target has extra polling logic)
  usage            in sync
  context-reset    inward available  (template updated trigger conditions)

Template-only (not in target — skipped):
  <none> | <list>

Target-only (no template counterpart):
  seed             (harness-internal, push-only)
  sync             (this skill, skip)
  <any user-created skills>
```

---

## Step 4 — Interactive resolution loop

Process each skill that is NOT `in sync`, in the order shown in the summary.

For each diverging **paired** skill, present the diff (section headings that differ), then offer:

```
[p] pull  — overwrite target file with template version
[P] push  — overwrite template file with target version
[d] diff  — show full inline comparison (template vs target)
[s] skip  — leave both sides unchanged
```

For **conflict** skills: always show the diff first before asking for action. Do not auto-resolve conflicts.

For **target-only** skills (excluding `sync` itself): offer only:

```
[P] push  — copy target file into templates/skills/<name>/SKILL.md (creates new template)
[s] skip  — leave as-is
```

**Placeholder safety check (before any push):** Before pushing a target file back to templates, scan it for patterns that look like resolved project-specific values — e.g. a hardcoded repo name like `dburkart/my-project`, a resolved `{{GITHUB_USER}}` value, or any string that was a placeholder in the template but is now a literal value in the target. If found, warn:

> "This file contains what may be resolved placeholder values (e.g. 'my-project-name'). Pushing it to templates could bake in project-specific values. Continue anyway? [y/N]"

Only proceed with the push if the user confirms.

---

## Step 5 — Apply changes

Use the **Read** and **Write** tools only — no shell copy commands.

- **Pull:** Read `<ae-repo>/templates/skills/<name>/SKILL.md`, Write to `<target>/.claude/skills/<name>/SKILL.md`.
- **Push (paired):** Read `<target>/.claude/skills/<name>/SKILL.md`, Write to `<ae-repo>/templates/skills/<name>/SKILL.md`.
- **Push (target-only):** Read `<target>/.claude/skills/<name>/SKILL.md`, Write to `<ae-repo>/templates/skills/<name>/SKILL.md` (creates new template entry).

Confirm each write succeeded before moving to the next skill.

---

## Step 6 — Report

Print a final summary:

```
Sync complete:

  Pulled from template (target updated):
    sdlc, context-reset

  Pushed to template (template updated):
    wait-for-pr

  Skipped:
    auto-engineer (conflict, deferred)

  In sync (no action needed):
    file-issue, usage

Reminder: pushed changes to templates/ should be committed and PR'd to
dburkart/auto-engineer so they benefit future seeded projects.
```

If any skills were pushed to templates, remind the user to commit and open a PR so the improvements flow back to the canonical source.

---

## Never

- Auto-resolve conflicts — always surface them and let the user decide.
- Push a target file with resolved project-specific placeholder values without explicit user confirmation.
- Sync the `sync` skill itself (this file) — it has no template counterpart by design.
- Use shell `cp` or `rsync` — use the Read and Write tools only.
- Modify files outside `<ae-repo>/templates/skills/` and `<target>/.claude/skills/` — do not touch playbooks, Dockerfiles, scripts, or settings.
- Create commits or push — the user should review and commit synced files themselves.
