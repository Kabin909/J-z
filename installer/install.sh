#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="3.2.0"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
STATE="/etc/jz-panel"
LOG="/var/log/jz-panel-install.log"
BACKUP_DIR="$STATE/rollback"
LOCK_FILE="/run/lock/jz-panel-install.lock"
NGINX_CONF="/etc/nginx/sites-available/jz-panel.conf"
NGINX_LINK="/etc/nginx/sites-enabled/jz-panel.conf"
ACME_ROOT="/var/www/jz-panel-acme"

mkdir -p "$STATE" "$BACKUP_DIR" /run/lock
install -m 600 /dev/null "$LOG"
exec > >(tee -a "$LOG") 2>&1

ROLLBACK_NEEDED=0
ROLLBACK_DONE=0
STACK_WAS_PRESENT=0
STACK_WAS_RUNNING=0
PREV_ENV_BACKUP=""
PREV_NGINX_BACKUP=""
DEFAULT_SITE_WAS_ENABLED=0
DEFAULT_SITE_BACKUP=""
UFW_WAS_ACTIVE=0
UFW_WAS_INSTALLED=0
UFW_ADDED_RULES=()
declare -A PREV_APP_IMAGES=()
HTTPS_ENABLED=0
CERT_CREATED=0

cleanup(){ rm -f "$LOCK_FILE" 2>/dev/null || true; }

rollback(){
  local rc="${1:-1}"
  [[ "$ROLLBACK_NEEDED" -eq 1 && "$ROLLBACK_DONE" -eq 0 ]] || return 0
  ROLLBACK_DONE=1
  echo
  section "↩️ Transaction failed — restoring previous state"
  set +e

  if [[ -f "$ROOT/docker-compose.yml" ]]; then
    cd "$ROOT"
    if (( STACK_WAS_PRESENT == 1 )); then
      docker compose --env-file "$ROOT/.env" down --remove-orphans >/dev/null 2>&1 || true
    else
      docker compose --env-file "$ROOT/.env" down --remove-orphans >/dev/null 2>&1 || true
    fi
  fi

  if [[ -n "$PREV_ENV_BACKUP" && -f "$PREV_ENV_BACKUP" ]]; then
    cp -f "$PREV_ENV_BACKUP" "$ROOT/.env"
    chmod 600 "$ROOT/.env"
  else
    rm -f "$ROOT/.env"
  fi

  if [[ -n "$PREV_NGINX_BACKUP" && -f "$PREV_NGINX_BACKUP" ]]; then
    cp -f "$PREV_NGINX_BACKUP" "$NGINX_CONF"
    ln -sfn "$NGINX_CONF" "$NGINX_LINK"
  else
    rm -f "$NGINX_LINK" "$NGINX_CONF"
  fi

  if (( DEFAULT_SITE_WAS_ENABLED == 1 )); then
    if [[ -n "$DEFAULT_SITE_BACKUP" && -f "$DEFAULT_SITE_BACKUP" ]]; then
      cp -f "$DEFAULT_SITE_BACKUP" /etc/nginx/sites-enabled/default
    fi
  else
    rm -f /etc/nginx/sites-enabled/default
  fi

  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true

  if (( STACK_WAS_PRESENT == 1 )); then
    for svc in api worker ws web; do
      if [[ -n "${PREV_APP_IMAGES[$svc]:-}" ]]; then
        docker tag "${PREV_APP_IMAGES[$svc]}" "jz-panel-${svc}:latest" >/dev/null 2>&1 || true
      fi
    done
  fi
  if (( STACK_WAS_RUNNING == 1 )) && [[ -f "$ROOT/.env" ]]; then
    cd "$ROOT"
    docker compose --env-file "$ROOT/.env" up -d --remove-orphans >/dev/null 2>&1 || true
  fi

  for rule in "${UFW_ADDED_RULES[@]}"; do
    ufw delete allow "$rule" >/dev/null 2>&1 || true
  done
  if (( UFW_WAS_ACTIVE == 0 )); then
    ufw disable >/dev/null 2>&1 || true
  fi

  if (( CERT_CREATED == 1 )); then
    warn "A new Let's Encrypt certificate may remain in /etc/letsencrypt; certificate files were not deleted during rollback."
  fi

  echo "↩️ Previous configuration restored."
  if (( STACK_WAS_RUNNING == 1 )); then echo "↩️ Previous Docker stack restart attempted."; fi
  echo "💾 Database volumes and Docker images were preserved."
  echo "📋 Log: $LOG"
  return "$rc"
}

on_error(){ local rc=$?; echo "❌ Installer failed at line ${1:-unknown} (exit $rc)."; rollback "$rc" || true; exit "$rc"; }
trap 'on_error "$LINENO"' ERR
trap cleanup EXIT

ok(){ echo "✅ $*"; }
warn(){ echo "⚠️  $*"; }
die(){ echo "❌ $*"; return 1; }
section(){ printf '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n%s\n' "$*"; }

require_root(){ [[ $EUID -eq 0 ]] || die "Run as root: sudo bash install.sh"; }
acquire_lock(){ [[ ! -e "$LOCK_FILE" ]] || die "Another J&Z installer is already running."; : > "$LOCK_FILE"; }

check_os(){
  section "🩺 System preflight"
  . /etc/os-release
  case "$ID" in
    debian) [[ "${VERSION_ID%%.*}" -ge 12 ]] || die "Debian 12+ required.";;
    ubuntu) [[ "${VERSION_ID%%.*}" -ge 22 ]] || die "Ubuntu 22.04+ required.";;
    *) die "Supported OS: Debian 12+ or Ubuntu 22.04+.";;
  esac
  case "$(dpkg --print-architecture)" in amd64|arm64) ;; *) die "Supported architecture: amd64/arm64.";; esac
  ok "$PRETTY_NAME / $(dpkg --print-architecture)"
}

check_resources(){
  local mem disk
  mem="$(awk '/MemTotal/{printf "%d",$2/1024}' /proc/meminfo)"
  disk="$(df -Pk "$ROOT" | awk 'NR==2{printf "%d",$4/1024/1024}')"
  echo "CPU: $(nproc) / RAM: ${mem} MiB / Free disk: ${disk} GiB"
  (( disk >= 5 )) || die "At least 5 GiB free disk space is required."
  (( mem >= 1024 )) || warn "Less than 1 GiB RAM; Docker builds may be unstable."
}

fix_duplicate_sury(){
  local a=/etc/apt/sources.list.d/php.list b=/etc/apt/sources.list.d/sury-php.list
  if [[ -f "$a" && -f "$b" ]] && grep -q packages.sury.org/php "$a" && grep -q packages.sury.org/php "$b"; then
    cp -a "$a" "$STATE/php.list.$(date +%Y%m%d-%H%M%S).bak"
    mv -f "$a" "$a.disabled-by-jz"
    warn "Disabled duplicate Sury PHP repository: $a"
  fi
}

apt_install(){
  section "📦 System dependencies"
  export DEBIAN_FRONTEND=noninteractive
  fix_duplicate_sury
  apt-get update -y
  apt-get install -y ca-certificates curl git jq openssl python3 nginx ufw dnsutils lsof procps iproute2
  systemctl enable --now nginx
}

install_docker(){
  section "🐳 Docker"
  if ! command -v docker >/dev/null 2>&1; then apt-get install -y docker.io; fi
  if ! docker compose version >/dev/null 2>&1; then apt-get install -y docker-compose-plugin; fi
  systemctl enable --now docker
  docker info >/dev/null 2>&1 || die "Docker daemon is unavailable."
  docker compose version >/dev/null 2>&1 || die "Docker Compose is unavailable."
  ok "$(docker --version) / $(docker compose version --short)"
}

valid_domain(){ [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]; }
valid_ipv4(){ [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1; local IFS=. a; read -ra a <<< "$1"; for x in "${a[@]}"; do ((x<=255)) || return 1; done; }
valid_email(){ [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; }
public_ip(){ curl -4fsS --max-time 8 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}'; }
secret(){ openssl rand -hex 48; }

prompt_config(){
  section "⚙️ Panel configuration"
  read -rp "🌐 Panel domain (blank = VPS IPv4): " PANEL_DOMAIN
  PANEL_DOMAIN="${PANEL_DOMAIN//[[:space:]]/}"
  if [[ -n "$PANEL_DOMAIN" ]]; then
    valid_domain "$PANEL_DOMAIN" || die "Invalid domain: $PANEL_DOMAIN"
    PANEL_HOST="$PANEL_DOMAIN"; USE_DOMAIN=1
  else
    PANEL_HOST="$(public_ip)"; valid_ipv4 "$PANEL_HOST" || die "Could not determine public IPv4."; USE_DOMAIN=0
  fi
  read -rp "👤 Admin username [admin]: " ADMIN_USERNAME; ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
  [[ "$ADMIN_USERNAME" =~ ^[A-Za-z0-9_.-]{3,32}$ ]] || die "Invalid admin username."
  read -rp "📧 Admin email: " ADMIN_EMAIL; valid_email "$ADMIN_EMAIL" || die "Invalid admin email."
  while :; do read -rsp "🔑 Admin password (12+ chars): " ADMIN_PASSWORD; echo; (( ${#ADMIN_PASSWORD} >= 12 )) && break; warn "Password must be at least 12 characters."; done
  PANEL_ORIGIN="http://${PANEL_HOST}"
}

check_dns(){
  (( USE_DOMAIN == 1 )) || return 0
  section "🌐 DNS check"
  local resolved public
  resolved="$(getent ahostsv4 "$PANEL_DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u || true)"
  [[ -n "$resolved" ]] || die "$PANEL_DOMAIN does not resolve. Create its A record first."
  public="$(public_ip || true)"
  echo "$PANEL_DOMAIN -> $resolved"
  if [[ -n "$public" ]] && ! grep -qx "$public" <<< "$resolved"; then
    warn "DNS does not point to detected VPS IP $public."
    read -rp "Continue anyway? [y/N]: " a
    [[ "${a,,}" == y ]] || die "DNS check cancelled."
  else ok "DNS is aligned with this VPS."; fi
}

check_ports(){
  section "🔌 Port check"
  for p in 80 443; do
    local hit; hit="$(ss -ltnp "sport = :$p" 2>/dev/null | tail -n +2 || true)"
    [[ -z "$hit" ]] && { ok "Port $p available."; continue; }
    if grep -qi nginx <<< "$hit"; then ok "Port $p already belongs to Nginx."; else
      echo "$hit"; read -rp "Port $p is occupied. Continue? [y/N]: " a; [[ "${a,,}" == y ]] || die "Port check cancelled."
    fi
  done
}

backup_current(){
  section "💾 Rollback snapshot"
  local stamp="$(date +%Y%m%d-%H%M%S)"
  if [[ -f "$ROOT/.env" ]]; then PREV_ENV_BACKUP="$BACKUP_DIR/env.$stamp.bak"; cp -a "$ROOT/.env" "$PREV_ENV_BACKUP"; fi
  if [[ -f "$NGINX_CONF" ]]; then PREV_NGINX_BACKUP="$BACKUP_DIR/nginx.$stamp.bak"; cp -a "$NGINX_CONF" "$PREV_NGINX_BACKUP"; fi
  if [[ -e /etc/nginx/sites-enabled/default ]]; then
    DEFAULT_SITE_WAS_ENABLED=1
    DEFAULT_SITE_BACKUP="$BACKUP_DIR/default.$stamp.bak"
    cp -a /etc/nginx/sites-enabled/default "$DEFAULT_SITE_BACKUP"
  fi
  if command -v ufw >/dev/null 2>&1; then
    ufw status | grep -q '^Status: active' && UFW_WAS_ACTIVE=1 || UFW_WAS_ACTIVE=0
  fi
  if [[ -f "$ROOT/docker-compose.yml" ]] && docker compose --env-file "$ROOT/.env" ps -q >/dev/null 2>&1; then
    STACK_WAS_PRESENT=1
    for svc in api worker ws web; do
      local image_id
      image_id="$(docker compose --env-file "$ROOT/.env" images -q "$svc" 2>/dev/null | head -n1 || true)"
      [[ -n "$image_id" ]] && PREV_APP_IMAGES["$svc"]="$image_id"
    done
    if [[ -n "$(docker compose --env-file "$ROOT/.env" ps -q 2>/dev/null)" ]]; then
      if docker compose --env-file "$ROOT/.env" ps --status running -q 2>/dev/null | grep -q .; then STACK_WAS_RUNNING=1; fi
    fi
  fi
  ok "Rollback snapshot ready. Existing stack running=$STACK_WAS_RUNNING."
}

upsert_env(){
  python3 - "$1" "$2" "$3" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); k=sys.argv[2]; v=sys.argv[3]
s=p.read_text() if p.exists() else ''
line=f'{k}={v}'
pat=rf'^{re.escape(k)}=.*$'
s=re.sub(pat,lambda _:line,s,flags=re.M) if re.search(pat,s,re.M) else (s + ('\n' if s and not s.endswith('\n') else '') + line + '\n')
p.write_text(s)
PY
}

get_env(){
  local key="$1" file="${2:-$ROOT/.env}"
  [[ -f "$file" ]] || return 1
  awk -F= -v k="$key" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$file"
}

pg_url_password(){
  python3 - "$1" <<'PY2'
from urllib.parse import quote
import sys
print(quote(sys.argv[1], safe=""))
PY2
}

write_env(){
  section "🔐 Generating .env"
  [[ -f "$ROOT/.env.example" ]] || die "Missing $ROOT/.env.example"
  [[ -f "$ROOT/.env" ]] || cp "$ROOT/.env.example" "$ROOT/.env"
  chmod 600 "$ROOT/.env"

  local db db_url_password jwt cookie wings nodekey bootstrap
  db="$(get_env POSTGRES_PASSWORD || true)"
  jwt="$(get_env JWT_SECRET || true)"
  cookie="$(get_env COOKIE_SECRET || true)"
  wings="$(get_env WINGS_SHARED_SECRET || true)"
  nodekey="$(get_env NODE_ENCRYPTION_KEY || true)"
  bootstrap="$(get_env JZ_BOOTSTRAP_TOKEN || true)"

  [[ -n "$db" ]] || db="$(secret)"
  [[ -n "$jwt" ]] || jwt="$(secret)"
  [[ -n "$cookie" ]] || cookie="$(secret)"
  [[ -n "$wings" ]] || wings="$(secret)"
  [[ -n "$nodekey" ]] || nodekey="$(secret)"
  [[ -n "$bootstrap" ]] || bootstrap="$(secret)"

  upsert_env "$ROOT/.env" NODE_ENV production
  upsert_env "$ROOT/.env" APP_NAME 'J&Z Panel'
  upsert_env "$ROOT/.env" PANEL_ORIGIN "$PANEL_ORIGIN"
  upsert_env "$ROOT/.env" WEB_ORIGIN "$PANEL_ORIGIN"
  upsert_env "$ROOT/.env" CORS_ORIGIN "$PANEL_ORIGIN"
  upsert_env "$ROOT/.env" POSTGRES_DB jz
  upsert_env "$ROOT/.env" POSTGRES_USER jz
  db_url_password="$(pg_url_password "$db")"
  upsert_env "$ROOT/.env" POSTGRES_PASSWORD "$db"
  upsert_env "$ROOT/.env" DATABASE_URL "postgresql://jz:${db_url_password}@postgres:5432/jz"
  upsert_env "$ROOT/.env" REDIS_URL 'redis://redis:6379'
  upsert_env "$ROOT/.env" JWT_SECRET "$jwt"
  upsert_env "$ROOT/.env" COOKIE_SECRET "$cookie"
  upsert_env "$ROOT/.env" WINGS_SHARED_SECRET "$wings"
  upsert_env "$ROOT/.env" NODE_ENCRYPTION_KEY "$nodekey"
  upsert_env "$ROOT/.env" JZ_BOOTSTRAP_TOKEN "$bootstrap"
  upsert_env "$ROOT/.env" ADMIN_USERNAME "$ADMIN_USERNAME"
  upsert_env "$ROOT/.env" ADMIN_EMAIL "$ADMIN_EMAIL"
  upsert_env "$ROOT/.env" ADMIN_PASSWORD "$ADMIN_PASSWORD"
  chmod 600 "$ROOT/.env"
  [[ -n "$(get_env POSTGRES_PASSWORD)" ]] || die ".env generation failed: POSTGRES_PASSWORD missing"
  [[ -n "$(get_env DATABASE_URL)" ]] || die ".env generation failed: DATABASE_URL missing"
  [[ ${#jwt} -ge 32 ]] || die ".env generation failed: JWT_SECRET is too short"
  ok ".env ready at $ROOT/.env (existing secrets preserved)."
}

source_check(){
  section "🔎 Source validation"
  [[ -f "$ROOT/docker-compose.yml" && -f "$ROOT/package.json" ]] || die "Incomplete J&Z source tree."
  [[ -f "$ROOT/apps/worker/src/index.ts" ]] || die "Worker source missing."
  grep -Fq 'import Redis from "ioredis"' "$ROOT/apps/worker/src/index.ts" || die "Worker Redis import is invalid."
  [[ -d "$ROOT/packages/db/migrations" ]] || die "Database migrations directory is missing."
  [[ -x "$ROOT/installer/migrate.sh" ]] || die "Migration runner is missing or not executable."
  bash -n "$ROOT/install.sh" "$ROOT/installer/install.sh" "$ROOT/installer/generate-env.sh" "$ROOT/installer/validate.sh" "$ROOT/installer/migrate.sh"
  ok "Shell and source checks passed."
}

compose_validate(){
  cd "$ROOT"
  docker compose --env-file .env config >/dev/null
  ok "Docker Compose configuration is valid."
}

build_stack(){
  section "🏗️ Building J&Z images"
  cd "$ROOT"
  docker compose --env-file .env --progress plain build --pull
  ok "All application images built successfully."
}

wait_for(){
  local name="$1" cmd="$2" max="$3" i
  for i in $(seq 1 "$max"); do
    if eval "$cmd"; then ok "$name ready."; return 0; fi
    sleep 1
  done
  cd "$ROOT"
  docker compose --env-file .env ps || true
  docker compose --env-file .env logs --tail=150 2>/dev/null || true
  die "$name did not become ready within ${max}s."
}

start_stack(){
  section "🚀 Starting PostgreSQL / Redis / API / Worker / WS / Web"
  cd "$ROOT"
  docker compose --env-file .env up -d --remove-orphans
  wait_for 'PostgreSQL' 'docker compose --env-file .env exec -T postgres pg_isready -U "$(get_env POSTGRES_USER)" -d "$(get_env POSTGRES_DB)" >/dev/null 2>&1' 120
  wait_for 'Redis' 'docker compose --env-file .env exec -T redis redis-cli ping 2>/dev/null | grep -q PONG' 120
  wait_for 'API' 'curl -fsS http://127.0.0.1:4000/api/ready >/dev/null 2>&1' 120
  wait_for 'Web' 'curl -fsS http://127.0.0.1:5173/ >/dev/null 2>&1' 120
  wait_for 'WS' 'curl -fsS http://127.0.0.1:4001/health >/dev/null 2>&1' 120
}

migrate_db(){
  section "🗄️ Database migrations"
  cd "$ROOT"
  "$ROOT/installer/migrate.sh"
  ok "Database schema is at the current migration level."
}

bootstrap_admin(){
  section "👤 Admin account"
  local hash db_user db_name
  hash="$(python3 - "$ADMIN_PASSWORD" <<'PY'
import hashlib, os, sys
password=sys.argv[1].encode()
salt=os.urandom(16).hex(); iterations=210000
digest=hashlib.pbkdf2_hmac("sha256", password, salt.encode(), iterations, 32).hex()
print(f"pbkdf2${iterations}${salt}${digest}")
PY
)"
  db_user="$(get_env POSTGRES_USER)"; db_name="$(get_env POSTGRES_DB)"
  docker compose --env-file .env exec -T postgres psql -v ON_ERROR_STOP=1 -U "$db_user" -d "$db_name" -v username="$ADMIN_USERNAME" -v email="$ADMIN_EMAIL" -v hash="$hash" <<'SQL'
INSERT INTO users(username,email,password_hash,role)
VALUES(:'username',:'email',:'hash','admin')
ON CONFLICT (username) DO UPDATE SET email=EXCLUDED.email,password_hash=EXCLUDED.password_hash,role='admin';
SQL
  ok "Admin account created/updated."
}

nginx_http(){
  local host="$1"
  mkdir -p "$ACME_ROOT/.well-known/acme-challenge"
  cat >"$NGINX_CONF" <<EOF2
server {
    listen 80;
    listen [::]:80;
    server_name $host;
    client_max_body_size 200m;
    location ^~ /.well-known/acme-challenge/ { root $ACME_ROOT; default_type text/plain; try_files \$uri =404; }
    location /api/ { proxy_pass http://127.0.0.1:4000; proxy_http_version 1.1; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme; proxy_read_timeout 120s; }
    location /ws { proxy_pass http://127.0.0.1:4001; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; proxy_set_header X-Forwarded-Proto \$scheme; proxy_read_timeout 3600s; }
    location / { proxy_pass http://127.0.0.1:5173; proxy_http_version 1.1; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme; proxy_read_timeout 120s; }
}
EOF2
  ln -sfn "$NGINX_CONF" "$NGINX_LINK"
  if [[ -e /etc/nginx/sites-enabled/default ]]; then
    mv -f /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.jz-backup
  fi
  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx
  ok "HTTP reverse proxy configured for $host"
}

nginx_https(){
  local host="$1"
  cat >"$NGINX_CONF" <<EOF2
server {
    listen 80;
    listen [::]:80;
    server_name $host;
    client_max_body_size 200m;
    location ^~ /.well-known/acme-challenge/ { root $ACME_ROOT; default_type text/plain; try_files \$uri =404; }
    location / { return 301 https://\$host\$request_uri; }
}
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $host;
    ssl_certificate /etc/letsencrypt/live/$host/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$host/privkey.pem;
    client_max_body_size 200m;
    location /api/ { proxy_pass http://127.0.0.1:4000; proxy_http_version 1.1; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto https; proxy_read_timeout 120s; }
    location /ws { proxy_pass http://127.0.0.1:4001; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; proxy_set_header X-Forwarded-Proto https; proxy_read_timeout 3600s; }
    location / { proxy_pass http://127.0.0.1:5173; proxy_http_version 1.1; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto https; proxy_read_timeout 120s; }
}
EOF2
  nginx -t
  systemctl reload nginx
}

https_setup(){
  (( USE_DOMAIN == 1 )) || return 0
  section "🔒 HTTPS"
  read -rp "Enable Let's Encrypt HTTPS for $PANEL_DOMAIN? [Y/n]: " ans
  [[ "${ans:-Y}" =~ ^[Yy]$ ]] || { warn "HTTPS skipped."; return 0; }
  apt-get install -y certbot
  read -rp "📧 Let's Encrypt email: " LE_EMAIL
  valid_email "$LE_EMAIL" || die "Invalid Let's Encrypt email."

  nginx_http "$PANEL_DOMAIN"
  echo "jz-acme-check" > "$ACME_ROOT/.well-known/acme-challenge/health"
  curl -fsS --max-time 15 "http://$PANEL_DOMAIN/.well-known/acme-challenge/health" | grep -q jz-acme-check || die "HTTP ACME challenge path is not reachable."

  certbot certonly --webroot -w "$ACME_ROOT" -d "$PANEL_DOMAIN" --non-interactive --agree-tos --email "$LE_EMAIL" --keep-until-expiring
  [[ -s "/etc/letsencrypt/live/$PANEL_DOMAIN/fullchain.pem" && -s "/etc/letsencrypt/live/$PANEL_DOMAIN/privkey.pem" ]] || die "Certificate files were not created."
  CERT_CREATED=1
  nginx_https "$PANEL_DOMAIN"
  PANEL_ORIGIN="https://$PANEL_DOMAIN"
  upsert_env "$ROOT/.env" PANEL_ORIGIN "$PANEL_ORIGIN"
  upsert_env "$ROOT/.env" WEB_ORIGIN "$PANEL_ORIGIN"
  upsert_env "$ROOT/.env" CORS_ORIGIN "$PANEL_ORIGIN"
  cd "$ROOT"
  docker compose --env-file .env up -d --force-recreate api ws web
  wait_for 'API after HTTPS config' 'curl -fsS http://127.0.0.1:4000/api/ready >/dev/null 2>&1' 120
  HTTPS_ENABLED=1
  ok "HTTPS enabled: $PANEL_ORIGIN"
}

firewall(){
  section "🛡️ Firewall"
  command -v ufw >/dev/null 2>&1 || return 0
  local ssh_port; ssh_port="$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}' || true)"; ssh_port="${ssh_port:-22}"
  if ! ufw status | grep -q "${ssh_port}/tcp"; then ufw allow "$ssh_port/tcp" >/dev/null; UFW_ADDED_RULES+=("$ssh_port/tcp"); fi
  if ! ufw status | grep -q '80/tcp'; then ufw allow 80/tcp >/dev/null; UFW_ADDED_RULES+=("80/tcp"); fi
  if ! ufw status | grep -q '443/tcp'; then ufw allow 443/tcp >/dev/null; UFW_ADDED_RULES+=("443/tcp"); fi
  if (( UFW_WAS_ACTIVE == 0 )); then ufw --force enable >/dev/null; fi
  ok "UFW: SSH $ssh_port, HTTP 80, HTTPS 443"
}

final_health(){
  section "🩺 Final verification"
  cd "$ROOT"
  docker compose --env-file .env ps
  curl -fsS http://127.0.0.1:4000/api/ready >/dev/null || die "API readiness failed."
  curl -fsS http://127.0.0.1:5173/ >/dev/null || die "Web health failed."
  curl -fsS http://127.0.0.1:4001/health >/dev/null || die "WebSocket health failed."
  docker compose --env-file .env exec -T redis redis-cli ping | grep -q PONG || die "Redis failed."
  docker compose --env-file .env exec -T postgres pg_isready -U "$(get_env POSTGRES_USER)" -d "$(get_env POSTGRES_DB)" >/dev/null || die "PostgreSQL failed."
  nginx -t >/dev/null && systemctl is-active --quiet nginx || die "Nginx failed."
  if (( USE_DOMAIN == 1 )); then
    if (( HTTPS_ENABLED == 1 )); then
      curl -fsS --max-time 20 "$PANEL_ORIGIN/api/ready" >/dev/null || die "Public HTTPS API check failed."
    else
      curl -fsS --max-time 20 "$PANEL_ORIGIN/api/ready" >/dev/null || die "Public HTTP API check failed."
    fi
  fi
  ok "API / Web / WS / Redis / PostgreSQL / Nginx all passed."
}

panel_install(){
  ROLLBACK_NEEDED=1
  prompt_config
  check_dns
  check_ports
  backup_current
  write_env
  source_check
  compose_validate
  build_stack
  start_stack
  migrate_db
  bootstrap_admin
  nginx_http "$PANEL_HOST"
  https_setup
  firewall
  final_health
  ROLLBACK_NEEDED=0
  section "🎉 J&Z Panel v$VERSION installation complete"
  echo "Panel: $PANEL_ORIGIN"
  echo "Admin: $ADMIN_EMAIL"
  echo "Log: $LOG"
}

repair(){
  ROLLBACK_NEEDED=1
  install_docker
  if [[ ! -f "$ROOT/.env" ]]; then
    backup_current
    prompt_config
    write_env
  else
    backup_current
  fi
  source_check; compose_validate; build_stack; start_stack; migrate_db; final_health
  ROLLBACK_NEEDED=0
  ok "Repair completed."
}

health(){
  section "🩺 Diagnostics"
  cd "$ROOT"
  docker compose --env-file .env ps || true
  curl -fsS http://127.0.0.1:4000/api/ready >/dev/null && ok "API healthy" || warn "API unhealthy"
  curl -fsS http://127.0.0.1:5173/ >/dev/null && ok "Web healthy" || warn "Web unhealthy"
  curl -fsS http://127.0.0.1:4001/health >/dev/null && ok "WS healthy" || warn "WS unhealthy"
  docker compose --env-file .env exec -T redis redis-cli ping 2>/dev/null | grep -q PONG && ok "Redis healthy" || warn "Redis unhealthy"
  docker compose --env-file .env exec -T postgres pg_isready -U "$(get_env POSTGRES_USER 2>/dev/null || echo jz)" -d "$(get_env POSTGRES_DB 2>/dev/null || echo jz)" >/dev/null 2>&1 && ok "PostgreSQL healthy" || warn "PostgreSQL unhealthy"
  nginx -t >/dev/null 2>&1 && ok "Nginx config valid" || warn "Nginx config invalid"
}

backup(){
  section "💾 Backup"
  mkdir -p "$STATE/backups"; cd "$ROOT"
  local out="$STATE/backups/jz-$(date +%Y%m%d-%H%M%S).sql"
  docker compose --env-file .env exec -T postgres pg_dump -U "$(get_env POSTGRES_USER)" -d "$(get_env POSTGRES_DB)" > "$out"
  chmod 600 "$out"; ok "Database backup: $out"
}

uninstall(){
  section "🗑️ Uninstall"
  read -rp "Remove J&Z containers and database volume? [y/N]: " a; [[ "${a,,}" == y ]] || return 0
  cd "$ROOT"; docker compose --env-file .env down -v --remove-orphans || true
  rm -f "$NGINX_LINK" "$NGINX_CONF"
  if [[ -e /etc/nginx/sites-enabled/default.jz-backup ]]; then mv -f /etc/nginx/sites-enabled/default.jz-backup /etc/nginx/sites-enabled/default; fi
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  ok "J&Z application removed; Docker was left installed."
}

banner(){ clear 2>/dev/null || true; cat <<'EOF2'
╔════════════════════════════════════════════════════════════╗
║                         🚀 J&Z PANEL                      ║
║                 Transaction-Safe v3.2.0                   ║
║                    🟧 Orange / White                      ║
╚════════════════════════════════════════════════════════════╝
EOF2
}

main(){
  require_root; acquire_lock; check_os; check_resources; banner
  echo "1) 🟧 Panel + 🪽 Wings (Wings source required)"
  echo "2) 🟧 Panel"
  echo "3) 🪽 Wings (not included in current source)"
  echo "4) 🛠️ Repair"
  echo "5) 🔄 Update/Repair"
  echo "6) 🩺 Diagnostics"
  echo "7) 💾 Backup"
  echo "8) 🗑️ Uninstall"
  echo "9) Exit"
  read -rp "Select [1-9]: " c
  case "$c" in
    1) die "Panel + Wings cannot be truthfully installed from this repository yet: the wings directory contains documentation, not a Wings daemon.";;
    2) apt_install; install_docker; panel_install;;
    3) die "Wings source is not included in this build.";;
    4) repair;;
    5) repair;;
    6) health;;
    7) backup;;
    8) uninstall;;
    9) exit 0;;
    *) die "Invalid option.";;
  esac
}
main "$@"
