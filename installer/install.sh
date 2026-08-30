#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="0.9.0"
REPO_URL="https://github.com/Kabin909/J-z.git"
INSTALL_ROOT="/opt/jz-panel"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ORANGE='\033[38;5;208m'
WHITE='\033[97m'
GREEN='\033[92m'
RED='\033[91m'
CYAN='\033[96m'
YELLOW='\033[93m'
RESET='\033[0m'

STATE="/etc/jz-panel"
LOG="/var/log/jz-panel-install.log"
mkdir -p "$STATE"
touch "$LOG"
chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1

on_error() {
  local rc=$?
  echo -e "${RED}❌ Installer failed at line ${BASH_LINENO[0]:-${LINENO}} (exit ${rc}).${RESET}"
  echo -e "${CYAN}📋 Log: $LOG${RESET}"
  if [[ -n "${ROOT:-}" && -f "${ROOT}/docker-compose.yml" ]]; then
    echo -e "${YELLOW}🐳 Recent service state:${RESET}"
    (cd "$ROOT" && docker compose ps) 2>/dev/null || true
  fi
  exit "$rc"
}
trap on_error ERR

ok(){ echo -e "${GREEN}✅ $*${RESET}"; }
warn(){ echo -e "${YELLOW}⚠️  $*${RESET}"; }
die(){ echo -e "${RED}❌ $*${RESET}"; exit 1; }
section(){
  echo -e "\n${ORANGE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${WHITE}$*${RESET}"
}

root_check(){ [[ $EUID -eq 0 ]] || die "Run as root: sudo bash installer/install.sh"; }

os_check(){
  [[ -r /etc/os-release ]] || die "Cannot detect operating system."
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
  ok "System: $PRETTY_NAME / $(dpkg --print-architecture)"
}

bootstrap_repo(){
  # The one-line installer is downloaded to /tmp. In that case the old
  # installer calculated ROOT=/ and tried to read //.env. Always bootstrap
  # the real repository before doing anything that depends on ROOT.
  if [[ -f "$SCRIPT_DIR/../docker-compose.yml" && -f "$SCRIPT_DIR/../.env.example" ]]; then
    ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    return
  fi

  section "📥 Preparing J&Z source"
  if [[ -f "$INSTALL_ROOT/docker-compose.yml" && -f "$INSTALL_ROOT/.env.example" ]]; then
    ROOT="$INSTALL_ROOT"
    ok "Using existing installation at $ROOT"
    return
  fi

  command -v git >/dev/null 2>&1 || {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y git ca-certificates curl
  }

  rm -rf "$INSTALL_ROOT"
  git clone --depth 1 --branch main "$REPO_URL" "$INSTALL_ROOT"
  ROOT="$INSTALL_ROOT"
  ok "Repository bootstrapped at $ROOT"
}

validate_domain(){
  local d="${1:-}"
  [[ -z "$d" ||
     "$d" == "localhost" ||
     "$d" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ||
     "$d" =~ ^([A-Za-z0-9-]+\.)+[A-Za-z]{2,63}$ ]] ||
     die "Invalid domain/IP: $d"
}

get_public_ip(){
  curl -4fsS --max-time 8 https://api.ipify.org 2>/dev/null ||
  hostname -I | awk '{print $1}'
}

normalize_url(){
  local u="$1"
  [[ "$u" =~ ^https?:// ]] || u="http://$u"
  printf '%s' "${u%/}"
}

secret(){
  python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(48))
PY
}

apt_install(){
  export DEBIAN_FRONTEND=noninteractive
  section "📦 Installing system dependencies"
  apt-get update -y
  apt-get install -y \
    ca-certificates curl git jq openssl python3 nginx ufw \
    docker.io docker-compose-plugin golang-go
  systemctl enable --now docker
  systemctl enable --now nginx
  docker info >/dev/null 2>&1 || die "Docker daemon is not available."
  docker compose version >/dev/null 2>&1 || die "Docker Compose plugin is missing."
  ok "Docker and required system packages are ready."
}

configure_domain(){
  local domain="$1"
  validate_domain "$domain"

  PANEL_HOST="$domain"
  [[ -n "$PANEL_HOST" ]] || PANEL_HOST="$(get_public_ip)"
  [[ -n "$PANEL_HOST" ]] || die "Could not determine VPS public IP."

  PANEL_ORIGIN="http://$PANEL_HOST"

  section "🌐 Panel address"
  echo -e "${WHITE}Panel URL: ${CYAN}${PANEL_ORIGIN}${RESET}"

  if [[ "$PANEL_HOST" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "$PANEL_HOST" == "localhost" ]]; then
    cat >/etc/nginx/sites-available/jz-panel.conf <<NGINX
server {
    listen 80 default_server;
    server_name _;
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
        proxy_pass http://127.0.0.1:4000/api/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /ws/ {
        proxy_pass http://127.0.0.1:4001/api/ws/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
NGINX
  else
    cat >/etc/nginx/sites-available/jz-panel.conf <<NGINX
server {
    listen 80;
    server_name $PANEL_HOST;
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
        proxy_pass http://127.0.0.1:4000/api/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /ws/ {
        proxy_pass http://127.0.0.1:4001/api/ws/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
NGINX
  fi

  ln -sfn /etc/nginx/sites-available/jz-panel.conf /etc/nginx/sites-enabled/jz-panel.conf
  rm -f /etc/nginx/sites-enabled/default
  nginx -t >/dev/null
  systemctl reload nginx
  printf '%s\n' "$PANEL_ORIGIN" >"$STATE/url"
  ok "Nginx configured for $PANEL_ORIGIN"
}

enable_https(){
  local domain="$1"
  [[ -n "$domain" && "$domain" != "localhost" &&
     "$domain" =~ ^([A-Za-z0-9-]+\.)+[A-Za-z]{2,63}$ ]] || return 0

  read -rp "🔒 Enable Let's Encrypt HTTPS for $domain? [Y/n]: " ans
  ans="${ans:-Y}"
  [[ "${ans,,}" == "y" ]] || return 0

  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y certbot python3-certbot-nginx
  certbot --nginx -d "$domain" --non-interactive --agree-tos \
    --register-unsafely-without-email --redirect

  PANEL_ORIGIN="https://$domain"
  printf '%s\n' "$PANEL_ORIGIN" >"$STATE/url"
  ok "HTTPS enabled: $PANEL_ORIGIN"
}

set_env_value(){
  local file="$1" key="$2" value="$3"
  python3 - "$file" "$key" "$value" <<'PY'
from pathlib import Path
import sys, re
p=Path(sys.argv[1])
key=sys.argv[2]
value=sys.argv[3]
text=p.read_text() if p.exists() else ""
line=f"{key}={value}"
pattern=rf"^{re.escape(key)}=.*$"
if re.search(pattern,text,re.M):
    text=re.sub(pattern,lambda _:line,text,flags=re.M)
else:
    if text and not text.endswith("\n"):
        text += "\n"
    text += line + "\n"
p.write_text(text)
PY
}

write_env(){
  section "🔐 Configuring production environment"
  cd "$ROOT"
  [[ -f ".env.example" ]] || die "Missing $ROOT/.env.example"
  [[ -f ".env" ]] || cp ".env.example" ".env"

  local dbpass jwt cookie wings nodekey bootstrap
  dbpass="$(grep -E '^POSTGRES_PASSWORD=' .env | head -1 | cut -d= -f2- || true)"
  jwt="$(grep -E '^JWT_SECRET=' .env | head -1 | cut -d= -f2- || true)"
  cookie="$(grep -E '^COOKIE_SECRET=' .env | head -1 | cut -d= -f2- || true)"
  wings="$(grep -E '^WINGS_SHARED_SECRET=' .env | head -1 | cut -d= -f2- || true)"
  nodekey="$(grep -E '^NODE_ENCRYPTION_KEY=' .env | head -1 | cut -d= -f2- || true)"
  bootstrap="$(grep -E '^JZ_BOOTSTRAP_TOKEN=' .env | head -1 | cut -d= -f2- || true)"

  [[ -n "$dbpass" && "$dbpass" != *"change-me"* ]] || dbpass="$(secret)"
  [[ -n "$jwt" && "$jwt" != *"change-me"* ]] || jwt="$(secret)"
  [[ -n "$cookie" && "$cookie" != *"change-me"* ]] || cookie="$(secret)"
  [[ -n "$wings" && "$wings" != *"change-me"* ]] || wings="$(secret)"
  [[ -n "$nodekey" && "$nodekey" != *"change-me"* ]] || nodekey="$(secret)"
  [[ -n "$bootstrap" && "$bootstrap" != *"change-me"* ]] || bootstrap="$(secret)"

  set_env_value .env POSTGRES_PASSWORD "$dbpass"
  set_env_value .env JWT_SECRET "$jwt"
  set_env_value .env COOKIE_SECRET "$cookie"
  set_env_value .env WINGS_SHARED_SECRET "$wings"
  set_env_value .env NODE_ENCRYPTION_KEY "$nodekey"
  set_env_value .env JZ_BOOTSTRAP_TOKEN "$bootstrap"
  set_env_value .env WEB_ORIGIN "$PANEL_ORIGIN"
  set_env_value .env ADMIN_USERNAME "$ADMIN_USERNAME"
  set_env_value .env ADMIN_EMAIL "$ADMIN_EMAIL"
  set_env_value .env ADMIN_PASSWORD "$ADMIN_PASSWORD"
  set_env_value .env NODE_ENV "production"

  chmod 600 .env
  ok "Production environment is ready."
}

compose_build_up(){
  section "🐳 Building J&Z Panel services"
  cd "$ROOT"
  docker compose config >/dev/null || die "docker-compose.yml is invalid."

  # Pulling/building the current main branch avoids the stale ioredis/pg
  # dependency errors found in older checkouts. Current source declares
  # @types/pg and uses a constructor-compatible ioredis import.
  docker compose build --pull --progress plain || {
    warn "Docker build failed. Showing the failing service logs."
    docker compose ps || true
    die "Docker build failed. Update the repository to the latest main branch and retry Repair."
  }

  docker compose up -d --remove-orphans

  for _ in $(seq 1 90); do
    if curl -fsS --max-time 3 http://127.0.0.1:4000/api/ready >/dev/null 2>&1; then
      ok "API is ready."
      break
    fi
    sleep 2
  done

  curl -fsS --max-time 5 http://127.0.0.1:4000/api/ready >/dev/null ||
    { docker compose ps; docker compose logs --tail=120 api worker ws web || true; die "J&Z services did not become ready."; }

  docker compose ps
}

prompt_wings(){
  local default_ip
  default_ip="$(get_public_ip)"
  WINGS_PORT="${WINGS_PORT:-8080}"
  WINGS_NODE_NAME="${WINGS_NODE_NAME:-Local-01}"

  echo
  read -rp "🪽 Wings node name [Local-01]: " input
  WINGS_NODE_NAME="${input:-Local-01}"

  read -rp "🌐 Wings public address (IP or domain) [$default_ip]: " input
  WINGS_PUBLIC_HOST="${input:-$default_ip}"
  validate_domain "$WINGS_PUBLIC_HOST"

  while :; do
    read -rp "🔌 Wings API port [8080]: " input
    WINGS_PORT="${input:-8080}"
    [[ "$WINGS_PORT" =~ ^[0-9]+$ && "$WINGS_PORT" -ge 1024 && "$WINGS_PORT" -le 65535 ]] && break
    warn "Use a TCP port from 1024 to 65535."
  done

  WINGS_ADDRESS="http://${WINGS_PUBLIC_HOST}:${WINGS_PORT}"
  echo -e "${WHITE}Wings address: ${CYAN}${WINGS_ADDRESS}${RESET}"
}

wings(){
  section "🪽 Installing J&Z Wings"
  command -v go >/dev/null 2>&1 || die "Go compiler is missing."

  [[ -d "$ROOT/wings" ]] || die "Missing $ROOT/wings source."
  cd "$ROOT/wings"
  go build -o /tmp/jz-wings .
  install -Dm755 /tmp/jz-wings /usr/local/bin/jz-wings

  mkdir -p /etc/jz /var/lib/jz-wings/servers

  cat >/etc/systemd/system/jz-wings.service <<'UNIT'
[Unit]
Description=J&Z Wings
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

  if [[ "$MODE" == "combo" ]]; then
    local token response nodeid secret
    token="$(grep '^JZ_BOOTSTRAP_TOKEN=' "$ROOT/.env" | cut -d= -f2-)"
    [[ -n "$token" ]] || die "JZ_BOOTSTRAP_TOKEN is missing."

    for _ in $(seq 1 60); do
      curl -fsS http://127.0.0.1:4000/api/ready >/dev/null 2>&1 && break
      sleep 2
    done

    response="$(
      curl -fsS -X POST \
        http://127.0.0.1:4000/api/bootstrap/local-node \
        -H 'content-type: application/json' \
        -H "x-jz-bootstrap-token: $token" \
        -d "$(python3 - "$WINGS_NODE_NAME" "$WINGS_ADDRESS" <<'PY'
import json,sys
print(json.dumps({
    "name": sys.argv[1],
    "address": sys.argv[2],
    "location": "local"
}))
PY
)" \
    )" || die "Panel/Wings bootstrap failed. Check API logs."

    nodeid="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["node"]["id"])' <<<"$response")"
    secret="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["secret"])' <<<"$response")"

    cat >/etc/jz/wings.env <<EOF
JZ_PANEL_URL=http://127.0.0.1:4000
JZ_NODE_ID=$nodeid
WINGS_SHARED_SECRET=$secret
WINGS_BIND=:$WINGS_PORT
WINGS_SERVERS_ROOT=/var/lib/jz-wings/servers
DOCKER_HOST=unix:///var/run/docker.sock
EOF
  else
    [[ -n "${EXTERNAL_WINGS_SECRET:-}" ]] || die "Wings-only mode requires a node secret."
    cat >/etc/jz/wings.env <<EOF
JZ_PANEL_URL=$EXISTING_PANEL_URL
JZ_NODE_ID=$EXTERNAL_NODE_ID
WINGS_SHARED_SECRET=$EXTERNAL_WINGS_SECRET
WINGS_BIND=:$WINGS_PORT
WINGS_SERVERS_ROOT=/var/lib/jz-wings/servers
DOCKER_HOST=unix:///var/run/docker.sock
EOF
  fi

  chmod 600 /etc/jz/wings.env
  systemctl enable --now jz-wings
  sleep 2

  if ! systemctl is-active --quiet jz-wings; then
    journalctl -u jz-wings -n 100 --no-pager || true
    die "Wings failed to start."
  fi

  ok "Wings is running on port $WINGS_PORT."
}

firewall(){
  section "🛡️ Firewall"
  ufw allow OpenSSH
  ufw allow 80/tcp
  ufw allow 443/tcp
  [[ -n "${WINGS_PORT:-}" ]] && ufw allow "$WINGS_PORT"/tcp
  ufw --force enable
  ok "Firewall configured."
}

health(){
  section "🩺 Final diagnostics"
  [[ -n "${ROOT:-}" && -f "$ROOT/docker-compose.yml" ]] || {
    warn "J&Z repository is not installed at $INSTALL_ROOT."
    return 0
  }

  cd "$ROOT"
  docker compose ps || true
  curl -fsS --max-time 5 http://127.0.0.1:4000/api/ready >/dev/null &&
    ok "API ready" || warn "API is not ready."
  curl -fsS --max-time 5 http://127.0.0.1:5173/ >/dev/null &&
    ok "Web UI reachable" || warn "Web UI is not reachable."
  if systemctl is-active --quiet jz-wings 2>/dev/null; then
    ok "Wings service active."
  else
    warn "Wings service is not active."
  fi
  if [[ -n "${WINGS_PORT:-}" ]]; then
    ss -lnt 2>/dev/null | grep -q ":${WINGS_PORT} " &&
      ok "Wings port ${WINGS_PORT} is listening." ||
      warn "Wings port ${WINGS_PORT} is not listening."
  fi
}

uninstall(){
  section "🗑️ Uninstall J&Z"
  read -rp "Remove J&Z containers, database volume, Nginx config and Wings? [y/N]: " answer
  [[ "${answer,,}" == "y" ]] || { warn "Uninstall cancelled."; return; }

  if [[ -n "${ROOT:-}" && -f "$ROOT/docker-compose.yml" ]]; then
    cd "$ROOT"
    docker compose down -v --remove-orphans || true
  fi

  systemctl disable --now jz-wings 2>/dev/null || true
  rm -f /etc/systemd/system/jz-wings.service /usr/local/bin/jz-wings /etc/jz/wings.env
  systemctl daemon-reload

  rm -f /etc/nginx/sites-enabled/jz-panel.conf /etc/nginx/sites-available/jz-panel.conf
  systemctl reload nginx 2>/dev/null || true

  rm -rf "$STATE"
  ok "J&Z services removed. Docker itself was intentionally left installed."
}

repair(){
  root_check
  bootstrap_repo
  apt_install
  section "🛠️ Repairing J&Z"
  cd "$ROOT"

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git fetch origin main
    git reset --hard origin/main
    ok "Source synchronized with origin/main."
  fi

  [[ -f ".env" ]] || {
    [[ -f ".env.example" ]] || die "Missing .env.example"
    cp .env.example .env
  }

  docker compose down --remove-orphans || true
  docker compose build --pull --progress plain
  docker compose up -d --remove-orphans
  health
}

update(){
  root_check
  bootstrap_repo
  section "🔄 Updating J&Z"
  cd "$ROOT"

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git fetch origin main
    git reset --hard origin/main
  else
    die "The J&Z directory is not a git checkout."
  fi

  docker compose build --pull --progress plain
  docker compose up -d --remove-orphans
  health
}

install_panel(){
  MODE="$1"

  section "🚀 J&Z Panel Installation"

  read -rp "🌐 Panel domain (example: panel.example.com, blank = VPS IP): " PANEL_DOMAIN
  validate_domain "$PANEL_DOMAIN"

  read -rp "👤 Admin username [admin]: " ADMIN_USERNAME
  ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
  [[ "$ADMIN_USERNAME" =~ ^[a-zA-Z0-9_.-]{3,32}$ ]] || die "Invalid admin username."

  read -rp "📧 Admin email: " ADMIN_EMAIL
  [[ "$ADMIN_EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] ||
    die "Valid admin email required."

  while :; do
    read -rsp "🔑 Admin password (12+ chars): " ADMIN_PASSWORD
    echo
    [[ ${#ADMIN_PASSWORD} -ge 12 ]] && break
    warn "Password must be at least 12 characters."
  done

  configure_domain "$PANEL_DOMAIN"
  enable_https "$PANEL_DOMAIN"

  # IMPORTANT: create .env AFTER HTTPS has finalized PANEL_ORIGIN.
  # This fixes the old `sed: can't read //.env` failure and ensures CORS
  # matches the actual http/https panel URL.
  write_env
  compose_build_up

  if [[ "$MODE" == "combo" ]]; then
    prompt_wings
    wings
    firewall
  fi

  health

  section "🎉 Installation complete"
  echo -e "${WHITE}Panel: ${CYAN}${PANEL_ORIGIN}${RESET}"
  [[ "$MODE" == "combo" ]] && echo -e "${WHITE}Wings: ${CYAN}${WINGS_ADDRESS}${RESET}"
  echo -e "${WHITE}Admin: ${CYAN}${ADMIN_EMAIL}${RESET}"
  echo -e "${CYAN}📋 Log: $LOG${RESET}"
}

banner(){
  clear 2>/dev/null || true
  echo -e "${ORANGE}"
  cat <<'ASCII'
       ██╗ █████╗ ███╗   ██╗███████╗
       ██║██╔══██╗████╗  ██║╚══███╔╝
       ██║███████║██╔██╗ ██║  ███╔╝
  ██   ██║██╔══██║██║╚██╗██║ ███╔╝
  ╚█████╔╝██║  ██║██║ ╚████║███████╗
   ╚════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝
                    J&Z PANEL
ASCII
  echo -e "${RESET}"
  echo -e "${WHITE}J&Z Panel Installation Manager v${VERSION}${RESET}"
  echo -e "${CYAN}Powerful infrastructure. Simple control. Built to scale.${RESET}"
  echo
}

main(){
  root_check
  os_check
  bootstrap_repo

  banner
  echo "  1) 🟧 Panel + 🪽 Wings"
  echo "  2) 🟧 Panel"
  echo "  3) 🪽 Wings"
  echo "  4) 🛠️ Repair"
  echo "  5) 🔄 Update"
  echo "  6) 🩺 Diagnostics"
  echo "  7) 🗑️ Uninstall"
  echo "  8) Exit"
  echo

  read -rp "Select an option: " choice

  case "$choice" in
    1)
      apt_install
      install_panel combo
      ;;
    2)
      apt_install
      install_panel panel
      ;;
    3)
      apt_install
      MODE="wings"
      read -rp "🌐 Existing Panel URL (example: https://panel.example.com): " EXISTING_PANEL_URL
      EXISTING_PANEL_URL="$(normalize_url "$EXISTING_PANEL_URL")"
      [[ "$EXISTING_PANEL_URL" =~ ^https?://[^/]+$ ]] || die "Invalid Panel URL."

      read -rp "🆔 Node ID: " EXTERNAL_NODE_ID
      [[ -n "$EXTERNAL_NODE_ID" ]] || die "Node ID is required."

      read -rsp "🔐 Node secret: " EXTERNAL_WINGS_SECRET
      echo
      [[ -n "$EXTERNAL_WINGS_SECRET" ]] || die "Node secret is required."

      prompt_wings
      wings
      firewall
      health
      ;;
    4) repair ;;
    5) update ;;
    6) health ;;
    7) uninstall ;;
    8) exit 0 ;;
    *) die "Invalid option." ;;
  esac
}

main "$@"
