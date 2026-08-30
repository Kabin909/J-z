#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE=/etc/jz-panel
LOG=/var/log/jz-panel-install.log
mkdir -p "$STATE"
touch "$LOG"; chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1

err(){ local rc=$?; echo "❌ Installer failed at line $1 (exit $rc)."; echo "📋 Log: $LOG"; exit "$rc"; }
trap 'err $LINENO' ERR
ok(){ echo "✅ $*"; }
warn(){ echo "⚠️  $*"; }
die(){ echo "❌ $*"; exit 1; }
section(){ printf '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n%s\n' "$*"; }

require_root(){ [[ $EUID -eq 0 ]] || die "Run as root: sudo bash installer/install.sh"; }
check_os(){
  . /etc/os-release
  case "$ID" in
    debian) [[ "${VERSION_ID%%.*}" -ge 12 ]] || die "Debian 12+ required." ;;
    ubuntu) [[ "${VERSION_ID%%.*}" -ge 22 ]] || die "Ubuntu 22.04+ required." ;;
    *) die "Supported OS: Debian 12+ or Ubuntu 22.04+." ;;
  esac
  case "$(dpkg --print-architecture)" in amd64|arm64) ;; *) die "Supported architectures: amd64 or arm64.";; esac
  ok "System: $PRETTY_NAME / $(dpkg --print-architecture)"
}

fix_duplicate_sury(){
  local a=/etc/apt/sources.list.d/php.list b=/etc/apt/sources.list.d/sury-php.list
  [[ -f "$a" && -f "$b" ]] || return 0
  if grep -q 'packages.sury.org/php' "$a" && grep -q 'packages.sury.org/php' "$b"; then
    # Keep the newer/common sury-php filename and disable the duplicate only.
    mv -f "$a" "${a}.disabled-by-jz"
    warn "Disabled duplicate Sury PHP source: $a"
  fi
}

install_docker(){
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    systemctl enable --now docker
    ok "Docker and Compose already available."
    return
  fi
  section "🐳 Installing Docker"
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/${ID}/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  local arch; arch="$(dpkg --print-architecture)"
  echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" >/etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  docker info >/dev/null || die "Docker daemon is unavailable."
  docker compose version >/dev/null || die "Docker Compose is unavailable."
  ok "Docker $(docker --version | cut -d' ' -f3 | tr -d ',') / $(docker compose version --short)"
}

install_deps(){
  section "📦 Preparing system"
  fix_duplicate_sury
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y ca-certificates curl git jq openssl nginx ufw
  install_docker
  systemctl enable --now nginx
}

valid_domain(){
  local d="$1"
  [[ -z "$d" ]] && return 0
  [[ "$d" != "localhost" ]] || return 1
  [[ "$d" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}
valid_email(){ [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; }
public_ip(){ curl -4fsS --max-time 8 https://api.ipify.org || hostname -I | awk '{print $1}'; }
secret(){ openssl rand -hex 32; }

write_env(){
  section "🔐 Creating configuration"
  [[ -f .env ]] || cp .env.example .env
  local db jwt cookie wings
  db="$(grep '^POSTGRES_PASSWORD=' .env | cut -d= -f2- || true)"; [[ -n "$db" && "$db" != CHANGE_ME ]] || db="$(secret)"
  jwt="$(grep '^JWT_SECRET=' .env | cut -d= -f2- || true)"; [[ -n "$jwt" && "$jwt" != CHANGE_ME ]] || jwt="$(secret)"
  cookie="$(grep '^COOKIE_SECRET=' .env | cut -d= -f2- || true)"; [[ -n "$cookie" && "$cookie" != CHANGE_ME ]] || cookie="$(secret)"
  wings="$(grep '^WINGS_SHARED_SECRET=' .env | cut -d= -f2- || true)"; [[ -n "$wings" && "$wings" != CHANGE_ME ]] || wings="$(secret)"
  export DBPASS="$db" JWT="$jwt" COOKIE="$cookie" WINGS="$wings" ORIGIN="$PANEL_ORIGIN"
  python3 - <<'PY'
from pathlib import Path
import os, re
p=Path('.env')
text=p.read_text()
vals={
 'POSTGRES_PASSWORD':os.environ['DBPASS'],
 'DATABASE_URL':f'postgresql://jz:{os.environ["DBPASS"]}@postgres:5432/jz',
 'REDIS_URL':'redis://redis:6379',
 'JWT_SECRET':os.environ['JWT'],
 'COOKIE_SECRET':os.environ['COOKIE'],
 'WINGS_SHARED_SECRET':os.environ['WINGS'],
 'PANEL_ORIGIN':os.environ['ORIGIN'],
 'NODE_ENV':'production',
 'ADMIN_USERNAME':os.environ.get('ADMIN_USERNAME','admin'),
 'ADMIN_EMAIL':os.environ.get('ADMIN_EMAIL',''),
 'ADMIN_PASSWORD':os.environ.get('ADMIN_PASSWORD','')
}
for k,v in vals.items():
    pattern=rf'^{re.escape(k)}=.*$'
    if re.search(pattern,text,re.M): text=re.sub(pattern,f'{k}={v}',text,flags=re.M)
    else: text += f'\n{k}={v}'
p.write_text(text)
p.chmod(0o600)
PY
  ok "Production .env ready."
}

configure_nginx(){
  local host="$1"
  section "🌐 Configuring Nginx for $host"
  cat >/etc/nginx/sites-available/jz-panel.conf <<EOF2
server {
    listen 80;
    server_name $host;
    client_max_body_size 200m;

    location / {
        proxy_pass http://127.0.0.1:5173;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location /api/ {
        proxy_pass http://127.0.0.1:4000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location /ws/ {
        proxy_pass http://127.0.0.1:4001/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF2
  ln -sfn /etc/nginx/sites-available/jz-panel.conf /etc/nginx/sites-enabled/jz-panel.conf
  if [[ -e /etc/nginx/sites-enabled/default && ! -e /etc/nginx/sites-enabled/default.jz-backup ]]; then
    mv /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.jz-backup
  fi
  nginx -t
  systemctl reload nginx
  ok "Nginx configured."
}

start_stack(){
  section "🐳 Building J&Z services"
  cd "$ROOT"
  docker compose config >/dev/null
  docker compose build --pull --progress plain
  docker compose up -d --remove-orphans
  for i in $(seq 1 60); do
    if curl -fsS http://127.0.0.1:4000/api/ready >/dev/null 2>&1; then ok "API is ready."; break; fi
    [[ $i -eq 60 ]] && { docker compose ps; docker compose logs --tail=100 api worker ws web; die "Services did not become ready."; }
    sleep 2
  done
  docker compose ps
}

https(){
  local domain="$1"
  [[ "$domain" =~ ^([A-Za-z0-9-]+\.)+[A-Za-z]{2,63}$ ]] || return 0
  read -rp "🔒 Enable Let's Encrypt HTTPS now? [Y/n]: " ans
  [[ "${ans:-Y}" =~ ^[Yy]$ ]] || return 0
  apt-get install -y certbot python3-certbot-nginx
  read -rp "📧 Let's Encrypt email (recommended): " email
  valid_email "$email" || die "A valid email is required for HTTPS."
  if certbot --nginx -d "$domain" --non-interactive --agree-tos --email "$email" --redirect; then
    PANEL_ORIGIN="https://$domain"
    sed -i "s#^PANEL_ORIGIN=.*#PANEL_ORIGIN=$PANEL_ORIGIN#" .env 2>/dev/null || true
    ok "HTTPS enabled: $PANEL_ORIGIN"
  else
    warn "Let's Encrypt could not issue a certificate. Continuing safely on HTTP. Check DNS/ports 80 and 443, then rerun Repair/Update."
    PANEL_ORIGIN="http://$domain"
  fi
}

firewall(){
  section "🛡️ Firewall"
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
  local ssh_port
  ssh_port="$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}')"
  [[ -n "$ssh_port" ]] || ssh_port=22
  ufw allow "$ssh_port/tcp" >/dev/null
  ufw --force enable >/dev/null
  ok "UFW enabled; SSH $ssh_port, HTTP 80, HTTPS 443."
}

install_wings_agent(){
  section "🪽 Installing J&Z Wings node agent"
  command -v go >/dev/null 2>&1 || { export DEBIAN_FRONTEND=noninteractive; apt-get install -y golang-go; }
  cd "$ROOT/wings"
  go build -trimpath -ldflags='-s -w' -o /usr/local/bin/jz-wings .
  install -d -m 0750 /etc/jz /var/lib/jz-wings/servers
  cat >/etc/jz/wings.env <<EOF2
WINGS_PORT=${WINGS_PORT:-8080}
JZ_PANEL_URL=${PANEL_ORIGIN:-http://127.0.0.1:5173}
DOCKER_HOST=unix:///var/run/docker.sock
WINGS_SERVERS_ROOT=/var/lib/jz-wings/servers
EOF2
  chmod 600 /etc/jz/wings.env
  cat >/etc/systemd/system/jz-wings.service <<'UNIT'
[Unit]
Description=J&Z Wings Node Agent
After=docker.service network-online.target
Wants=network-online.target
Requires=docker.service
[Service]
Type=simple
EnvironmentFile=/etc/jz/wings.env
ExecStart=/usr/local/bin/jz-wings
Restart=always
RestartSec=3
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable --now jz-wings
  sleep 1
  systemctl is-active --quiet jz-wings || { journalctl -u jz-wings -n 80 --no-pager; die "J&Z Wings agent failed to start."; }
  curl -fsS "http://127.0.0.1:${WINGS_PORT:-8080}/health" >/dev/null || die "J&Z Wings health check failed."
  ok "J&Z Wings node agent is running on port ${WINGS_PORT:-8080}."
}

panel_install(){
  section "🚀 J&Z Panel installation"
  read -rp "🌐 Panel domain (blank = VPS IP): " DOMAIN
  if [[ -n "$DOMAIN" ]]; then valid_domain "$DOMAIN" || die "Invalid domain: $DOMAIN"; PANEL_HOST="$DOMAIN"; else PANEL_HOST="$(public_ip)"; fi
  PANEL_ORIGIN="http://$PANEL_HOST"
  read -rp "👤 Admin username [admin]: " ADMIN_USERNAME; ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
  read -rp "📧 Admin email: " ADMIN_EMAIL; valid_email "$ADMIN_EMAIL" || die "Valid admin email required."
  while :; do read -rsp "🔑 Admin password (12+ chars): " ADMIN_PASSWORD; echo; [[ ${#ADMIN_PASSWORD} -ge 12 ]] && break; warn "Password must be at least 12 characters."; done
  export ADMIN_USERNAME ADMIN_EMAIL ADMIN_PASSWORD
  configure_nginx "$PANEL_HOST"
  if [[ "$PANEL_HOST" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    warn "Using IP address; HTTPS is skipped because Let's Encrypt needs a DNS name."
  else
    https "$PANEL_HOST"
  fi
  write_env
  cd "$ROOT"
  docker compose down --remove-orphans >/dev/null 2>&1 || true
  start_stack
  # The bootstrap password is only needed during first API startup; do not retain it in .env.
  sed -i '/^ADMIN_PASSWORD=/d' .env 2>/dev/null || true
  chmod 600 .env
  firewall
  ok "Panel stack is running."
}

repair(){
  section "🛠️ Repair"
  install_deps
  cd "$ROOT"
  [[ -f .env ]] || cp .env.example .env
  docker compose config >/dev/null
  docker compose down --remove-orphans || true
  docker compose build --pull --progress plain
  docker compose up -d --remove-orphans
  curl -fsS http://127.0.0.1:4000/api/ready >/dev/null
  ok "Repair completed."
}
health(){
  section "🩺 Health"
  cd "$ROOT"
  docker compose ps
  curl -fsS http://127.0.0.1:4000/api/health >/dev/null && ok "API healthy" || warn "API unhealthy"
  curl -fsS http://127.0.0.1:5173/ >/dev/null && ok "Web healthy" || warn "Web unhealthy"
  docker compose exec -T redis redis-cli ping 2>/dev/null | grep -q PONG && ok "Redis healthy" || warn "Redis unhealthy"
  docker compose exec -T postgres pg_isready -U jz -d jz >/dev/null 2>&1 && ok "PostgreSQL healthy" || warn "PostgreSQL unhealthy"
}
backup(){
  section "💾 Backup"
  mkdir -p "$STATE/backups"
  cd "$ROOT"
  local out="$STATE/backups/jz-$(date +%Y%m%d-%H%M%S).sql"
  docker compose exec -T postgres pg_dump -U jz -d jz >"$out"
  chmod 600 "$out"
  ok "Database backup: $out"
}
uninstall(){
  section "🗑️ Uninstall"
  read -rp "Remove J&Z containers and database volume? [y/N]: " a
  [[ "${a,,}" == y ]] || return
  cd "$ROOT"
  docker compose down -v --remove-orphans || true
  rm -f /etc/nginx/sites-enabled/jz-panel.conf /etc/nginx/sites-available/jz-panel.conf
  nginx -t && systemctl reload nginx || true
  rm -rf "$STATE"
  ok "J&Z application removed. Docker was left installed."
}

banner(){
  clear 2>/dev/null || true
  cat <<'EOF2'
╔════════════════════════════════════════════════════════════╗
║                     🚀 J&Z PANEL                         ║
║             Full Panel + Wings Stack                     ║
║                  🟧 Orange / White                        ║
╚════════════════════════════════════════════════════════════╝
EOF2
}

main(){
  require_root; check_os; banner
  echo "1) 🟧 Panel + 🪽 Wings"
  echo "2) 🟧 Panel only"
  echo "3) 🪽 Wings only"
  echo "4) 🛠️ Repair"
  echo "5) 🔄 Update"
  echo "6) 🩺 Health"
  echo "7) 💾 Backup"
  echo "8) 🗑️ Uninstall"
  echo "9) Exit"
  read -rp "Select [1-9]: " c
  case "$c" in
    1) install_deps; panel_install; WINGS_PORT=8080; install_wings_agent; firewall; health;;
    2) install_deps; panel_install;;
    3) install_deps; MODE=wings; read -rp "🌐 Existing Panel URL: " EXISTING_PANEL_URL; WINGS_PORT=8080; install_wings_agent; firewall; health;;
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
