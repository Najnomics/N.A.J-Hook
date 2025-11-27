# syntax=docker/dockerfile:1.7-labs

# EigenCompute requires linux/amd64 and root (per docs)
FROM --platform=linux/amd64 node:20-slim AS base
WORKDIR /app

ENV NODE_ENV=production

COPY package.json package-lock.json* ./

RUN npm install --omit=dev && npm cache clean --force

COPY tsconfig.json ./tsconfig.json
COPY src ./src

RUN npm run build && rm -rf src

EXPOSE 8080

CMD ["node", "dist/index.js"]

