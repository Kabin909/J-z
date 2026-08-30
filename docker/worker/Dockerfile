FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
COPY apps/worker/package.json apps/worker/package.json
RUN npm install
COPY apps/worker apps/worker
CMD ["npm","--workspace","@jz/worker","run","dev"]
