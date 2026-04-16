# Prioritization Playbook — auto-engineer

## Label taxonomy

### Priority labels (exactly one per issue)

| Label | Color | Meaning | Examples |
|---|---|---|---|
| `priority:P0` | #B60205 (red) | Critical — blocks core functionality | Seed skill produces broken output, Docker entrypoint crashes |
| `priority:P1` | #D93F0B (orange) | High — required for next milestone | Missing template for a supported stack, placeholder not substituted |
| `priority:P2` | #E4E669 (yellow) | Medium — polish and hardening | Better error messages, edge case handling in scripts |
| `priority:P3` | #0E8A16 (green) | Low — nice-to-have or future work | Documentation improvements, new optional features |

### Type labels

| Label | Meaning |
|---|---|
| `bug` | Something isn't working as intended |
| `enhancement` | New feature or improvement to existing functionality |

## Triage rules

1. Every issue gets exactly one `priority:*` label on creation.
2. Issues without a priority label are considered un-triaged and rank below P3.
3. P0 issues are picked first, then P1, P2, P3, then un-triaged.
4. Within a priority bucket, lowest issue number first.

## Picking rules for auto-engineer

1. Filter out issues labeled `blocked`, `needs-discussion`, `question`, `wontfix`.
2. Filter out issues with unresolved dependencies (body references open issues).
3. Sort by priority (P0 > P1 > P2 > P3 > un-triaged), then by issue number.
4. If the top candidate is un-triaged, triage it first (assign priority via `/file-issue` conventions).
5. If no unblocked issues remain, stop.

## When to escalate

- P0 issues that can't be resolved in 3 fix attempts → stop and report to user.
- Issues that require human judgment (architectural decisions, API design) → label `needs-discussion` and skip.
