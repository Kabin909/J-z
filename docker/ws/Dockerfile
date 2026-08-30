FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
COPY apps/ws/package.json apps/ws/package.json
RUN npm install
COPY apps/ws apps/ws
CMD ["npm","--workspace","@jz/ws","run","dev"]
