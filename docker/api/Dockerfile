FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
COPY apps/api/package.json apps/api/package.json
COPY apps/web/package.json apps/web/package.json
COPY apps/worker/package.json apps/worker/package.json
COPY apps/ws/package.json apps/ws/package.json
COPY packages/db packages/db
RUN npm install
COPY . .
RUN npm --workspace @jz/api run build
CMD ["npm","--workspace","@jz/api","run","start"]
