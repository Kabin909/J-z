#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail(){ echo "ERROR: $*" >&2; exit 1; }
[[ -f "$ROOT/package.json" ]] || fail "package.json missing"
[[ -f "$ROOT/.env.example" ]] || fail ".env.example missing"
[[ -f "$ROOT/docker-compose.yml" ]] || fail "docker-compose.yml missing"
for f in apps/api/src/index.ts apps/worker/src/index.ts apps/ws/src/index.ts; do
  [[ -f "$ROOT/$f" ]] || fail "$f missing"
done
grep -q "import Redis from 'ioredis'" "$ROOT/apps/worker/src/index.ts" || fail "worker Redis import not fixed"
grep -q "import Redis from 'ioredis'" "$ROOT/apps/api/src/index.ts" || fail "api Redis import not fixed"
docker compose -f "$ROOT/docker-compose.yml" config >/dev/null || fail "invalid docker compose"
echo "J&Z preflight: OK"
