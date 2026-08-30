#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
VERSION="0.7.0"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_URL="${JZ_REPO_URL:-https://github.com/Kabin909/J-ZPanel.git}"
STATE=/etc/jz-panel
# The public one-line installer is often downloaded to /tmp. In that case,
# bootstrap a complete working checkout before doing any local build steps.
if [[ ! -f "$ROOT/package.json" || ! -d "$ROOT/apps" ]]; then
  BOOTSTRAP_DIR="/opt/jz-panel"
  mkdir -p "$BOOTSTRAP_DIR"
  if [[ ! -f "$BOOTSTRAP_DIR/package.json" ]]; then
    tmp="$(mktemp -d)"
    curl -fsSL "${JZ_REPO_ARCHIVE_URL:-https://github.com/Kabin909/J-ZPanel/archive/refs/heads/main.tar.gz}" -o "$tmp/jz.tar.gz"
    tar -xzf "$tmp/jz.tar.gz" -C "$tmp"
    src="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"
    cp -a "$src"/. "$BOOTSTRAP_DIR"/
    rm -rf "$tmp"
  fi
  exec bash "$BOOTSTRAP_DIR/installer/install.sh" "$@"
fi
LOG=/var/log/jz-panel-install.log
ORANGE='\033[38;5;208m'; WHITE='\033[97m'; GREEN='\033[92m'; RED='\033[91m'; CYAN='\033[96m'; RESET='\033[0m'
mkdir -p "$STATE"; touch "$LOG"; chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1
trap 'rc=$?; echo -e "${RED}❌ Failed at line ${LINENO} (exit ${rc}).${RESET}"; echo "Log: $LOG"' ERR
ok(){ echo -e "${GREEN}✅ $*${RESET}"; }; warn(){ echo -e "${ORANGE}⚠️  $*${RESET}"; }; die(){ echo -e "${RED}❌ $*${RESET}"; exit 1; }; section(){ echo -e "\n${ORANGE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n${WHITE}$*${RESET}"; }
root(){ [[ $EUID -eq 0 ]] || die "Run as root or with sudo."; }
os(){ . /etc/os-release; case "$ID" in debian|ubuntu) ;; *) die "Supported: Debian/Ubuntu.";; esac; ok "System: $PRETTY_NAME / $(dpkg --print-architecture)"; }
apt(){ export DEBIAN_FRONTEND=noninteractive; apt-get update -y; apt-get install -y ca-certificates curl git jq openssl python3 nginx ufw docker.io || true; apt-get install -y docker-compose-plugin 2>/dev/null || apt-get install -y docker-compose-v2 2>/dev/null || true; command -v docker >/dev/null || die "Docker installation failed."; docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required. Install docker-compose-plugin/docker-compose-v2."; systemctl enable --now docker nginx; }
secrets(){ [[ -f "$ROOT/.env" ]] || cp "$ROOT/.env.example" "$ROOT/.env"; python3 - "$ROOT/.env" <<'PY'
from pathlib import Path
import secrets,re,sys
p=Path(sys.argv[1]); text=p.read_text(); keys=['POSTGRES_PASSWORD','JWT_SECRET','COOKIE_SECRET','WINGS_SHARED_SECRET','NODE_ENCRYPTION_KEY','JZ_BOOTSTRAP_TOKEN']
for k in keys:
    v=secrets.token_urlsafe(32)
    text=re.sub(rf'^{k}=.*$',f'{k}={v}',text,flags=re.M)
    if not re.search(rf'^{k}=',text,re.M): text += f'\n{k}={v}\n'
text=re.sub(r'^DATABASE_URL=.*$',lambda m:'DATABASE_URL=postgresql://jz:${POSTGRES_PASSWORD}@postgres:5432/jz',text,flags=re.M)
p.write_text(text); p.chmod(0o600)
PY
}
compose(){ section "🚀 Starting J&Z services"; cd "$ROOT"; docker compose up -d --build; docker compose ps; }
web(){ local domain="$1"; [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || die "Invalid domain."; section "🌐 Configuring domain $domain"; cat >/etc/nginx/sites-available/jz-panel.conf <<NG
server { listen 80; server_name $domain; client_max_body_size 200m;
 location / { proxy_pass http://127.0.0.1:5173; proxy_http_version 1.1; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme; }
 location /api/ { proxy_pass http://127.0.0.1:4000/api/; proxy_http_version 1.1; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme; }
 location /ws/ { proxy_pass http://127.0.0.1:4001/; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host \$host; }
}
NG
ln -sfn /etc/nginx/sites-available/jz-panel.conf /etc/nginx/sites-enabled/jz-panel.conf; rm -f /etc/nginx/sites-enabled/default; nginx -t; systemctl reload nginx; printf '%s\n' "$domain" >"$STATE/domain"; ok "Domain proxy ready: http://$domain"; }
ssl(){ local domain="$1"; read -rp "🔐 Enable Let's Encrypt HTTPS for $domain? [y/N]: " a; [[ ${a,,} == y ]] || return; apt-get install -y certbot python3-certbot-nginx; certbot --nginx -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email --redirect || warn "Certificate issuance failed; HTTP remains available."; }
wings(){ section "🪽 Building and configuring J&Z Wings"; command -v go >/dev/null || apt-get install -y golang-go; cd "$ROOT/wings"; go build -o jz-wings .; install -Dm755 jz-wings /usr/local/bin/jz-wings; mkdir -p /etc/jz /var/lib/jz-wings; cat >/etc/systemd/system/jz-wings.service <<'UNIT'
[Unit]
Description=J&Z Wings
After=docker.service network-online.target
Requires=docker.service
[Service]
EnvironmentFile=/etc/jz/wings.env
ExecStart=/usr/local/bin/jz-wings
Restart=always
RestartSec=3
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
# Local bootstrap is supported by the bundled API.
TOKEN=$(grep '^JZ_BOOTSTRAP_TOKEN=' "$ROOT/.env" | cut -d= -f2-)
for i in $(seq 1 40); do curl -fsS http://127.0.0.1:4000/api/ready >/dev/null && break || sleep 2; done
NODE_NAME="${JZ_NODE_NAME:-Local-01}"; NODE_ADDRESS="${JZ_NODE_ADDRESS:-http://127.0.0.1:8080}"
read -rp "🪽 Wings public API address [$NODE_ADDRESS]: " entered_address; NODE_ADDRESS="${entered_address:-$NODE_ADDRESS}"
R=$(curl -fsS -X POST http://127.0.0.1:4000/api/bootstrap/local-node -H 'content-type: application/json' -H "x-jz-bootstrap-token: $TOKEN" -d "{\"name\":\"$NODE_NAME\",\"address\":\"$NODE_ADDRESS\",\"location\":\"local\"}") || die "Panel node bootstrap failed. Check $LOG"
NODE_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["node"]["id"])' <<<"$R"); SECRET=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["secret"])' <<<"$R")
cat >/etc/jz/wings.env <<EOF2
JZ_PANEL_URL=http://127.0.0.1:4000
JZ_NODE_ID=$NODE_ID
WINGS_SHARED_SECRET=$SECRET
WINGS_BIND=:8080
DOCKER_HOST=unix:///var/run/docker.sock
EOF2
chmod 600 /etc/jz/wings.env; systemctl enable --now jz-wings; ok "Wings online: $(systemctl is-active jz-wings)"; }
firewall(){ section "🛡️ Firewall"; ufw allow 22/tcp; ufw allow 80/tcp; ufw allow 443/tcp; ufw allow 8080/tcp; ufw allow 2022/tcp; ufw --force enable; ok "Opened SSH/HTTP/HTTPS/Wings ports."; }
health(){ section "🩺 Health"; cd "$ROOT"; docker compose ps; for s in docker nginx jz-wings; do if systemctl is-active --quiet "$s"; then ok "$s"; else warn "$s is not active"; fi; done; for p in 80 443 4000 4001 8080; do ss -lnt | grep -qE "[:.]$p[[:space:]]" && ok "Port $p listening" || true; done; }
uninstall(){ section "🗑️ Uninstall"; read -rp "Remove J&Z containers, images, project data and Wings? [y/N]: " a; [[ ${a,,} == y ]] || return; cd "$ROOT"; docker compose down -v --remove-orphans || true; systemctl disable --now jz-wings 2>/dev/null || true; rm -f /etc/systemd/system/jz-wings.service /usr/local/bin/jz-wings; systemctl daemon-reload; rm -rf /etc/jz "$STATE"; rm -f /etc/nginx/sites-enabled/jz-panel.conf /etc/nginx/sites-available/jz-panel.conf; systemctl reload nginx || true; ok "J&Z application services removed. Docker itself was left installed."; }
repair(){ section "🛠️ Repair"; apt; secrets; compose; [[ -f /etc/jz/wings.env ]] && systemctl restart jz-wings || true; health; }
update(){ section "🔄 Update"; cd "$ROOT"; git pull --ff-only || warn "Not a git checkout; using current files."; secrets; docker compose build --pull; docker compose up -d; health; }
banner(){ clear 2>/dev/null || true; echo -e "${ORANGE}╔════════════════════════════════════════════════════════════╗\n║${WHITE}                     🚀 J&Z PANEL                         ${ORANGE}║\n║${WHITE}             Full Panel + Wings Stack                     ${ORANGE}║\n║${WHITE}                  🟧 Orange / White                        ${ORANGE}║\n╚════════════════════════════════════════════════════════════╝${RESET}"; }
main(){ root; os; banner; echo "1) 🟧 Panel + 🪽 Wings"; echo "2) 🟧 Panel only"; echo "3) 🪽 Wings only"; echo "4) 🛠️ Repair"; echo "5) 🔄 Update"; echo "6) 🩺 Health"; echo "7) 💾 Backup"; echo "8) 🗑️ Uninstall"; echo "9) Exit"; read -rp "Select [1-9]: " c; case "$c" in 6) health;; 7) "$ROOT/installer/jz-panel" backup;; 8) uninstall;; 9) exit 0;; 4) repair;; 5) update;; 1|2|3) apt; secrets; [[ "$c" != 3 ]] && compose; if [[ "$c" != 3 ]]; then read -rp "🌐 Panel domain (example: panel.example.com): " d; web "$d"; ssl "$d"; fi; [[ "$c" != 2 ]] && wings; firewall; health;; *) die "Invalid option.";; esac; }
main "$@"
