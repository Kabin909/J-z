FROM node:22-alpine
WORKDIR /app
COPY package.json ./
COPY apps/ws/package.json apps/ws/package.json
RUN npm install --omit=optional --no-audit --no-fund
COPY apps/ws apps/ws
RUN npm --workspace @jz/ws run build
USER node
CMD ["node","apps/ws/dist/index.js"]
