FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
COPY apps/ws/package.json apps/ws/package.json
COPY apps/api/package.json apps/api/package.json
COPY apps/web/package.json apps/web/package.json
COPY apps/worker/package.json apps/worker/package.json
RUN npm install
COPY apps/ws apps/ws
RUN npm --workspace @jz/ws run build
CMD ["npm","--workspace","@jz/ws","run","start"]
