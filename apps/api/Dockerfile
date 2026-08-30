FROM node:22-alpine
WORKDIR /app
COPY package.json ./
COPY apps/api/package.json apps/api/package.json
RUN npm install --omit=optional --no-audit --no-fund
COPY apps/api apps/api
RUN npm --workspace @jz/api run build
USER node
CMD ["node","apps/api/dist/index.js"]
