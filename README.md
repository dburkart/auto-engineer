# auto-engineer

A general-purpose Claude Code toolkit for autonomous, closed-loop software delivery. Run it from this repo to seed any project with the skills and Docker infrastructure Claude needs to pick issues, implement changes, push PRs, respond to CI and review feedback, and merge — without human intervention between steps.

Inspired by auto-researcher by @karpathy.

This toolkit is a starting off point; in order for it to be effective in your project, you will have to think critically about the autonomous software development lifecycle. Different projects require different things!

## Demo

Perhaps you want to see a demo first, before deciding if this is for you.
Check out [vibix](https://github.com/dburkart/vibix), an autonomously developed operating system.

## What's included

| Skill | Description |
|---|---|
| `/seed` | One-time setup: asks for a target project path, detects its stack, writes customized skills and Docker files into it |
| `/auto-engineer` | The main loop: pick → plan → implement → PR → wait → merge → repeat *(written into target by `/seed`)* |
| `/auto-manager` | Epic orchestrator: scope a fuzzy topic or parent issue, file sub-issues, plan workstreams, and spawn parallel `/auto-engineer` subagents to ship the whole epic *(written into target)* |
| `/sdlc` | Branch, commit, and PR conventions *(written into target)* |
| `/file-issue` | File GitHub issues with correct labels *(written into target)* |
| `/wait-for-pr` | Manual PR-wait loop with CI polling and auto-fix *(written into target)* |
| `/usage` | Session quota check used by the auto-engineer quota gate *(written into target)* |

Plus Docker infrastructure (`scripts/sandbox.sh`, `Dockerfile`) so the loop runs safely with `--dangerously-skip-permissions` in an isolated container.

## Seeding a project

Open Claude Code in this repo and run:

```
/seed
```

Claude will ask for the path to your target project, then:
1. Auto-detect the tech stack and GitHub configuration
2. Ask a few questions about labels and playbooks
3. Write customized skills, Docker files, and settings directly into the target project

The seed skill never touches any pre-existing `.claude/` content in the target — it only creates files that don't already exist.

## After seeding

In the target project, review and commit the generated files, then:

```sh
# Start the autonomous loop in a container
scripts/auto-engineer.sh

# Run any skill or prompt in the container
scripts/sandbox.sh /some-skill
scripts/sandbox.sh -- /auto-engineer --iteration 1
```

### Docker prerequisites

- Docker installed and running
- Host Claude Code login (`~/.claude` + `~/.claude.json`)
- `GITHUB_TOKEN` in your environment or in `.env` at the project root

The container mounts your host `~/.claude` for auth reuse. The base `Dockerfile` has no language toolchain — add yours in the toolchain section before building.

## Playbooks

The seeded skills optionally reference playbook files that hold project-specific policy:

| Playbook | Contents |
|---|---|
| `sdlc.md` | Branch naming, commit format, PR process |
| `build-run.md` | How to build and run the project locally |
| `testing.md` | Test strategy, CI matrix, how to run tests |
| `pr-review.md` | CI readiness criteria, review classification rules |
| `prioritization.md` | Issue label taxonomy, priority definitions, triage rules |

`/seed` can create stub versions of these for you to fill in. If you skip playbooks, policy is inlined into the skills directly.

## Re-seeding

Run `/seed` from this repo again at any time to add skills that were missing or update Docker files. Existing skills and playbooks are never overwritten.
