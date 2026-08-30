#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
printf '\033[38;5;208mJ&Z PANEL\033[0m — CodeSandbox development bootstrap\n\n'
if [[ ! -f .env ]]; then
  if [[ -f .env.codesandbox.example ]]; then cp .env.codesandbox.example .env; fi
  echo "Created .env from .env.codesandbox.example."
  echo "Set DATABASE_URL and REDIS_URL before starting the API."
fi
if grep -q 'replace-with-' .env 2>/dev/null; then
  echo "WARNING: development secrets are still placeholders. Replace them before sharing this sandbox."
fi
npm install
printf '\n\033[32mStarting J&Z web + API...\033[0m\n'
npx concurrently -k "npm --workspace apps/api run dev" "npm --workspace apps/web run dev -- --host 0.0.0.0"
