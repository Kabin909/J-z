#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="2.0.0"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
STATE="/etc/jz-panel"
LOG="/var/log/jz-panel-install.log"
BACKUP_DIR="$STATE/rollback"
LOCK_FILE="/run/lock/jz-panel-install.lock"

mkdir -p "$STATE" "$BACKUP_DIR"
touch "$LOG"
chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1

ROLLBACK_NEEDED=0
ROLLBACK_DONE=0
INSTALL_STARTED=0
PREV_ENV_BACKUP=""
PREV_NGINX_BACKUP=""
PREV_UFW_STATUS=""

cleanup(){
  rm -f "$LOCK_FILE" 2>/dev/null || true
}

rollback(){
  local rc="${1:-1}"
  [[ "$ROLLBACK_NEEDED" -eq 1 && "$ROLLBACK_DONE" -eq 0 ]] || return 0
  ROLLBACK_DONE=1
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "↩️  Transaction failed — starting safe rollback"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  set +e
  if [[ -f "$ROOT/docker-compose.yml" || -f "$ROOT/compose.yml" ]]; then
    cd "$ROOT"
    docker compose stop >/dev/null 2>&1 || true
  fi

  if [[ -n "$PREV_ENV_BACKUP" && -f "$PREV_ENV_BACKUP" ]]; then
    cp -f "$PREV_ENV_BACKUP" "$ROOT/.env" || true
    chmod 600 "$ROOT/.env" || true
  elif [[ "$INSTALL_STARTED" -eq 1 ]]; then
    rm -f "$ROOT/.env"
  fi

  if [[ -n "$PREV_NGINX_BACKUP" && -f "$PREV_NGINX_BACKUP" ]]; then
    cp -f "$PREV_NGINX_BACKUP" /etc/nginx/sites-available/jz-panel.conf || true
    ln -sfn /etc/nginx/sites-available/jz-panel.conf /etc/nginx/sites-enabled/jz-panel.conf || true
    nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  else
    rm -f /etc/nginx/sites-enabled/jz-panel.conf /etc/nginx/sites-available/jz-panel.conf
    nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  fi

  echo "⚠️  Existing database volumes were NOT deleted."
  echo "⚠️  Docker images were NOT pruned."
  echo "📋 Full log: $LOG"
  return "$rc"
}

on_error(){
  local rc=$?
  local line="${1:-unknown}"
  echo "❌ Installer failed at line $line (exit $rc)."
  rollback "$rc" || true
  exit "$rc"
}
trap 'on_error "$LINENO"' ERR
trap cleanup EXIT

ok(){ echo "✅ $*"; }
warn(){ echo "⚠️  $*"; }
die(){ echo "❌ $*"; return 1; }
section(){ printf '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n%s\n' "$*"; }

require_root(){
  [[ "$EUID" -eq 0 ]] || die "Run as root: sudo bash installer/install.sh"
}

acquire_lock(){
  if [[ -e "$LOCK_FILE" ]]; then
    die "Another J&Z installer process is already running."
  fi
  : > "$LOCK_FILE"
}

check_os(){
  section "🩺 Preflight: operating system"
  . /etc/os-release
  case "$ID" in
    debian)
      [[ "${VERSION_ID%%.*}" -ge 12 ]] || die "Debian 12+ is required."
      ;;
    ubuntu)
      [[ "${VERSION_ID%%.*}" -ge 22 ]] || die "Ubuntu 22.04+ is required."
      ;;
    *) die "Supported OS: Debian 12+ or Ubuntu 22.04+." ;;
  esac
  case "$(dpkg --print-architecture)" in
    amd64|arm64) ;;
    *) die "Supported architectures: amd64 or arm64." ;;
  esac
  ok "$PRETTY_NAME / $(dpkg --print-architecture)"
}

check_resources(){
  section "🧠 Preflight: resources"
  local mem_mib disk_gib cpu_count
  mem_mib="$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)"
  disk_gib="$(df -Pk "$ROOT" | awk 'NR==2 {printf "%d", $4/1024/1024}')"
  cpu_count="$(nproc)"
  echo "CPU: ${cpu_count}"
  echo "RAM: ${mem_mib} MiB"
  echo "Free disk: ${disk_gib} GiB"
  (( mem_mib >= 1024 )) || warn "Less than 1 GiB RAM detected; builds may fail under memory pressure."
  (( disk_gib >= 5 )) || die "At least 5 GiB free disk space is recommended."
}

check_virtualization(){
  section "🖥️ Preflight: virtualization"
  local virt
  virt="$(systemd-detect-virt 2>/dev/null || true)"
  [[ -n "$virt" ]] && echo "Virtualization: $virt" || echo "Virtualization: bare metal/unknown"
  case "$virt" in
    openvz|lxc|container)
      warn "Container virtualization detected ($virt). Docker/Wings may be restricted by the host."
      ;;
  esac
}

fix_duplicate_sury(){
  local a=/etc/apt/sources.list.d/php.list
  local b=/etc/apt/sources.list.d/sury-php.list
  [[ -f "$a" && -f "$b" ]] || return 0
  if grep -q 'packages.sury.org/php' "$a" 2>/dev/null && grep -q 'packages.sury.org/php' "$b" 2>/dev/null; then
    local stamp
    stamp="$(date +%Y%m%d-%H%M%S)"
    cp -a "$a" "$STATE/php.list.$stamp.bak"
    mv -f "$a" "${a}.disabled-by-jz"
    warn "Disabled duplicate Sury PHP source: $a"
  fi
}

apt_update(){
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
}

install_base_deps(){
  section "📦 Installing system dependencies"
  fix_duplicate_sury
  apt_update
  apt-get install -y ca-certificates curl git jq openssl python3 nginx ufw dnsutils lsof procps
}

install_docker(){
  section "🐳 Checking Docker"
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    systemctl enable --now docker
    docker info >/dev/null 2>&1 || die "Docker is installed but the daemon is unavailable."
    ok "Docker and Compose are ready."
    return 0
  fi

  apt-get install -y ca-certificates curl gnupg
  install -d -m 0755 /etc/apt/keyrings
  local arch codename
  arch="$(dpkg --print-architecture)"
  codename="${VERSION_CODENAME:-}"
  [[ -n "$codename" ]] || . /etc/os-release && codename="$VERSION_CODENAME"

  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  chmod 0644 /etc/apt/keyrings/docker.gpg
  echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${ID} ${codename} stable" >/etc/apt/sources.list.d/docker.list

  apt_update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  docker info >/dev/null 2>&1 || die "Docker daemon is unavailable after installation."
  docker compose version >/dev/null 2>&1 || die "Docker Compose plugin is unavailable."
  ok "Docker $(docker --version | cut -d' ' -f3 | tr -d ',') / $(docker compose version --short)"
}

valid_domain(){
  local d="$1"
  [[ "$d" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}
valid_ipv4(){
  local ip="$1" o IFS=.
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  read -r -a o <<< "$ip"
  for x in "${o[@]}"; do (( x <= 255 )) || return 1; done
}
valid_email(){ [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; }
public_ip(){ curl -4fsS --max-time 8 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}'; }
secret(){ openssl rand -hex 32; }

prompt_config(){
  section "⚙️  Panel configuration"
  read -rp "🌐 Panel domain (blank = VPS IPv4): " PANEL_DOMAIN
  PANEL_DOMAIN="${PANEL_DOMAIN//[[:space:]]/}"

  if [[ -n "$PANEL_DOMAIN" ]]; then
    valid_domain "$PANEL_DOMAIN" || die "Invalid domain: $PANEL_DOMAIN"
    PANEL_HOST="$PANEL_DOMAIN"
    USE_DOMAIN=1
  else
    PANEL_HOST="$(public_ip)"
    valid_ipv4 "$PANEL_HOST" || die "Could not determine a valid public IPv4 address."
    USE_DOMAIN=0
  fi

  read -rp "👤 Admin username [admin]: " ADMIN_USERNAME
  ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
  [[ "$ADMIN_USERNAME" =~ ^[A-Za-z0-9_.-]{3,32}$ ]] || die "Admin username must be 3-32 characters."

  read -rp "📧 Admin email: " ADMIN_EMAIL
  valid_email "$ADMIN_EMAIL" || die "Valid admin email required."

  while :; do
    read -rsp "🔑 Admin password (12+ chars): " ADMIN_PASSWORD
    echo
    (( ${#ADMIN_PASSWORD} >= 12 )) && break
    warn "Password must be at least 12 characters."
  done

  PANEL_ORIGIN="http://${PANEL_HOST}"
  ok "Panel origin: $PANEL_ORIGIN"
}

check_dns(){
  [[ "$USE_DOMAIN" -eq 1 ]] || return 0
  section "🌐 Checking DNS"
  local resolved public
  resolved="$(getent ahostsv4 "$PANEL_DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u | head -20 || true)"
  [[ -n "$resolved" ]] || die "DNS does not resolve $PANEL_DOMAIN. Create an A record first."
  echo "Resolved $PANEL_DOMAIN ->"
  echo "$resolved"
  public="$(public_ip || true)"
  if [[ -n "$public" ]] && ! grep -qx "$public" <<< "$resolved"; then
    warn "DNS does not currently resolve to detected VPS IP $public."
    read -rp "Continue anyway? [y/N]: " ans
    [[ "${ans,,}" == "y" ]] || die "DNS check cancelled."
  else
    ok "DNS points to this VPS."
  fi
}

check_ports(){
  section "🔌 Checking required ports"
  local p owner
  for p in 80 443; do
    owner="$(ss -ltnp "sport = :$p" 2>/dev/null | tail -n +2 || true)"
    if [[ -n "$owner" ]]; then
      echo "Port $p is already in use: $owner"
      if [[ "$p" == "80" || "$p" == "443" ]]; then
        if grep -qi nginx <<< "$owner"; then
          ok "Port $p is owned by Nginx."
        else
          warn "Another service owns port $p. Nginx/HTTPS may not work."
          read -rp "Continue? [y/N]: " ans
          [[ "${ans,,}" == "y" ]] || die "Port check cancelled."
        fi
      fi
    else
      ok "Port $p is available."
    fi
  done
}

backup_current_config(){
  section "💾 Creating rollback snapshot"
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  PREV_ENV_BACKUP="$BACKUP_DIR/env.$stamp.bak"
  PREV_NGINX_BACKUP="$BACKUP_DIR/nginx.$stamp.bak"

  if [[ -f "$ROOT/.env" ]]; then
    cp -a "$ROOT/.env" "$PREV_ENV_BACKUP"
  else
    PREV_ENV_BACKUP=""
  fi
  if [[ -f /etc/nginx/sites-available/jz-panel.conf ]]; then
    cp -a /etc/nginx/sites-available/jz-panel.conf "$PREV_NGINX_BACKUP"
  else
    PREV_NGINX_BACKUP=""
  fi
  ok "Rollback snapshot created."
}

upsert_env(){
  local file="$1" key="$2" value="$3"
  python3 - "$file" "$key" "$value" <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1]); key=sys.argv[2]; value=sys.argv[3]
text=p.read_text() if p.exists() else ''
line=f'{key}={value}'
pattern=rf'^{re.escape(key)}=.*$'
if re.search(pattern,text,re.M):
    text=re.sub(pattern,lambda _: line,text,flags=re.M)
else:
    if text and not text.endswith('\n'): text += '\n'
    text += line+'\n'
p.write_text(text)
PY
}

write_env(){
  section "🔐 Generating production .env"
  [[ -f "$ROOT/.env" ]] || cp "$ROOT/.env.example" "$ROOT/.env"
  chmod 600 "$ROOT/.env"

  local db jwt cookie wings
  db="$(grep '^POSTGRES_PASSWORD=' "$ROOT/.env" | cut -d= -f2- || true)"
  jwt="$(grep '^JWT_SECRET=' "$ROOT/.env" | cut -d= -f2- || true)"
  cookie="$(grep '^COOKIE_SECRET=' "$ROOT/.env" | cut -d= -f2- || true)"
  wings="$(grep '^WINGS_SHARED_SECRET=' "$ROOT/.env" | cut -d= -f2- || true)"
  [[ -n "$db" && "$db" != CHANGE_ME ]] || db="$(secret)"
  [[ -n "$jwt" && "$jwt" != CHANGE_ME ]] || jwt="$(secret)"
  [[ -n "$cookie" && "$cookie" != CHANGE_ME ]] || cookie="$(secret)"
  [[ -n "$wings" && "$wings" != CHANGE_ME ]] || wings="$(secret)"

  upsert_env "$ROOT/.env" NODE_ENV production
  upsert_env "$ROOT/.env" POSTGRES_DB jz
  upsert_env "$ROOT/.env" POSTGRES_USER jz
  upsert_env "$ROOT/.env" POSTGRES_PASSWORD "$db"
  upsert_env "$ROOT/.env" DATABASE_URL 'postgresql://jz:${POSTGRES_PASSWORD}@postgres:5432/jz'
  upsert_env "$ROOT/.env" REDIS_URL 'redis://redis:6379'
  upsert_env "$ROOT/.env" JWT_SECRET "$jwt"
  upsert_env "$ROOT/.env" COOKIE_SECRET "$cookie"
  upsert_env "$ROOT/.env" WINGS_SHARED_SECRET "$wings"
  upsert_env "$ROOT/.env" PANEL_ORIGIN "$PANEL_ORIGIN"
  upsert_env "$ROOT/.env" WEB_ORIGIN "$PANEL_ORIGIN"
  upsert_env "$ROOT/.env" ADMIN_USERNAME "$ADMIN_USERNAME"
  upsert_env "$ROOT/.env" ADMIN_EMAIL "$ADMIN_EMAIL"
  upsert_env "$ROOT/.env" ADMIN_PASSWORD "$ADMIN_PASSWORD"
  chmod 600 "$ROOT/.env"
  ok "Production .env generated at $ROOT/.env"
}

prepare_source(){
  section "🧰 Preparing source"
  [[ -f "$ROOT/docker-compose.yml" || -f "$ROOT/compose.yml" ]] || die "docker-compose.yml/compose.yml not found in $ROOT"
  [[ -f "$ROOT/package.json" ]] || die "package.json not found in $ROOT"

  # The worker can fail with TS2351 under NodeNext + ioredis v5's export map.
  # Prefer the named Redis constructor when the source uses the problematic default form.
  if [[ -f "$ROOT/apps/worker/src/index.ts" ]] && grep -q '^import Redis from "ioredis";' "$ROOT/apps/worker/src/index.ts"; then
    sed -i 's/^import Redis from "ioredis";/import { Redis } from "ioredis";/' "$ROOT/apps/worker/src/index.ts"
    ok "Applied NodeNext-compatible ioredis import."
  fi
}

compose_validate(){
  cd "$ROOT"
  docker compose --env-file .env config >/dev/null
  ok "Docker Compose configuration is valid."
}

build_stack(){
  section "🏗️ Building application images"
  cd "$ROOT"
  docker compose --env-file .env build --pull --progress plain
}

start_stack(){
  section "🚀 Starting J&Z services"
  cd "$ROOT"
  docker compose --env-file .env up -d --remove-orphans

  local i
  for i in $(seq 1 90); do
    if docker compose ps --status running 2>/dev/null | grep -q 'postgres'; then
      if docker compose exec -T postgres pg_isready -U jz -d jz >/dev/null 2>&1; then break; fi
    fi
    sleep 2
  done

  wait_for_service postgres 'docker compose exec -T postgres pg_isready -U jz -d jz >/dev/null 2>&1' 90
  wait_for_service redis 'docker compose exec -T redis redis-cli ping 2>/dev/null | grep -q PONG' 90
  wait_for_service api 'curl -fsS http://127.0.0.1:4000/api/ready >/dev/null 2>&1' 120
  wait_for_service web 'curl -fsS http://127.0.0.1:5173/ >/dev/null 2>&1' 90
  wait_for_service ws 'ss -ltn "sport = :4001" 2>/dev/null | grep -q 4001' 90
  docker compose ps
}

wait_for_service(){
  local name="$1" check="$2" timeout="$3" i
  for i in $(seq 1 "$timeout"); do
    if eval "$check"; then
      ok "$name is ready."
      return 0
    fi
    sleep 1
  done
  cd "$ROOT"
  docker compose ps
  docker compose logs --tail=120 "$name" 2>/dev/null || true
  die "$name did not become ready within ${timeout}s."
}

run_migrations(){
  section "🗄️ Database migrations"
  cd "$ROOT"
  local ran=0
  local service="api"

  # Run only scripts that actually exist in package.json. Never invent a migration command.
  if jq -e '.scripts.migrate' package.json >/dev/null 2>&1; then
    docker compose exec -T "$service" sh -lc 'npm run migrate' && ran=1
  elif jq -e '.scripts["db:migrate"]' package.json >/dev/null 2>&1; then
    docker compose exec -T "$service" sh -lc 'npm run db:migrate' && ran=1
  elif [[ -f packages/db/package.json ]] && jq -e '.scripts.migrate' packages/db/package.json >/dev/null 2>&1; then
    docker compose exec -T "$service" sh -lc 'npm --workspace @jz/db run migrate' && ran=1
  fi

  if (( ran == 1 )); then
    ok "Database migrations completed."
  else
    warn "No migration script is defined in this repository; migration step was safely skipped."
  fi
}

bootstrap_admin(){
  section "👤 Admin bootstrap"
  cd "$ROOT"
  local ran=0
  if jq -e '.scripts["seed:admin"]' package.json >/dev/null 2>&1; then
    docker compose exec -T api sh -lc 'npm run seed:admin' && ran=1
  elif jq -e '.scripts.seed' package.json >/dev/null 2>&1; then
    docker compose exec -T api sh -lc 'npm run seed' && ran=1
  elif [[ -f apps/api/package.json ]] && jq -e '.scripts["seed:admin"]' apps/api/package.json >/dev/null 2>&1; then
    docker compose exec -T api sh -lc 'npm run seed:admin' && ran=1
  fi

  if (( ran == 1 )); then
    ok "Admin seed completed."
  else
    warn "No admin-seed script exists in the current repository; installer cannot safely invent one."
    warn "ADMIN_USERNAME/ADMIN_EMAIL/ADMIN_PASSWORD remain in .env for an application-level bootstrap implementation."
  fi
}

configure_nginx(){
  section "🌐 Configuring Nginx"
  local host="$1"
  local server_name
  if valid_ipv4 "$host"; then server_name="$host"; else server_name="$host"; fi

  cat >/etc/nginx/sites-available/jz-panel.conf <<EOF2
server {
    listen 80;
    listen [::]:80;
    server_name $server_name;
    client_max_body_size 200m;

    location /api/ {
        proxy_pass http://127.0.0.1:4000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
    }

    location /ws/ {
        proxy_pass http://127.0.0.1:4001/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 3600s;
    }

    location / {
        proxy_pass http://127.0.0.1:5173;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
    }
}
EOF2

  ln -sfn /etc/nginx/sites-available/jz-panel.conf /etc/nginx/sites-enabled/jz-panel.conf
  if [[ -e /etc/nginx/sites-enabled/default && ! -e /etc/nginx/sites-enabled/default.jz-backup ]]; then
    mv /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.jz-backup
  fi
  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx
  ok "Nginx is configured for $server_name"
}

https(){
  local domain="${PANEL_DOMAIN:-}"
  [[ "$USE_DOMAIN" -eq 1 && -n "$domain" ]] || return 0
  section "🔒 HTTPS"
  read -rp "Enable Let's Encrypt HTTPS for $PANEL_DOMAIN? [Y/n]: " ans
  [[ "${ans:-Y}" =~ ^[Yy]$ ]] || { warn "HTTPS skipped by user."; return 0; }

  apt_update
  apt-get install -y certbot python3-certbot-nginx
  read -rp "📧 Let's Encrypt email: " LE_EMAIL
  valid_email "$LE_EMAIL" || die "Valid email required for HTTPS."

  certbot --nginx -d "$domain" --non-interactive --agree-tos --email "$LE_EMAIL" --redirect
  PANEL_ORIGIN="https://$domain"
  upsert_env "$ROOT/.env" PANEL_ORIGIN "$PANEL_ORIGIN"
  upsert_env "$ROOT/.env" WEB_ORIGIN "$PANEL_ORIGIN"
  ok "HTTPS enabled: $PANEL_ORIGIN"
}

firewall(){
  section "🛡️ Firewall"
  local ssh_port
  ssh_port="$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}' || true)"
  [[ -n "$ssh_port" ]] || ssh_port=22
  ufw allow "$ssh_port/tcp" >/dev/null
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
  # Wings is intentionally not opened by Panel-only mode.
  ufw --force enable >/dev/null
  ok "UFW configured; SSH $ssh_port, HTTP 80, HTTPS 443."
}

final_health(){
  section "🩺 Final health verification"
  cd "$ROOT"
  docker compose ps
  curl -fsS http://127.0.0.1:4000/api/health >/dev/null || die "API health check failed."
  curl -fsS http://127.0.0.1:5173/ >/dev/null || die "Web health check failed."
  docker compose exec -T redis redis-cli ping 2>/dev/null | grep -q PONG || die "Redis health check failed."
  docker compose exec -T postgres pg_isready -U jz -d jz >/dev/null 2>&1 || die "PostgreSQL health check failed."
  nginx -t >/dev/null
  systemctl is-active --quiet nginx || die "Nginx is not active."
  ok "API"
  ok "Web UI"
  ok "Redis"
  ok "PostgreSQL"
  ok "Nginx"
}

panel_install(){
  section "🚀 J&Z Panel transactional installation"
  INSTALL_STARTED=1
  ROLLBACK_NEEDED=1

  prompt_config
  check_dns
  check_ports
  backup_current_config
  write_env
  prepare_source
  compose_validate
  build_stack
  start_stack
  run_migrations
  bootstrap_admin
  configure_nginx "$PANEL_HOST"
  https
  firewall
  final_health

  ROLLBACK_NEEDED=0
  section "🎉 Installation complete"
  echo "Panel: $PANEL_ORIGIN"
  echo "Admin: $ADMIN_EMAIL"
  echo "Log: $LOG"
  ok "Transaction committed successfully."
}

repair(){
  section "🛠️ Repair"
  ROLLBACK_NEEDED=1
  install_base_deps
  install_docker
  [[ -f "$ROOT/.env" ]] || cp "$ROOT/.env.example" "$ROOT/.env"
  chmod 600 "$ROOT/.env"
  prepare_source
  compose_validate
  cd "$ROOT"
  docker compose up -d --remove-orphans
  build_stack
  start_stack
  run_migrations
  final_health
  ROLLBACK_NEEDED=0
  ok "Repair completed."
}

health(){
  section "🩺 Health diagnostics"
  cd "$ROOT"
  docker compose ps || true
  curl -fsS http://127.0.0.1:4000/api/health >/dev/null && ok "API healthy" || warn "API unhealthy"
  curl -fsS http://127.0.0.1:5173/ >/dev/null && ok "Web healthy" || warn "Web unhealthy"
  docker compose exec -T redis redis-cli ping 2>/dev/null | grep -q PONG && ok "Redis healthy" || warn "Redis unhealthy"
  docker compose exec -T postgres pg_isready -U jz -d jz >/dev/null 2>&1 && ok "PostgreSQL healthy" || warn "PostgreSQL unhealthy"
  nginx -t >/dev/null 2>&1 && ok "Nginx configuration valid" || warn "Nginx configuration invalid"
}

backup(){
  section "💾 Database backup"
  mkdir -p "$STATE/backups"
  cd "$ROOT"
  local out="$STATE/backups/jz-$(date +%Y%m%d-%H%M%S).sql"
  docker compose exec -T postgres pg_dump -U jz -d jz >"$out"
  chmod 600 "$out"
  ok "Backup created: $out"
}

uninstall(){
  section "🗑️ Uninstall"
  read -rp "Remove J&Z containers/database volume and Nginx config? [y/N]: " a
  [[ "${a,,}" == "y" ]] || return 0
  cd "$ROOT"
  docker compose down -v --remove-orphans || true
  rm -f /etc/nginx/sites-enabled/jz-panel.conf /etc/nginx/sites-available/jz-panel.conf
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  rm -rf "$STATE"
  ok "J&Z application removed. Docker itself was left installed."
}

banner(){
  clear 2>/dev/null || true
  cat <<'EOF2'
╔════════════════════════════════════════════════════════════╗
║                     🚀 J&Z PANEL                         ║
║          Transaction-Safe Production Installer            ║
║                  🟧 Orange / White                        ║
╚════════════════════════════════════════════════════════════╝
EOF2
}

main(){
  require_root
  acquire_lock
  check_os
  check_resources
  check_virtualization
  banner
  echo "1) 🟧 Panel + 🪽 Wings"
  echo "2) 🟧 Panel"
  echo "3) 🪽 Wings"
  echo "4) 🛠️ Repair"
  echo "5) 🔄 Update"
  echo "6) 🩺 Diagnostics"
  echo "7) 💾 Backup"
  echo "8) 🗑️ Uninstall"
  echo "9) Exit"
  read -rp "Select [1-9]: " c

  case "$c" in
    1)
      install_base_deps
      install_docker
      panel_install
      warn "Wings installation is not invoked by this Panel transaction because this repository does not contain a complete Panel↔Wings protocol."
      ;;
    2)
      install_base_deps
      install_docker
      panel_install
      ;;
    3)
      die "Wings-only installation requires a complete Wings implementation/configuration in this repository."
      ;;
    4) repair ;;
    5) repair ;;
    6) health ;;
    7) backup ;;
    8) uninstall ;;
    9) exit 0 ;;
    *) die "Invalid option." ;;
  esac
}

main "$@"
