FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates curl git make sudo \
        gnupg \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
 && curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
 && apt-get install -y --no-install-recommends gh nodejs \
 && npm install -g @anthropic-ai/claude-code \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN if id -u ubuntu >/dev/null 2>&1; then userdel --remove ubuntu; fi \
 && useradd --create-home --shell /bin/bash --uid 1000 agent \
 && echo "agent ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/agent

USER agent
ENV HOME=/home/agent \
    PATH=/home/agent/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# --------------------------------------------------------------------
# Project-specific toolchain setup
#
# Add any language runtime or toolchain installation here. This base
# image intentionally omits language toolchains so it stays minimal.
#
# Examples:
#   Rust:   COPY --chown=agent:agent rust-toolchain.toml /tmp/toolchain/
#           RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
#                   | sh -s -- -y --default-toolchain none --profile minimal \
#            && cd /tmp/toolchain && rustup show active-toolchain
#   Python: RUN pip install --user uv
#   Node:   (already available system-wide via the apt install above)
# --------------------------------------------------------------------

WORKDIR /home/agent/work

COPY --chown=root:root scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/auto-engineer"]
