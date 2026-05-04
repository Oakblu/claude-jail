FROM node:24-alpine

RUN apk add --no-cache git curl bash ca-certificates unzip python3 py3-pip rust cargo

RUN npm install -g @anthropic-ai/claude-code pnpm

RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"

WORKDIR /workspace

CMD ["bash"]
