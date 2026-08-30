#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
VERSION="0.8.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE=/etc/jz-panel
LOG=/var/log/jz-panel-install.log
ORANGE='\033[38;5;208m'; WHITE='\033[97m'; GREEN='\033[92m'; RED='\033[91m'; CYAN='\033[96m'; RESET='\033[0m'
mkdir -p "$STATE"; touch "$LOG"; chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1
on_error(){ rc=$?; echo -e "${RED}❌ Installer failed at line ${LINENO} (exit ${rc}).${RESET}"; echo -e "${CYAN}📋 Log: $LOG${RESET}"; exit "$rc"; }
trap on_error ERR
ok(){ echo -e "${GREEN}✅ $*${RESET}"; }; warn(){ echo -e "${ORANGE}⚠️  $*${RESET}"; }; die(){ echo -e "${RED}❌ $*${RESET}"; exit 1; }
section(){ echo -e "\n${ORANGE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n${WHITE}$*${RESET}"; }
root(){ [[ $EUID -eq 0 ]] || die "Run as root: sudo bash installer/install.sh"; }
os(){ . /etc/os-release; case "$ID" in debian|ubuntu) ;; *) die "Supported OS: Debian 12+ or Ubuntu 22.04+.";; esac; ok "System: $PRETTY_NAME / $(dpkg --print-architecture)"; }
validate_domain(){ local d="$1"; [[ -z "$d" || "$d" == "localhost" || "$d" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "$d" =~ ^([A-Za-z0-9-]+\.)+[A-Za-z]{2,63}$ ]] || die "Invalid domain/IP: $d"; }
get_public_ip(){ curl -4fsS --max-time 8 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}'; }
apt(){ export DEBIAN_FRONTEND=noninteractive; section "📦 Installing system dependencies"; apt-get update -y; apt-get install -y ca-certificates curl git jq openssl python3 nginx ufw docker.io docker-compose-plugin golang-go; systemctl enable --now docker nginx; docker info >/dev/null || die "Docker daemon is not available."; docker compose version >/dev/null || die "Docker Compose plugin is missing."; }
secret(){ python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(48))
PY
}
write_env(){
  section "🔐 Configuring production secrets"
  [[ -f "$ROOT/.env" ]] || cp "$ROOT/.env.example" "$ROOT/.env"
  local dbpass jwt cookie wings nodekey bootstrap
  dbpass="$(secret)"; jwt="$(secret)"; cookie="$(secret)"; wings="$(secret)"; nodekey="$(secret)"; bootstrap="$(secret)"
  python3 - "$ROOT/.env" "$dbpass" "$jwt" "$cookie" "$wings" "$nodekey" "$bootstrap" "$PANEL_ORIGIN" "$ADMIN_USERNAME" "$ADMIN_EMAIL" "$ADMIN_PASSWORD" <<'PY'
from pathlib import Path
import sys,re
p=Path(sys.argv[1]); text=p.read_text()
vals={'POSTGRES_PASSWORD':sys.argv[2],'JWT_SECRET':sys.argv[3],'COOKIE_SECRET':sys.argv[4],'WINGS_SHARED_SECRET':sys.argv[5],'NODE_ENCRYPTION_KEY':sys.argv[6],'JZ_BOOTSTRAP_TOKEN':sys.argv[7],'WEB_ORIGIN':sys.argv[8],'ADMIN_USERNAME':sys.argv[9],'ADMIN_EMAIL':sys.argv[10],'ADMIN_PASSWORD':sys.argv[11],'NODE_ENV':'production'}
for k,v in vals.items():
    text=re.sub(rf'^{re.escape(k)}=.*$',f'{k}={v}',text,flags=re.M)
    if not re.search(rf'^{re.escape(k)}=',text,re.M): text += f'\n{k}={v}'
text=re.sub(r'^DATABASE_URL=.*$', 'DATABASE_URL=postgresql://jz:${POSTGRES_PASSWORD}@postgres:5432/jz', text, flags=re.M)
p.write_text(text); p.chmod(0o600)
PY
  ok "Production environment created."
}
configure_domain(){
  local domain="$1"; validate_domain "$domain"
  local host="$domain"; [[ -z "$host" ]] && host="$(get_public_ip)"
  PANEL_ORIGIN="http://$host"
  section "🌐 Panel address"
  echo "Panel URL will be: $PANEL_ORIGIN"
  if [[ "$host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    cat >/etc/nginx/sites-available/jz-panel.conf <<NG
server {
 listen 80 default_server; server_name _; client_max_body_size 200m;
 location / { proxy_pass http://127.0.0.1:5173; proxy_http_version 1.1; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme; }
 location /api/ { proxy_pass http://127.0.0.1:4000/api/; proxy_http_version 1.1; proxy_set_header Host \$host; proxy_set_header X-Forwarded-Proto \$scheme; }
 location /ws/ { proxy_pass http://127.0.0.1:4001/api/ws/; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; }
}
NG
  else
    cat >/etc/nginx/sites-available/jz-panel.conf <<NG
server {
 listen 80; server_name $host; client_max_body_size 200m;
 location / { proxy_pass http://127.0.0.1:5173; proxy_http_version 1.1; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme; }
 location /api/ { proxy_pass http://127.0.0.1:4000/api/; proxy_http_version 1.1; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme; }
 location /ws/ { proxy_pass http://127.0.0.1:4001/api/ws/; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; }
}
NG
  fi
  ln -sfn /etc/nginx/sites-available/jz-panel.conf /etc/nginx/sites-enabled/jz-panel.conf
  rm -f /etc/nginx/sites-enabled/default
  nginx -t >/dev/null; systemctl reload nginx
  printf '%s\n' "$PANEL_ORIGIN" > "$STATE/url"
  ok "Nginx configured for $PANEL_ORIGIN"
}
compose(){
  section "🐳 Building J&Z Panel services"
  cd "$ROOT"
  docker compose config >/dev/null || die "docker-compose.yml is invalid."
  docker compose build --pull --progress plain
  docker compose up -d
  for i in $(seq 1 60); do
    if curl -fsS http://127.0.0.1:4000/api/ready >/dev/null 2>&1; then ok "API is ready"; break; fi
    [[ $i -eq 60 ]] && { docker compose ps; docker compose logs --tail=120 api worker ws web; die "J&Z services did not become ready."; }
    sleep 2
  done
  docker compose ps
}
https(){
  local domain="$1"; [[ "$domain" =~ ^([A-Za-z0-9-]+\.)+[A-Za-z]{2,63}$ ]] || return 0
  read -rp "🔒 Enable Let's Encrypt HTTPS for $domain? [Y/n]: " ans; ans="${ans:-Y}"
  [[ "${ans,,}" == "y" ]] || return 0
  apt-get install -y certbot python3-certbot-nginx
  certbot --nginx -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email --redirect
  PANEL_ORIGIN="https://$domain"; sed -i "s#^WEB_ORIGIN=.*#WEB_ORIGIN=$PANEL_ORIGIN#" "$ROOT/.env"
  ok "HTTPS enabled: $PANEL_ORIGIN"
}
wings(){
  section "🪽 Installing J&Z Wings"
  cd "$ROOT/wings"; go build -o /tmp/jz-wings .; install -Dm755 /tmp/jz-wings /usr/local/bin/jz-wings
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
    local token name address response nodeid secret
    token="$(grep '^JZ_BOOTSTRAP_TOKEN=' "$ROOT/.env" | cut -d= -f2-)"
    name="$WINGS_NODE_NAME"; address="http://127.0.0.1:$WINGS_PORT"
    for i in $(seq 1 60); do curl -fsS http://127.0.0.1:4000/api/ready >/dev/null 2>&1 && break; sleep 2; done
    response="$(curl -fsS -X POST http://127.0.0.1:4000/api/bootstrap/local-node -H 'content-type: application/json' -H "x-jz-bootstrap-token: $token" -d "{\"name\":\"$name\",\"address\":\"$address\",\"location\":\"local\"}")" || die "Panel/Wings bootstrap failed."
    nodeid="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["node"]["id"])' <<<"$response")"
    secret="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["secret"])' <<<"$response")"
    cat >/etc/jz/wings.env <<EOF2
JZ_PANEL_URL=http://127.0.0.1:4000
JZ_NODE_ID=$nodeid
WINGS_SHARED_SECRET=$secret
WINGS_BIND=:$WINGS_PORT
WINGS_SERVERS_ROOT=/var/lib/jz-wings/servers
DOCKER_HOST=unix:///var/run/docker.sock
EOF2
  else
    [[ -n "${EXTERNAL_WINGS_SECRET:-}" ]] || die "Wings-only mode requires a node secret from J&Z Panel."
    cat >/etc/jz/wings.env <<EOF2
JZ_PANEL_URL=$EXISTING_PANEL_URL
JZ_NODE_ID=$EXTERNAL_NODE_ID
WINGS_SHARED_SECRET=$EXTERNAL_WINGS_SECRET
WINGS_BIND=:$WINGS_PORT
WINGS_SERVERS_ROOT=/var/lib/jz-wings/servers
DOCKER_HOST=unix:///var/run/docker.sock
EOF2
  fi
  chmod 600 /etc/jz/wings.env
  systemctl enable --now jz-wings
  sleep 2
  systemctl is-active --quiet jz-wings || { journalctl -u jz-wings -n 80 --no-pager; die "Wings failed to start."; }
  ok "Wings is running on port $WINGS_PORT"
}
firewall(){ section "🛡️ Firewall"; ufw allow OpenSSH; ufw allow 80/tcp; ufw allow 443/tcp; ufw allow "$WINGS_PORT"/tcp; ufw --force enable; ok "Firewall configured."; }
health(){ section "🩺 Final diagnostics"; cd "$ROOT"; docker compose ps; curl -fsS http://127.0.0.1:4000/api/health >/dev/null && ok "API health"; curl -fsS http://127.0.0.1:5173/ >/dev/null && ok "Web UI"; systemctl is-active --quiet jz-wings && ok "Wings service" || warn "Wings not installed"; ss -lnt | grep -q ":$WINGS_PORT " && ok "Wings port $WINGS_PORT" || true; }
uninstall(){ section "🗑️ Uninstall"; read -rp "Remove J&Z containers, database volume, Nginx config and Wings? [y/N]: " a; [[ "${a,,}" == y ]] || return; cd "$ROOT"; docker compose down -v --remove-orphans || true; systemctl disable --now jz-wings 2>/dev/null || true; rm -f /etc/systemd/system/jz-wings.service /usr/local/bin/jz-wings /etc/jz/wings.env; systemctl daemon-reload; rm -f /etc/nginx/sites-enabled/jz-panel.conf /etc/nginx/sites-available/jz-panel.conf; systemctl reload nginx || true; rm -rf "$STATE"; ok "J&Z services removed; Docker itself was left installed."; }
repair(){ section "🛠️ Repair"; apt; [[ -f "$ROOT/.env" ]] || cp "$ROOT/.env.example" "$ROOT/.env"; cd "$ROOT"; docker compose down --remove-orphans || true; docker compose build --pull; docker compose up -d; health; }
update(){ section "🔄 Update"; cd "$ROOT"; git pull --ff-only || warn "Not a git checkout; continuing with local files."; docker compose build --pull; docker compose up -d; health; }
banner(){ clear 2>/dev/null || true; echo -e "${ORANGE}       ██╗ █████╗ ███╗   ██╗███████╗\n       ██║██╔══██╗████╗  ██║╚══███╔╝\n       ██║███████║██╔██╗ ██║  ███╔╝\n  ██   ██║██╔══██║██║╚██╗██║ ███╔╝\n  ╚█████╔╝██║  ██║██║ ╚████║███████╗\n   ╚════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝${RESET}\n                    ${WHITE}J&Z PANEL${RESET}\n"; }
install(){
  section "🚀 J&Z Panel Installation"
  MODE="$1"
  if [[ "$MODE" != "wings" ]]; then
    read -rp "🌐 Panel domain (example: panel.example.com, blank = VPS IP): " PANEL_DOMAIN
    validate_domain "$PANEL_DOMAIN"
    if [[ -n "$PANEL_DOMAIN" ]]; then PANEL_HOST="$PANEL_DOMAIN"; else PANEL_HOST="$(get_public_ip)"; fi
    PANEL_ORIGIN="http://$PANEL_HOST"
    read -rp "👤 Admin username [admin]: " ADMIN_USERNAME; ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
    read -rp "📧 Admin email: " ADMIN_EMAIL
    [[ "$ADMIN_EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || die "Valid admin email required."
    while :; do read -rsp "🔑 Admin password (12+ chars): " ADMIN_PASSWORD; echo; [[ ${#ADMIN_PASSWORD} -ge 12 ]] && break; warn "Password must be at least 12 characters."; done
    configure_domain "$PANEL_DOMAIN"
    WINGS_PORT=8080; WINGS_NODE_NAME="Local-01"
    https "$PANEL_DOMAIN"
    write_env
    compose
  fi
  if [[ "$MODE" == "combo" ]]; then wings; firewall; else health; fi
  section "🎉 Installation complete"
  echo -e "${WHITE}Panel: ${CYAN}${PANEL_ORIGIN}${RESET}"
  [[ "$MODE" == "combo" ]] && echo -e "${WHITE}Wings: ${CYAN}port $WINGS_PORT${RESET}"
  echo -e "${WHITE}Admin: ${CYAN}$ADMIN_EMAIL${RESET}"
  echo -e "${CYAN}📋 Log: $LOG${RESET}"
}
main(){ root; os; banner; echo "1) 🟧 Panel + 🪽 Wings"; echo "2) 🟧 Panel"; echo "3) 🪽 Wings"; echo "4) 🛠️ Repair"; echo "5) 🔄 Update"; echo "6) 🩺 Diagnostics"; echo "7) 🗑️ Uninstall"; echo "8) Exit"; read -rp "Select an option: " c; case "$c" in 1) apt; install combo;; 2) apt; install panel;; 3) apt; MODE=wings; read -rp "🌐 Existing Panel URL (example: https://panel.example.com): " EXISTING_PANEL_URL; read -rp "🆔 Node ID: " EXTERNAL_NODE_ID; read -rsp "🔐 Node secret: " EXTERNAL_WINGS_SECRET; echo; WINGS_PORT=8080; wings; firewall; health;; 4) repair;; 5) update;; 6) health;; 7) uninstall;; 8) exit 0;; *) die "Invalid option.";; esac; }
main "$@"
