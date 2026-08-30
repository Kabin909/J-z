#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# J&Z Panel unified installer / updater / repair utility.
# Safe-by-default: destructive actions require explicit confirmation.

JZ_VERSION="1.0.0"
PANEL_DIR="${JZ_PANEL_DIR:-/var/www/jz-panel}"
WINGS_BIN="/usr/local/bin/jz-wings"
WINGS_CONF_DIR="/etc/pterodactyl" # Compatibility path expected by Wings/Pterodactyl node configuration.
WINGS_SERVICE="jz-wings.service"
QUEUE_SERVICE="jz-panel-queue.service"
NGINX_SITE="jz-panel.conf"
SOURCE_URL="${JZ_PANEL_SOURCE_URL:-}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/jz-panel-installer.log"

ORANGE='\033[38;5;208m'
WHITE='\033[97m'
GREEN='\033[92m'
RED='\033[91m'
BLUE='\033[94m'
YELLOW='\033[93m'
MAGENTA='\033[95m'
CYAN='\033[96m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
exec > >(tee -a "$LOG_FILE") 2>&1

trap 'echo -e "\n${RED}✖ J&Z installer stopped unexpectedly.${RESET}"; echo -e "${DIM}Log: ${LOG_FILE}${RESET}"' ERR

say() { echo -e "$*"; }
ok() { say "${GREEN}✔${RESET} $*"; }
warn() { say "${YELLOW}⚠${RESET} $*"; }
die() { say "${RED}✖${RESET} $*"; exit 1; }
step() { say "\n${CYAN}➜${RESET} ${BOLD}$*${RESET}"; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run this installer as root: sudo bash install.sh"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

confirm() {
  local prompt="${1:-Continue?}"
  local answer
  read -r -p "${prompt} [y/N]: " answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

random_secret() {
  if command_exists openssl; then
    openssl rand -hex 20
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
  fi
}

banner() {
  clear || true
  say ""
  say "${ORANGE}${BOLD}        ██╗${RESET}${WHITE}${BOLD} & ${RESET}${ORANGE}${BOLD}███████╗${RESET}"
  say "${WHITE}${BOLD}        J&Z PANEL${RESET}"
  say "${DIM}        Advanced Hosting Control Panel + Wings Manager${RESET}"
  say ""
  say "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  say "${DIM}Version ${JZ_VERSION} • Installer log: ${LOG_FILE}${RESET}"
  say "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  say ""
}

menu() {
  banner
  say "${GREEN}1)${RESET} 🖥️  Install J&Z Panel"
  say "${RED}2)${RESET} 🪽 Install J&Z Wings"
  say "${BLUE}3)${RESET} 🗑️  Uninstall J&Z Panel"
  say "${YELLOW}4)${RESET} 🗑️  Uninstall J&Z Wings"
  say "${MAGENTA}5)${RESET} 🔄 Update J&Z Panel"
  say "${CYAN}6)${RESET} 🔄 Update J&Z Wings"
  say "${GREEN}7)${RESET} 🛠️  Repair J&Z Panel"
  say "${RED}8)${RESET} 🛠️  Repair J&Z Wings"
  say "${BLUE}9)${RESET} 📦 Install/Upload Panel Source from URL"
  say "${WHITE}0)${RESET} 🚪 Exit"
  say ""
  read -r -p "Choose an option [0-9]: " choice
  case "$choice" in
    1) install_panel ;;
    2) install_wings ;;
    3) uninstall_panel ;;
    4) uninstall_wings ;;
    5) update_panel ;;
    6) update_wings ;;
    7) repair_panel ;;
    8) repair_wings ;;
    9) source_upload_install ;;
    0) say "${GREEN}Goodbye 👋${RESET}"; exit 0 ;;
    *) warn "Invalid option."; sleep 1 ;;
  esac
}

wait_key() { read -r -p $'\nPress Enter to return to the menu...' _; }

check_os() {
  [[ -r /etc/os-release ]] || die "Cannot detect Linux distribution."
  # shellcheck disable=SC1091
  source /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) ;;
    *) die "Supported systems: Ubuntu or Debian. Detected: ${ID:-unknown}." ;;
  esac
  local major="${VERSION_ID%%.*}"
  if [[ "$ID" == "debian" && "$major" -lt 12 ]]; then die "Debian 12+ is required."; fi
  if [[ "$ID" == "ubuntu" && "$major" -lt 22 ]]; then die "Ubuntu 22.04+ is required."; fi
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

install_php() {
  if ! command_exists php; then
    step "Installing PHP and required extensions"
    if [[ "${ID}" == "ubuntu" ]]; then
      apt_install software-properties-common ca-certificates lsb-release apt-transport-https
      local major="${VERSION_ID%%.*}"
      if [[ "$major" -lt 24 ]]; then
        apt_install gnupg2
        add-apt-repository -y ppa:ondrej/php
        apt-get update -y
      fi
    fi
    apt_install php php-cli php-fpm php-gd php-mbstring php-bcmath php-xml php-curl php-zip php-intl php-mysql php-sqlite3 php-tokenizer php-opcache php-redis unzip git curl
  else
    ok "PHP detected: $(php -r 'echo PHP_VERSION;')"
  fi
}

install_node_yarn() {
  if ! command_exists node; then
    step "Installing Node.js 20"
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt_install nodejs
  fi
  if ! command_exists corepack; then
    npm install -g corepack
  fi
  corepack enable >/dev/null 2>&1 || true
  if ! command_exists yarn; then
    corepack prepare yarn@1.22.22 --activate
  fi
  ok "Node $(node --version), Yarn $(yarn --version)"
}

install_composer() {
  if command_exists composer; then
    ok "Composer $(composer --version | head -1)"
    return
  fi
  step "Installing Composer"
  local installer
  installer="$(mktemp)"
  curl -fsSL https://getcomposer.org/installer -o "$installer"
  php "$installer" --install-dir=/usr/local/bin --filename=composer
  rm -f "$installer"
  ok "Composer installed"
}

install_base_dependencies() {
  step "Installing system dependencies"
  apt_install ca-certificates curl wget unzip git tar rsync nginx mariadb-server redis-server cron supervisor openssl
  systemctl enable --now nginx mariadb redis-server cron
  install_php
  install_node_yarn
  install_composer
}

sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}

mysql_exec() {
  local sql="$1"
  if mysql -uroot -e 'SELECT 1' >/dev/null 2>&1; then
    mysql -uroot -e "$sql"
  else
    local rootpw
    read -r -s -p "MariaDB root password: " rootpw
    echo
    mysql -uroot -p"$rootpw" -e "$sql"
  fi
}

setup_database() {
  step "Creating J&Z database"
  local db_name db_user db_pass
  read -r -p "Database name [jz_panel]: " db_name
  db_name="${db_name:-jz_panel}"
  read -r -p "Database user [jz_panel]: " db_user
  db_user="${db_user:-jz_panel}"
  read -r -s -p "Database password [auto-generate if blank]: " db_pass
  echo
  db_pass="${db_pass:-$(random_secret)}"

  [[ "$db_name" =~ ^[A-Za-z0-9_]+$ ]] || die "Invalid database name."
  [[ "$db_user" =~ ^[A-Za-z0-9_]+$ ]] || die "Invalid database user."

  local sql_pass
  sql_pass="$(sql_quote "$db_pass")"
  mysql_exec "CREATE DATABASE IF NOT EXISTS \\`$db_name\\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; CREATE USER IF NOT EXISTS '$db_user'@'127.0.0.1' IDENTIFIED BY '$sql_pass'; ALTER USER '$db_user'@'127.0.0.1' IDENTIFIED BY '$sql_pass'; GRANT ALL PRIVILEGES ON \\`$db_name\\`.* TO '$db_user'@'127.0.0.1'; FLUSH PRIVILEGES;"

  DB_NAME="$db_name" DB_USER="$db_user" DB_PASS="$db_pass"
}

resolve_source() {
  if [[ -n "$SOURCE_URL" ]]; then
    local tmp found
    tmp="$(mktemp -d)"
    step "Downloading J&Z Panel source"
    curl -fL --retry 3 --retry-delay 2 "$SOURCE_URL" -o "$tmp/source.zip"
    unzip -q "$tmp/source.zip" -d "$tmp/source"
    found="$(find "$tmp/source" -mindepth 1 -maxdepth 3 -type f -name composer.json -print -quit | xargs -r dirname)"
    [[ -n "$found" ]] || die "Downloaded archive does not contain a valid panel source."
    echo "$found"
    return
  fi
  if [[ -f "$SOURCE_DIR/composer.json" && -f "$SOURCE_DIR/package.json" ]]; then
    echo "$SOURCE_DIR"
    return
  fi
  [[ -n "$SOURCE_URL" ]] || die "Panel source not found. Run from the extracted J&Z source or set JZ_PANEL_SOURCE_URL."
  local tmp
  tmp="$(mktemp -d)"
  step "Downloading J&Z Panel source"
  curl -fL --retry 3 --retry-delay 2 "$SOURCE_URL" -o "$tmp/source.zip"
  unzip -q "$tmp/source.zip" -d "$tmp/source"
  local found
  found="$(find "$tmp/source" -mindepth 1 -maxdepth 2 -type f -name composer.json -print -quit | xargs -r dirname)"
  [[ -n "$found" ]] || die "Downloaded archive does not contain a valid panel source."
  echo "$found"
}

write_env() {
  local url="$1" db_name="$2" db_user="$3" db_pass="$4"
  cd "$PANEL_DIR"
  if [[ ! -f .env ]]; then cp .env.example .env; fi
  php artisan key:generate --force >/dev/null
  php artisan p:environment:setup --author="noreply@${url#*://}" --url="$url" --timezone="UTC" --cache=redis --session=redis --queue=redis --redis-host=127.0.0.1 --redis-port=6379 --redis-pass="" --settings-ui=true --telemetry=false >/dev/null
  sed -i "s|^APP_NAME=.*|APP_NAME=\"J&Z Panel\"|" .env || true
  sed -i "s|^APP_URL=.*|APP_URL=${url}|" .env || true
  sed -i "s|^DB_HOST=.*|DB_HOST=127.0.0.1|" .env || true
  sed -i "s|^DB_PORT=.*|DB_PORT=3306|" .env || true
  sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${db_name}|" .env || true
  sed -i "s|^DB_USERNAME=.*|DB_USERNAME=${db_user}|" .env || true
  sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${db_pass}|" .env || true
  sed -i "s|^CACHE_DRIVER=.*|CACHE_DRIVER=redis|" .env || true
  sed -i "s|^SESSION_DRIVER=.*|SESSION_DRIVER=redis|" .env || true
  sed -i "s|^QUEUE_CONNECTION=.*|QUEUE_CONNECTION=redis|" .env || true
  sed -i "s|^APP_DEBUG=.*|APP_DEBUG=false|" .env || true
}

install_assets() {
  cd "$PANEL_DIR"
  step "Installing PHP and frontend dependencies"
  composer install --no-dev --optimize-autoloader --no-interaction
  yarn install --frozen-lockfile
  yarn build:production
  php artisan storage:link >/dev/null 2>&1 || true
  chmod -R 755 storage bootstrap/cache
}

write_nginx() {
  local domain="$1"
  local php_sock
  php_sock="$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' | sort -V | tail -1)"
  [[ -S "$php_sock" ]] || die "PHP-FPM socket not found."
  cat > "/etc/nginx/sites-available/$NGINX_SITE" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};
    root ${PANEL_DIR}/public;
    index index.php;

    client_max_body_size 100m;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${php_sock};
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
NGINX
  ln -sfn "/etc/nginx/sites-available/$NGINX_SITE" "/etc/nginx/sites-enabled/$NGINX_SITE"
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl reload nginx
}

write_queue_service() {
  cat > "/etc/systemd/system/$QUEUE_SERVICE" <<SERVICE
[Unit]
Description=J&Z Panel Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
RestartSec=5
WorkingDirectory=${PANEL_DIR}
ExecStart=/usr/bin/php ${PANEL_DIR}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3 --timeout=90

[Install]
WantedBy=multi-user.target
SERVICE
  systemctl daemon-reload
  systemctl enable --now "$QUEUE_SERVICE"
  cat > /etc/cron.d/jz-panel <<CRON
* * * * * www-data cd ${PANEL_DIR} && /usr/bin/php artisan schedule:run >> /dev/null 2>&1
CRON
  chmod 644 /etc/cron.d/jz-panel
}

create_admin() {
  cd "$PANEL_DIR"
  if php artisan list | grep -q 'p:user:make'; then
    step "Create administrator account"
    php artisan p:user:make
  else
    warn "Admin creation command is unavailable; run 'php artisan p:user:make' after installation."
  fi
}

install_panel() {
  require_root; check_os
  step "Starting J&Z Panel installation"
  install_base_dependencies
  local source domain url
  source="$(resolve_source)"
  read -r -p "Panel domain (example.com): " domain
  [[ -n "$domain" ]] || die "Domain is required."
  url="https://${domain}"
  if [[ "$domain" == localhost || "$domain" == 127.0.0.1 ]]; then url="http://${domain}"; fi

  setup_database
  DB_NAME="$DB_NAME" DB_USER="$DB_USER" DB_PASS="$DB_PASS"

  step "Copying J&Z Panel source to ${PANEL_DIR}"
  mkdir -p "$PANEL_DIR"
  if [[ -f "$PANEL_DIR/.env" ]]; then cp "$PANEL_DIR/.env" "/tmp/jz-env-backup"; fi
  rsync -a --delete --exclude='.env' --exclude='storage/*' "$source/" "$PANEL_DIR/"
  if [[ -f /tmp/jz-env-backup ]]; then cp /tmp/jz-env-backup "$PANEL_DIR/.env"; rm -f /tmp/jz-env-backup; fi
  chown -R www-data:www-data "$PANEL_DIR"

  write_env "$url" "$DB_NAME" "$DB_USER" "$DB_PASS"
  cd "$PANEL_DIR"
  step "Running database migrations"
  php artisan migrate --seed --force
  install_assets
  write_nginx "$domain"
  write_queue_service
  chown -R www-data:www-data storage bootstrap/cache public/assets 2>/dev/null || true
  create_admin
  ok "J&Z Panel installation completed."
  say "${GREEN}Open: ${WHITE}${url}${RESET}"
}

install_docker() {
  if command_exists docker; then
    ok "Docker detected: $(docker --version)"
    systemctl enable --now docker
    return
  fi
  step "Installing Docker Engine"
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
}

wings_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) die "Unsupported CPU architecture: $(uname -m)" ;;
  esac
}

install_wings() {
  require_root; check_os
  install_docker
  apt_install curl ca-certificates tar
  local arch url
  arch="$(wings_arch)"
  url="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${arch}"
  step "Downloading J&Z Wings-compatible daemon"
  mkdir -p "$WINGS_CONF_DIR"
  curl -fL --retry 3 --retry-delay 2 "$url" -o "$WINGS_BIN.new"
  chmod 755 "$WINGS_BIN.new"
  mv "$WINGS_BIN.new" "$WINGS_BIN"
  cat > "/etc/systemd/system/$WINGS_SERVICE" <<SERVICE
[Unit]
Description=J&Z Wings Server Control Plane
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=${WINGS_CONF_DIR}
LimitNOFILE=4096
ExecStart=${WINGS_BIN}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE
  systemctl daemon-reload
  systemctl enable "$WINGS_SERVICE"
  if [[ -f "${WINGS_CONF_DIR}/config.yml" ]]; then
    systemctl restart "$WINGS_SERVICE" || warn "Wings could not start; configure the node first."
  fi
  ok "J&Z Wings installed. Configure the node in the J&Z Panel, then start Wings."
}

uninstall_panel() {
  require_root
  warn "This removes the J&Z Panel application, web config, queue worker and cron entry. Database/server data are NOT removed automatically."
  confirm "Uninstall J&Z Panel?" || return
  systemctl disable --now "$QUEUE_SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/$QUEUE_SERVICE" /etc/cron.d/jz-panel
  rm -f "/etc/nginx/sites-enabled/$NGINX_SITE" "/etc/nginx/sites-available/$NGINX_SITE"
  systemctl daemon-reload
  nginx -t && systemctl reload nginx || true
  if [[ -d "$PANEL_DIR" ]]; then
    mv "$PANEL_DIR" "${PANEL_DIR}.removed.$(date +%Y%m%d%H%M%S)"
  fi
  ok "Panel removed. A timestamped backup directory was retained."
}

uninstall_wings() {
  require_root
  warn "This removes the Wings binary and service. Existing server volumes/configuration are retained."
  confirm "Uninstall J&Z Wings?" || return
  systemctl disable --now "$WINGS_SERVICE" 2>/dev/null || true
  rm -f "/etc/systemd/system/$WINGS_SERVICE" "$WINGS_BIN"
  systemctl daemon-reload
  ok "Wings removed. Docker and /etc/pterodactyl were retained."
}

update_panel() {
  require_root
  [[ -d "$PANEL_DIR" ]] || die "J&Z Panel is not installed at $PANEL_DIR."
  step "Updating J&Z Panel"
  local source
  source="$(resolve_source)"
  php artisan down || true
  cp "$PANEL_DIR/.env" /tmp/jz-env-backup
  rsync -a --delete --exclude='.env' --exclude='storage/*' "$source/" "$PANEL_DIR/"
  cp /tmp/jz-env-backup "$PANEL_DIR/.env"
  cd "$PANEL_DIR"
  composer install --no-dev --optimize-autoloader --no-interaction
  yarn install --frozen-lockfile
  yarn build:production
  php artisan migrate --force
  php artisan optimize:clear
  php artisan config:cache
  php artisan view:cache
  php artisan route:cache
  chown -R www-data:www-data "$PANEL_DIR"
  php artisan up || true
  systemctl restart "$QUEUE_SERVICE" || true
  ok "J&Z Panel updated."
}

update_wings() {
  require_root
  step "Updating J&Z Wings"
  local arch url
  arch="$(wings_arch)"
  url="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${arch}"
  curl -fL --retry 3 --retry-delay 2 "$url" -o "$WINGS_BIN.new"
  chmod 755 "$WINGS_BIN.new"
  systemctl stop "$WINGS_SERVICE" 2>/dev/null || true
  mv "$WINGS_BIN.new" "$WINGS_BIN"
  systemctl daemon-reload
  systemctl enable "$WINGS_SERVICE"
  [[ -f "${WINGS_CONF_DIR}/config.yml" ]] && systemctl start "$WINGS_SERVICE" || true
  ok "J&Z Wings updated."
}

repair_panel() {
  require_root
  [[ -d "$PANEL_DIR" ]] || die "J&Z Panel is not installed at $PANEL_DIR."
  step "Repairing J&Z Panel"
  cd "$PANEL_DIR"
  composer install --no-dev --optimize-autoloader --no-interaction
  yarn install --frozen-lockfile
  yarn build:production
  php artisan storage:link >/dev/null 2>&1 || true
  php artisan optimize:clear
  php artisan config:cache
  php artisan view:cache
  php artisan route:cache
  chmod -R 755 storage bootstrap/cache
  chown -R www-data:www-data "$PANEL_DIR"
  nginx -t && systemctl reload nginx
  systemctl restart "$QUEUE_SERVICE" 2>/dev/null || true
  ok "J&Z Panel repair completed."
}

repair_wings() {
  require_root
  step "Repairing J&Z Wings"
  [[ -x "$WINGS_BIN" ]] || install_wings
  systemctl daemon-reload
  systemctl enable "$WINGS_SERVICE"
  if [[ -f "${WINGS_CONF_DIR}/config.yml" ]]; then
    systemctl restart "$WINGS_SERVICE" || true
  fi
  systemctl status "$WINGS_SERVICE" --no-pager || true
  ok "J&Z Wings repair completed."
}

source_upload_install() {
  require_root
  step "Panel source upload / URL installer"
  say "You can provide a public ZIP URL containing the J&Z Panel source."
  say "Example: https://example.com/JZ-Panel.zip"
  read -r -p "Source ZIP URL: " SOURCE_URL
  [[ -n "$SOURCE_URL" ]] || die "Source URL is required."
  install_panel
}

main() {
  require_root
  check_os
  while true; do menu; done
}

if [[ "${1:-}" == "--install-panel" ]]; then install_panel; exit $?; fi
if [[ "${1:-}" == "--install-wings" ]]; then install_wings; exit $?; fi
if [[ "${1:-}" == "--update-panel" ]]; then update_panel; exit $?; fi
if [[ "${1:-}" == "--update-wings" ]]; then update_wings; exit $?; fi
if [[ "${1:-}" == "--repair-panel" ]]; then repair_panel; exit $?; fi
if [[ "${1:-}" == "--repair-wings" ]]; then repair_wings; exit $?; fi
if [[ "${1:-}" == "--uninstall-panel" ]]; then uninstall_panel; exit $?; fi
if [[ "${1:-}" == "--uninstall-wings" ]]; then uninstall_wings; exit $?; fi
if [[ "${1:-}" == "--source-url" ]]; then SOURCE_URL="${2:-}"; [[ -n "$SOURCE_URL" ]] || die "--source-url requires a URL"; install_panel; exit $?; fi

main
