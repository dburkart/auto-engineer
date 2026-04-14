#!/usr/bin/env bash
# Convenience wrapper: run the /auto-engineer skill in the sandbox container.
# For custom prompts or other skills use scripts/sandbox.sh directly.
set -euo pipefail
exec "$(dirname "${BASH_SOURCE[0]}")/sandbox.sh" /auto-engineer "$@"
