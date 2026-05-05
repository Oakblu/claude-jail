FROM node:lts-slim

RUN apt-get update && apt-get install -y \
    python3 python3-pip curl git bash ca-certificates unzip \
    && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --default-toolchain stable --profile minimal \
    && chmod -R a+w /usr/local/rustup /usr/local/cargo \
    && rm -rf /usr/local/cargo/registry

ENV BUN_INSTALL=/usr/local/bun \
    PATH=/usr/local/bun/bin:$PATH

RUN curl -fsSL https://bun.sh/install | bash \
    && chmod -R a+rx /usr/local/bun

RUN corepack enable yarn pnpm && npm install -g @anthropic-ai/claude-code

RUN userdel node && useradd -m -u 1000 -s /bin/bash claude \
    && mkdir -p /workspace && chown claude:claude /workspace

WORKDIR /workspace

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER claude

ENTRYPOINT ["/entrypoint.sh"]
