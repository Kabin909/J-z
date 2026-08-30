#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${1:?project root required}"
ENV_FILE="$ROOT/.env"
EXAMPLE="$ROOT/.env.example"

mkdir -p "$ROOT"
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 48
  else
    python3 - <<'PY'
import secrets
print(secrets.token_hex(48))
PY
  fi
}

set_env() {
  local key="$1" value="$2"
  python3 - "$ENV_FILE" "$key" "$value" <<'PY'
from pathlib import Path
import sys, re
p=Path(sys.argv[1]); key=sys.argv[2]; value=sys.argv[3]
text=p.read_text() if p.exists() else ""
line=f"{key}={value}"
pat=re.compile(rf"^{re.escape(key)}=.*$", re.M)
if pat.search(text):
    text=pat.sub(lambda _: line, text)
else:
    if text and not text.endswith("\n"): text += "\n"
    text += line + "\n"
p.write_text(text)
PY
}

get_env() {
  local key="$1"
  grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- || true
}

# Seed non-secret defaults from .env.example, if present.
if [[ -f "$EXAMPLE" ]]; then
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
    key="${line%%=*}"
    [[ -n "$(get_env "$key")" ]] || set_env "$key" "${line#*=}"
  done < "$EXAMPLE"
fi

PANEL_ORIGIN="${PANEL_ORIGIN:-${WEB_ORIGIN:-http://localhost}}"
POSTGRES_PASSWORD="$(get_env POSTGRES_PASSWORD)"
JWT_SECRET="$(get_env JWT_SECRET)"
COOKIE_SECRET="$(get_env COOKIE_SECRET)"
WINGS_SHARED_SECRET="$(get_env WINGS_SHARED_SECRET)"

[[ -n "$POSTGRES_PASSWORD" ]] || POSTGRES_PASSWORD="$(secret)"
[[ -n "$JWT_SECRET" ]] || JWT_SECRET="$(secret)"
[[ -n "$COOKIE_SECRET" ]] || COOKIE_SECRET="$(secret)"
[[ -n "$WINGS_SHARED_SECRET" ]] || WINGS_SHARED_SECRET="$(secret)"

set_env NODE_ENV "${NODE_ENV:-production}"
set_env APP_NAME "${APP_NAME:-J&Z Panel}"
set_env PANEL_ORIGIN "$PANEL_ORIGIN"
set_env WEB_ORIGIN "${WEB_ORIGIN:-$PANEL_ORIGIN}"
set_env CORS_ORIGIN "${CORS_ORIGIN:-$PANEL_ORIGIN}"

set_env API_HOST "${API_HOST:-0.0.0.0}"
set_env API_PORT "${API_PORT:-4000}"
set_env WEB_HOST "${WEB_HOST:-0.0.0.0}"
set_env WEB_PORT "${WEB_PORT:-5173}"
set_env WS_HOST "${WS_HOST:-0.0.0.0}"
set_env WS_PORT "${WS_PORT:-4001}"

set_env POSTGRES_HOST "${POSTGRES_HOST:-postgres}"
set_env POSTGRES_PORT "${POSTGRES_PORT:-5432}"
set_env POSTGRES_DB "${POSTGRES_DB:-jz}"
set_env POSTGRES_USER "${POSTGRES_USER:-jz}"
set_env POSTGRES_PASSWORD "$POSTGRES_PASSWORD"

# URL-encode the password so special characters cannot break DATABASE_URL.
DATABASE_URL="$(python3 - "$POSTGRES_USER" "$POSTGRES_PASSWORD" "$POSTGRES_HOST" "$POSTGRES_PORT" "$POSTGRES_DB" <<'PY'
from urllib.parse import quote
import sys
u,p,h,port,d=sys.argv[1:]
print(f"postgresql://{quote(u, safe='')}:{quote(p, safe='')}@{h}:{port}/{d}")
PY
)"
set_env DATABASE_URL "$DATABASE_URL"

set_env REDIS_HOST "${REDIS_HOST:-redis}"
set_env REDIS_PORT "${REDIS_PORT:-6379}"
set_env REDIS_URL "${REDIS_URL:-redis://redis:6379}"

set_env JWT_SECRET "$JWT_SECRET"
set_env COOKIE_SECRET "$COOKIE_SECRET"
set_env WINGS_SHARED_SECRET "$WINGS_SHARED_SECRET"

# Optional installer-provided values.
[[ -n "${ADMIN_USERNAME:-}" ]] && set_env ADMIN_USERNAME "$ADMIN_USERNAME"
[[ -n "${ADMIN_EMAIL:-}" ]] && set_env ADMIN_EMAIL "$ADMIN_EMAIL"
[[ -n "${ADMIN_PASSWORD:-}" ]] && set_env ADMIN_PASSWORD "$ADMIN_PASSWORD"
[[ -n "${JZ_BOOTSTRAP_TOKEN:-}" ]] && set_env JZ_BOOTSTRAP_TOKEN "$JZ_BOOTSTRAP_TOKEN"

chmod 600 "$ENV_FILE"
echo "Generated/validated $ENV_FILE"
