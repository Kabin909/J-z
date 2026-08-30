#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "[1/4] Shell syntax"
bash -n "$ROOT/install.sh"
bash -n "$ROOT/installer/install.sh"
bash -n "$ROOT/installer/generate-env.sh"
echo "[2/4] Compose syntax"
if command -v docker >/dev/null 2>&1 && [[ -f "$ROOT/docker-compose.yml" ]]; then
  (cd "$ROOT" && docker compose config >/dev/null)
else
  echo "Docker/compose unavailable; skipped runtime compose validation."
fi
echo "[3/4] Required installer files"
test -x "$ROOT/install.sh"
test -x "$ROOT/installer/install.sh"
test -x "$ROOT/installer/generate-env.sh"
test -f "$ROOT/.env.example"
echo "[4/4] Done"

# Migration runner validation
bash -n "$(dirname "$0")/migrate.sh"
test -x "$(dirname "$0")/migrate.sh"
