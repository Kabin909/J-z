#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"
printf '\033[38;5;208mJ&Z Panel — macOS installer\033[0m\n'
if ! command -v docker >/dev/null 2>&1; then
  echo 'Docker Desktop is required. Install it, start it, then rerun this installer.'
  exit 1
fi
if [ ! -f .env ]; then cp .env.example .env; fi
if command -v openssl >/dev/null 2>&1; then
  for key in POSTGRES_PASSWORD JWT_SECRET COOKIE_SECRET WINGS_SHARED_SECRET NODE_ENCRYPTION_KEY JZ_BOOTSTRAP_TOKEN; do
    val="$(openssl rand -hex 32)"
    sed -i.bak -E "s|^${key}=.*$|${key}=${val}|" .env
  done
  rm -f .env.bak
  PG=$(grep '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)
  sed -i.bak -E "s|^DATABASE_URL=.*$|DATABASE_URL=postgresql://jz:${PG}@postgres:5432/jz|" .env
  rm -f .env.bak
fi
docker compose up -d --build postgres redis api worker ws web
echo 'J&Z Panel is running at http://localhost:5173'
echo 'For real J&Z Wings, use a Linux VPS/VM or WSL2 Linux node.'
