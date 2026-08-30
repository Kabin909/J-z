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
 'DATABASE_URL':'postgresql://jz:${POSTGRES_PASSWORD}@postgres:5432/jz',
 'REDIS_URL':'redis://redis:6379',
 'JWT_SECRET':os.environ['JWT'],
 'COOKIE_SECRET':os.environ['COOKIE'],
 'WINGS_SHARED_SECRET':os.environ['WINGS'],
 'PANEL_ORIGIN':os.environ['ORIGIN'],
 'NODE_ENV':'production'
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
  certbot --nginx -d "$domain" --non-interactive --agree-tos --email "$email" --redirect
  PANEL_ORIGIN="https://$domain"
  sed -i "s#^PANEL_ORIGIN=.*#PANEL_ORIGIN=$PANEL_ORIGIN#" .env
  ok "HTTPS enabled: $PANEL_ORIGIN"
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

panel_install(){
  section "🚀 J&Z Panel installation"
  read -rp "🌐 Panel domain (blank = VPS IP): " DOMAIN
  if [[ -n "$DOMAIN" ]]; then valid_domain "$DOMAIN" || die "Invalid domain: $DOMAIN"; else DOMAIN="$(public_ip)"; fi
  PANEL_ORIGIN="http://$DOMAIN"
  write_env
  configure_nginx "$DOMAIN"
  start_stack
  https "$DOMAIN"
  firewall
  section "🎉 Installation complete"
  echo "Panel: $PANEL_ORIGIN"
  echo "Health: $PANEL_ORIGIN/api/health"
  echo "Log: $LOG"
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
    1) die "The full Panel + Wings release is not included in this foundation ZIP yet. Use Panel only for this tested foundation.";;
    2) install_deps; panel_install;;
    3) die "The full Wings daemon is not included in this foundation ZIP yet.";;
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
