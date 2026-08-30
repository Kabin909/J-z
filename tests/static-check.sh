#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -f "$ROOT/installer/install.sh"
test -f "$ROOT/installer/jz-panel"
test -f "$ROOT/docker-compose.yml"
test -f "$ROOT/.env.example"
test -f "$ROOT/apps/api/src/index.ts"
test -f "$ROOT/apps/web/src/main.tsx"
test -f "$ROOT/wings/main.go"
bash -n "$ROOT/installer/install.sh"
bash -n "$ROOT/installer/jz-panel"
echo 'static checks: OK'
