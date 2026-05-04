FROM node:latest

RUN apt-get update && apt-get install -y \
    git curl bash ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

WORKDIR /workspace

CMD ["bash"]
