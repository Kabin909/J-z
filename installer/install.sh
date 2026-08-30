#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="3.1.1"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
STATE="/etc/jz-panel"
LOG="/var/log/jz-panel-install.log"
BACKUP_DIR="$STATE/rollback"
LOCK_FILE="/run/lock/jz-panel-install.lock"

mkdir -p "$STATE" "$BACKUP_DIR" /run/lock
touch "$LOG"
chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1

ROLLBACK_NEEDED=0
ROLLBACK_DONE=0
STACK_WAS_PRESENT=0
PREV_ENV_BACKUP=""
PREV_NGINX_BACKUP=""

cleanup(){ rm -f "$LOCK_FILE" 2>/dev/null || true; }

rollback(){
  local rc="${1:-1}"
  [[ "$ROLLBACK_NEEDED" -eq 1 && "$ROLLBACK_DONE" -eq 0 ]] || return 0
  ROLLBACK_DONE=1
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "↩️  Transaction failed — rolling back changed configuration"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  set +e
  if [[ -f "$ROOT/docker-compose.yml" ]]; then
    cd "$ROOT"
    if (( STACK_WAS_PRESENT == 1 )); then docker compose --env-file .env stop; else docker compose --env-file .env down --remove-orphans; fi
  fi
  if [[ -n "$PREV_ENV_BACKUP" && -f "$PREV_ENV_BACKUP" ]]; then cp -f "$PREV_ENV_BACKUP" "$ROOT/.env"; chmod 600 "$ROOT/.env"; else rm -f "$ROOT/.env"; fi
  if [[ -n "$PREV_NGINX_BACKUP" && -f "$PREV_NGINX_BACKUP" ]]; then
    cp -f "$PREV_NGINX_BACKUP" /etc/nginx/sites-available/jz-panel.conf
    ln -sfn /etc/nginx/sites-available/jz-panel.conf /etc/nginx/sites-enabled/jz-panel.conf
  else
    rm -f /etc/nginx/sites-enabled/jz-panel.conf /etc/nginx/sites-available/jz-panel.conf
  fi
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  echo "⚠️ Database volumes and Docker images were preserved."
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
  if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
    apt-get install -y docker.io docker-compose-plugin
  fi
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
env_value(){ grep -E "^${1}=" "$ROOT/.env" 2>/dev/null | tail -n1 | cut -d= -f2- || true; }
load_existing_config(){
  [[ -f "$ROOT/.env" ]] || die "Missing $ROOT/.env; run Panel installation first."
  PANEL_ORIGIN="$(env_value PANEL_ORIGIN)"
  [[ -n "$PANEL_ORIGIN" ]] || PANEL_ORIGIN="$(env_value WEB_ORIGIN)"
  [[ "$PANEL_ORIGIN" =~ ^https?:// ]] || die "Existing .env has no valid PANEL_ORIGIN."
  PANEL_HOST="${PANEL_ORIGIN#*://}"; PANEL_HOST="${PANEL_HOST%%/*}"
  if valid_ipv4 "$PANEL_HOST"; then USE_DOMAIN=0; else USE_DOMAIN=1; PANEL_DOMAIN="$PANEL_HOST"; fi
  ADMIN_EMAIL="$(env_value ADMIN_EMAIL)"
  ADMIN_USERNAME="$(env_value ADMIN_USERNAME)"
}

prompt_config(){
  section "⚙️ Panel configuration"
  read -rp "🌐 Panel domain (blank = VPS IPv4): " PANEL_DOMAIN
  PANEL_DOMAIN="${PANEL_DOMAIN//[[:space:]]/}"
  if [[ -n "$PANEL_DOMAIN" ]]; then valid_domain "$PANEL_DOMAIN" || die "Invalid domain: $PANEL_DOMAIN"; PANEL_HOST="$PANEL_DOMAIN"; USE_DOMAIN=1; else PANEL_HOST="$(public_ip)"; valid_ipv4 "$PANEL_HOST" || die "Could not determine public IPv4."; USE_DOMAIN=0; fi
  read -rp "👤 Admin username [admin]: " ADMIN_USERNAME; ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"; [[ "$ADMIN_USERNAME" =~ ^[A-Za-z0-9_.-]{3,32}$ ]] || die "Invalid admin username."
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
  if [[ -n "$public" ]] && ! grep -qx "$public" <<< "$resolved"; then warn "DNS does not point to detected VPS IP $public."; read -rp "Continue anyway? [y/N]: " a; [[ "${a,,}" == y ]] || die "DNS check cancelled."; else ok "DNS is aligned with this VPS."; fi
}

check_ports(){
  section "🔌 Port check"
  for p in 80 443; do
    local hit; hit="$(ss -ltnp "sport = :$p" 2>/dev/null | tail -n +2 || true)"
    [[ -z "$hit" ]] && { ok "Port $p available."; continue; }
    if grep -qi nginx <<< "$hit"; then ok "Port $p already belongs to Nginx."; else echo "$hit"; read -rp "Port $p is occupied. Continue? [y/N]: " a; [[ "${a,,}" == y ]] || die "Port check cancelled."; fi
  done
}

backup_current(){
  section "💾 Rollback snapshot"
  local stamp="$(date +%Y%m%d-%H%M%S)"
  if [[ -f "$ROOT/.env" ]]; then PREV_ENV_BACKUP="$BACKUP_DIR/env.$stamp.bak"; cp -a "$ROOT/.env" "$PREV_ENV_BACKUP"; fi
  if [[ -f /etc/nginx/sites-available/jz-panel.conf ]]; then PREV_NGINX_BACKUP="$BACKUP_DIR/nginx.$stamp.bak"; cp -a /etc/nginx/sites-available/jz-panel.conf "$PREV_NGINX_BACKUP"; fi
  [[ -f "$ROOT/docker-compose.yml" ]] && docker compose -f "$ROOT/docker-compose.yml" ps -q >/dev/null 2>&1 && STACK_WAS_PRESENT=1 || true
  ok "Rollback snapshot ready."
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

write_env(){
  section "🔐 Generating .env"
  [[ -f "$ROOT/.env.example" ]] || die "Missing $ROOT/.env.example"
  [[ -f "$ROOT/.env" ]] || cp "$ROOT/.env.example" "$ROOT/.env"
  chmod 600 "$ROOT/.env"
  local db jwt cookie wings nodekey bootstrap
  db="$(env_value POSTGRES_PASSWORD)"
  jwt="$(env_value JWT_SECRET)"
  cookie="$(env_value COOKIE_SECRET)"
  wings="$(env_value WINGS_SHARED_SECRET)"
  nodekey="$(env_value NODE_ENCRYPTION_KEY)"
  bootstrap="$(env_value JZ_BOOTSTRAP_TOKEN)"
  if [[ -z "$db" ]]; then db="$(secret)"; fi
  if [[ -z "$jwt" ]]; then jwt="$(secret)"; fi
  if [[ -z "$cookie" ]]; then cookie="$(secret)"; fi
  if [[ -z "$wings" ]]; then wings="$(secret)"; fi
  if [[ -z "$nodekey" ]]; then nodekey="$(secret)"; fi
  if [[ -z "$bootstrap" ]]; then bootstrap="$(secret)"; fi
  upsert_env "$ROOT/.env" NODE_ENV production
  upsert_env "$ROOT/.env" APP_NAME 'J&Z Panel'
  upsert_env "$ROOT/.env" PANEL_ORIGIN "$PANEL_ORIGIN"
  upsert_env "$ROOT/.env" WEB_ORIGIN "$PANEL_ORIGIN"
  upsert_env "$ROOT/.env" CORS_ORIGIN "$PANEL_ORIGIN"
  upsert_env "$ROOT/.env" POSTGRES_DB jz
  upsert_env "$ROOT/.env" POSTGRES_USER jz
  upsert_env "$ROOT/.env" POSTGRES_PASSWORD "$db"
  upsert_env "$ROOT/.env" DATABASE_URL "postgresql://jz:${db}@postgres:5432/jz"
  upsert_env "$ROOT/.env" REDIS_URL 'redis://redis:6379'
  upsert_env "$ROOT/.env" JWT_SECRET "$jwt"
  upsert_env "$ROOT/.env" COOKIE_SECRET "$cookie"
  upsert_env "$ROOT/.env" WINGS_SHARED_SECRET "$wings"
  upsert_env "$ROOT/.env" NODE_ENCRYPTION_KEY "$nodekey"
  upsert_env "$ROOT/.env" JZ_BOOTSTRAP_TOKEN "$bootstrap"
  upsert_env "$ROOT/.env" ADMIN_USERNAME "$ADMIN_USERNAME"
  upsert_env "$ROOT/.env" ADMIN_EMAIL "$ADMIN_EMAIL"
  # Do not persist the administrator password in .env; it is only used for initial DB bootstrap.
  python3 - "$ROOT/.env" <<'PY'
from pathlib import Path
p=Path(__import__('sys').argv[1])
lines=[x for x in p.read_text().splitlines() if not x.startswith('ADMIN_PASSWORD=')]
p.write_text('\n'.join(lines)+'\n')
PY
  chmod 600 "$ROOT/.env"
  grep -q '^POSTGRES_PASSWORD=..*' "$ROOT/.env" || die ".env generation failed: POSTGRES_PASSWORD missing"
  grep -q '^DATABASE_URL=' "$ROOT/.env" || die ".env generation failed: DATABASE_URL missing"
  grep -q '^JWT_SECRET=..*' "$ROOT/.env" || die ".env generation failed: JWT_SECRET missing"
  ok ".env generated at $ROOT/.env"
}

source_check(){
  section "🔎 Source validation"
  [[ -f "$ROOT/docker-compose.yml" && -f "$ROOT/package.json" ]] || die "Incomplete J&Z source tree."
  [[ -f "$ROOT/apps/worker/src/index.ts" ]] && grep -q 'import { Redis } from "ioredis"' "$ROOT/apps/worker/src/index.ts" || die "Worker Redis constructor import is not fixed."
  [[ -d "$ROOT/packages/db/migrations" ]] || die "Database migrations directory is missing."
  bash -n "$ROOT/install.sh" "$ROOT/installer/install.sh" "$ROOT/installer/generate-env.sh"
  ok "Shell source checks passed."
}

compose_validate(){ cd "$ROOT"; docker compose --env-file .env config >/dev/null; ok "Docker Compose configuration is valid."; }

build_stack(){ section "🏗️ Building J&Z images"; cd "$ROOT"; docker compose --env-file .env build --pull --progress=plain; }

start_stack(){
  section "🚀 Starting PostgreSQL / Redis / API / Worker / WS / Web"
  cd "$ROOT"
  docker compose --env-file .env up -d --remove-orphans
  wait_for 'PostgreSQL' 'docker compose exec -T postgres pg_isready -U jz -d jz >/dev/null 2>&1' 120
  wait_for 'Redis' 'docker compose exec -T redis redis-cli ping 2>/dev/null | grep -q PONG' 120
  wait_for 'API' 'curl -fsS http://127.0.0.1:4000/api/ready >/dev/null 2>&1' 120
  wait_for 'Web' 'curl -fsS http://127.0.0.1:5173/ >/dev/null 2>&1' 120
  wait_for 'WS' 'curl -fsS http://127.0.0.1:4001/health >/dev/null 2>&1' 120
}

wait_for(){ local name="$1" cmd="$2" max="$3"; local i; for i in $(seq 1 "$max"); do eval "$cmd" && { ok "$name ready."; return 0; }; sleep 1; done; cd "$ROOT"; docker compose ps; docker compose logs --tail=150 "${name,,}" 2>/dev/null || true; die "$name did not become ready within ${max}s."; }

init_db(){
  section "🗄️ Database schema"
  cd "$ROOT"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U jz -d jz -f /docker-entrypoint-initdb.d/001_init.sql >/dev/null
  ok "Database schema is present."
}

bootstrap_admin(){
  section "👤 Admin account"
  # Use the same PBKDF2 format as the API, so the generated admin account is immediately usable.
  local hash; hash="$(python3 - "$ADMIN_PASSWORD" <<'PY'
import hashlib, os, sys
password=sys.argv[1].encode()
salt=os.urandom(16).hex()
iterations=210000
digest=hashlib.pbkdf2_hmac("sha256", password, salt.encode(), iterations, 32).hex()
print(f"pbkdf2${iterations}${salt}${digest}")
PY
)"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U jz -d jz -v username="$ADMIN_USERNAME" -v email="$ADMIN_EMAIL" -v hash="$hash" <<'SQL'
INSERT INTO users(username,email,password_hash,role)
VALUES(:'username',:'email',:'hash','admin')
ON CONFLICT (username) DO UPDATE
SET email=EXCLUDED.email,password_hash=EXCLUDED.password_hash,role='admin',updated_at=NOW();
UPDATE users
SET username=:'username',password_hash=:'hash',role='admin',updated_at=NOW()
WHERE email=:'email' AND username<>:'username';
SQL
  ok "Admin account created/updated."
}

configure_nginx(){
  section "🌐 Nginx reverse proxy"
  local host="$1"
  cat >/etc/nginx/sites-available/jz-panel.conf <<EOF2
server {
    listen 80;
    listen [::]:80;
    server_name $host;
    client_max_body_size 200m;
    location /api/ { proxy_pass http://127.0.0.1:4000; proxy_http_version 1.1; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme; proxy_read_timeout 120s; }
    location /ws/ { proxy_pass http://127.0.0.1:4001/; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; proxy_set_header X-Forwarded-Proto \$scheme; proxy_read_timeout 3600s; }
    location / { proxy_pass http://127.0.0.1:5173; proxy_http_version 1.1; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme; proxy_read_timeout 120s; }
}
EOF2
  ln -sfn /etc/nginx/sites-available/jz-panel.conf /etc/nginx/sites-enabled/jz-panel.conf
  [[ -e /etc/nginx/sites-enabled/default ]] && mv /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.jz-backup || true
  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx
  ok "Nginx is serving $host"
}

https(){
  (( USE_DOMAIN == 1 )) || return 0
  section "🔒 HTTPS"
  read -rp "Enable Let's Encrypt HTTPS for $PANEL_DOMAIN? [Y/n]: " ans
  [[ "${ans:-Y}" =~ ^[Yy]$ ]] || { warn "HTTPS skipped."; return 0; }
  apt-get install -y certbot python3-certbot-nginx
  read -rp "📧 Let's Encrypt email: " LE_EMAIL
  valid_email "$LE_EMAIL" || die "Invalid Let's Encrypt email."
  certbot --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos --email "$LE_EMAIL" --redirect
  PANEL_ORIGIN="https://$PANEL_DOMAIN"
  upsert_env "$ROOT/.env" PANEL_ORIGIN "$PANEL_ORIGIN"
  upsert_env "$ROOT/.env" WEB_ORIGIN "$PANEL_ORIGIN"
  upsert_env "$ROOT/.env" CORS_ORIGIN "$PANEL_ORIGIN"
  cd "$ROOT"
  docker compose --env-file .env up -d --force-recreate api ws web
  wait_for 'API after HTTPS config' 'curl -fsS http://127.0.0.1:4000/api/ready >/dev/null 2>&1' 120
  ok "HTTPS enabled: $PANEL_ORIGIN"
}

firewall(){
  section "🛡️ Firewall"
  local ssh_port; ssh_port="$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}' || true)"; ssh_port="${ssh_port:-22}"
  ufw allow "$ssh_port/tcp" >/dev/null; ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null; ufw --force enable >/dev/null
  ok "UFW: SSH $ssh_port, HTTP 80, HTTPS 443"
}

final_health(){
  section "🩺 Final verification"
  cd "$ROOT"
  docker compose ps
  curl -fsS http://127.0.0.1:4000/api/ready >/dev/null || die "API readiness failed."
  curl -fsS http://127.0.0.1:5173/ >/dev/null || die "Web health failed."
  curl -fsS http://127.0.0.1:4001/health >/dev/null || die "WebSocket health failed."
  docker compose exec -T redis redis-cli ping | grep -q PONG || die "Redis failed."
  docker compose exec -T postgres pg_isready -U jz -d jz >/dev/null || die "PostgreSQL failed."
  nginx -t >/dev/null && systemctl is-active --quiet nginx || die "Nginx failed."
  if (( USE_DOMAIN == 1 )) && [[ "$PANEL_ORIGIN" == https://* ]]; then curl -fsS --max-time 15 "$PANEL_ORIGIN/api/ready" >/dev/null || die "Public HTTPS API check failed."; fi
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
  init_db
  bootstrap_admin
  configure_nginx "$PANEL_HOST"
  https
  firewall
  final_health
  ROLLBACK_NEEDED=0
  section "🎉 Installation complete"
  echo "J&Z Panel v$VERSION"
  echo "Panel: $PANEL_ORIGIN"
  echo "Admin: $ADMIN_EMAIL"
  echo "Log: $LOG"
}

repair(){
  ROLLBACK_NEEDED=1
  install_docker
  if [[ -f "$ROOT/.env" ]]; then load_existing_config; else prompt_config; write_env; fi
  source_check; compose_validate; build_stack; start_stack; init_db; final_health
  ROLLBACK_NEEDED=0
  ok "Repair completed."
}

health(){
  section "🩺 Diagnostics"
  cd "$ROOT"
  docker compose ps || true
  curl -fsS http://127.0.0.1:4000/api/ready >/dev/null && ok "API healthy" || warn "API unhealthy"
  curl -fsS http://127.0.0.1:5173/ >/dev/null && ok "Web healthy" || warn "Web unhealthy"
  curl -fsS http://127.0.0.1:4001/health >/dev/null && ok "WS healthy" || warn "WS unhealthy"
  docker compose exec -T redis redis-cli ping 2>/dev/null | grep -q PONG && ok "Redis healthy" || warn "Redis unhealthy"
  docker compose exec -T postgres pg_isready -U jz -d jz >/dev/null 2>&1 && ok "PostgreSQL healthy" || warn "PostgreSQL unhealthy"
  nginx -t >/dev/null 2>&1 && ok "Nginx config valid" || warn "Nginx config invalid"
}

backup(){
  section "💾 Backup"
  mkdir -p "$STATE/backups"; cd "$ROOT"
  local out="$STATE/backups/jz-$(date +%Y%m%d-%H%M%S).sql"
  docker compose exec -T postgres pg_dump -U jz -d jz > "$out"; chmod 600 "$out"; ok "Database backup: $out"
}

uninstall(){
  section "🗑️ Uninstall"
  read -rp "Remove J&Z containers and database volume? [y/N]: " a; [[ "${a,,}" == y ]] || return 0
  cd "$ROOT"; docker compose down -v --remove-orphans || true
  rm -f /etc/nginx/sites-enabled/jz-panel.conf /etc/nginx/sites-available/jz-panel.conf
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  ok "J&Z application removed; Docker was left installed."
}

banner(){ clear 2>/dev/null || true; cat <<'EOF2'
╔════════════════════════════════════════════════════════════╗
║                         🚀 J&Z PANEL                      ║
║             Transaction-Safe Production Stack             ║
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
