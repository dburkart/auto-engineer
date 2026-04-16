# PR Review Playbook — auto-engineer

## CI readiness

This project has no CI workflows. PR readiness is determined entirely by self-review (see below).

## Self-review process

Since there are no review bots or CI tests, every PR must complete a self-review cycle before merge:

1. Spawn a review subagent as a **Senior prompt engineer**.
2. The reviewer evaluates the diff for:
   - **Correctness**: do the skill instructions achieve their stated goal?
   - **Consistency**: do cross-references between skills match (e.g. playbook paths, placeholder names)?
   - **Safety**: are shell scripts safe (no unquoted variables, proper error handling)?
   - **Clarity**: are instructions unambiguous for an LLM executor?
   - **Completeness**: are edge cases addressed? Are "never" rules comprehensive?
3. Keep the review under 400 words.

## Finding classification

| Category | Action |
|---|---|
| **Actionable bug** | Must fix before merge — incorrect logic, broken references, security issue |
| **In-scope nit** | Fix if quick — wording improvements, minor clarifications |
| **Out-of-scope suggestion** | Defer with a comment + follow-up issue via `/file-issue` |

## Review bot timeout

Since no review bots are configured, the 30-minute bot timeout applies. After 30 minutes with no external review, proceed with self-review findings only.
