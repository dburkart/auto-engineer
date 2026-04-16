#!/usr/bin/env bash
# Restart the auto-engineer loop in a fresh container, optionally resuming
# at a specific iteration. Use when /compact is insufficient and a truly
# clean process is needed (context window full, env/credential refresh,
# or prior-cycle residue is corrupting decisions).
#
# Usage:
#   scripts/restart-loop.sh                # start from iteration 1
#   scripts/restart-loop.sh --iteration N  # resume at a specific iteration
#
# The --iteration N flag is forwarded to /auto-engineer so the loop
# continues from where it left off with a blank conversation slate.
#
# Convention: sandbox.sh passes its first argument (e.g. /auto-engineer) to
# the container entrypoint (scripts/docker-entrypoint.sh), which interprets a
# leading-slash argument as a Claude Code skill invocation. Additional args
# (like --iteration N) are appended to the Claude prompt verbatim.
set -euo pipefail
exec "$(dirname "${BASH_SOURCE[0]}")/sandbox.sh" /auto-engineer "$@"
