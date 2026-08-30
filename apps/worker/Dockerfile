FROM node:22-alpine
WORKDIR /app
COPY package.json ./
COPY apps/worker/package.json apps/worker/package.json
RUN npm install --omit=optional --no-audit --no-fund
COPY apps/worker apps/worker
RUN npm --workspace @jz/worker run build
USER node
CMD ["node","apps/worker/dist/index.js"]
