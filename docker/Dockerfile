FROM node:24-alpine

RUN apk add --no-cache git curl bash ca-certificates

RUN npm install -g @anthropic-ai/claude-code

WORKDIR /workspace

CMD ["bash"]
