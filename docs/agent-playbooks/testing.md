# Testing Playbook — auto-engineer

## Current state

This project has no automated test suite. The project consists of markdown skill definitions, shell scripts, and Dockerfile templates — none of which have unit tests.

## Verification strategy

Since there are no automated tests, verification is manual:

1. **Skill syntax**: ensure SKILL.md files have valid YAML frontmatter and no unresolved `{{PLACEHOLDER}}` values in non-template files.
2. **Shell scripts**: verify scripts are syntactically valid with `bash -n <script>`.
3. **Docker build**: `scripts/sandbox.sh --build-only` confirms the Dockerfile builds without errors.
4. **Seeding**: run `/seed` against a scratch repo to confirm end-to-end template substitution works.

## Self-review as a testing proxy

Because there are no CI tests, the SDLC skill requires a self-review step before merging any PR. The self-review subagent (a "Senior prompt engineer") checks for:

- Correctness of prompt instructions and skill logic
- Unresolved or mismatched placeholders
- Shell script safety issues
- Consistency between skills that reference each other

## Future considerations

If the project grows to include code beyond templates and skills, add:
- `shellcheck` for shell script linting
- A CI workflow that validates YAML frontmatter in SKILL.md files
- Integration tests that seed a temp repo and verify the output
