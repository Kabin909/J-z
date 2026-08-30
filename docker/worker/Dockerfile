FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
COPY apps/worker/package.json apps/worker/package.json
COPY apps/api/package.json apps/api/package.json
COPY apps/web/package.json apps/web/package.json
COPY apps/ws/package.json apps/ws/package.json
RUN npm install
COPY apps/worker apps/worker
COPY packages packages
RUN npm --workspace @jz/worker run build
CMD ["npm","--workspace","@jz/worker","run","start"]
