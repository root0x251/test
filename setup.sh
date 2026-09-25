#!/usr/bin/env bash
# =============================================================================
#  VPS SETUP SCRIPT
#  Ubuntu 24.04 LTS · Docker · Nginx Proxy Manager · 3x-ui · Hysteria2 · Telemt
#  https://github.com/YOUR_USERNAME/vps-setup
# =============================================================================
set -euo pipefail

# ─── Цвета ───────────────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m';  BOLD='\033[1m';  NC='\033[0m'

log_info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()    { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${NC}"; \
                echo -e "${BOLD}${BLUE}  $*${NC}"; \
                echo -e "${BOLD}${BLUE}══════════════════════════════════════════${NC}\n"; }
log_section() { echo -e "\n${BOLD}${CYAN}── $* ──${NC}\n"; }

die() { log_error "$*"; exit 1; }

# ─── Проверка root ───────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Запусти скрипт от root: sudo bash setup.sh"

# =============================================================================
#  СБОР ДАННЫХ
# =============================================================================
log_step "СБОР ДАННЫХ — введи параметры один раз"

echo -e "${YELLOW}Все данные вводятся сейчас. Скрипт больше не будет спрашивать.${NC}\n"

# ── Имя пользователя ──────────────────────────────────────────────────────────
while true; do
  read -rp "$(echo -e "${BOLD}Имя нового SSH-пользователя:${NC} ")" NEW_USER
  [[ "$NEW_USER" =~ ^[a-z_][a-z0-9_-]{1,31}$ ]] && break
  log_warn "Только строчные буквы, цифры, _ и - (2–32 символа)"
done

# ── Пароль пользователя ───────────────────────────────────────────────────────
while true; do
  read -rsp "$(echo -e "${BOLD}Пароль для $NEW_USER (мин. 16 символов):${NC} ")" USER_PASS; echo
  read -rsp "$(echo -e "${BOLD}Повтори пароль:${NC} ")"                           USER_PASS2; echo
  [[ "$USER_PASS" == "$USER_PASS2" ]] || { log_warn "Пароли не совпадают"; continue; }
  [[ ${#USER_PASS} -ge 16 ]]          || { log_warn "Минимум 16 символов"; continue; }
  break
done

# ── Email (Let's Encrypt) ─────────────────────────────────────────────────────
while true; do
  read -rp "$(echo -e "${BOLD}Email для Let's Encrypt / acme.sh:${NC} ")" LE_EMAIL
  [[ "$LE_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]] && break
  log_warn "Введи корректный email"
done

# ── Основной домен ────────────────────────────────────────────────────────────
while true; do
  read -rp "$(echo -e "${BOLD}Основной домен (например: example.ru):${NC} ")" ROOT_DOMAIN
  [[ "$ROOT_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] && break
  log_warn "Введи корректный домен без http:// и слешей"
done

echo ""
echo -e "${CYAN}Субдомены будут созданы автоматически:${NC}"
echo -e "  ${GREEN}npm.${ROOT_DOMAIN}${NC}      → панель Nginx Proxy Manager"
echo -e "  ${GREEN}cdn.${ROOT_DOMAIN}${NC}      → панель 3x-ui"
echo -e "  ${GREEN}hist.${ROOT_DOMAIN}${NC}     → Hysteria2 (TLS-сертификат)"
echo -e "  ${GREEN}${ROOT_DOMAIN}${NC}          → сайт-заглушка"
echo -e "  ${GREEN}www.${ROOT_DOMAIN}${NC}      → сайт-заглушка"
echo ""
read -rp "$(echo -e "${BOLD}Использовать эти субдомены? (y/n):${NC} ")" SUBDOMAIN_CONFIRM
if [[ "$SUBDOMAIN_CONFIRM" != "y" && "$SUBDOMAIN_CONFIRM" != "Y" ]]; then
  echo ""
  read -rp "$(echo -e "${BOLD}Субдомен для NPM-панели (например: npm.${ROOT_DOMAIN}):${NC} ")"  NPM_DOMAIN
  read -rp "$(echo -e "${BOLD}Субдомен для 3x-ui (например: cdn.${ROOT_DOMAIN}):${NC} ")"       XUI_DOMAIN
  read -rp "$(echo -e "${BOLD}Субдомен для Hysteria2 (например: hist.${ROOT_DOMAIN}):${NC} ")"  H2_DOMAIN
else
  NPM_DOMAIN="npm.${ROOT_DOMAIN}"
  XUI_DOMAIN="cdn.${ROOT_DOMAIN}"
  H2_DOMAIN="hist.${ROOT_DOMAIN}"
fi

# ── IP сервера ────────────────────────────────────────────────────────────────
SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
            curl -s --max-time 5 https://ifconfig.me  2>/dev/null || \
            hostname -I | awk '{print $1}')
echo ""
log_info "Определён IP сервера: ${GREEN}${SERVER_IP}${NC}"
read -rp "$(echo -e "${BOLD}Верно? Или введи IP вручную (Enter = использовать ${SERVER_IP}):${NC} ")" IP_INPUT
[[ -n "$IP_INPUT" ]] && SERVER_IP="$IP_INPUT"

# ── Пароль для 3x-ui ─────────────────────────────────────────────────────────
echo ""
log_section "Параметры 3x-ui"
while true; do
  read -rsp "$(echo -e "${BOLD}Пароль для панели 3x-ui (мин. 16 символов):${NC} ")" XUI_PASS; echo
  read -rsp "$(echo -e "${BOLD}Повтори пароль:${NC} ")"                              XUI_PASS2; echo
  [[ "$XUI_PASS" == "$XUI_PASS2" ]] || { log_warn "Пароли не совпадают"; continue; }
  [[ ${#XUI_PASS} -ge 16 ]]         || { log_warn "Минимум 16 символов"; continue; }
  break
done

# ── Пароль Hysteria2 ──────────────────────────────────────────────────────────
H2_PASS=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
log_info "Пароль Hysteria2 сгенерирован автоматически"

# ── Секрет Telemt ─────────────────────────────────────────────────────────────
TELEMT_SECRET=$(openssl rand -hex 16)
log_info "Секрет Telemt MTProxy сгенерирован автоматически"

# ── Порты VPN ──────────────────────────────────────────────────────────────────
echo ""
log_section "Порты VPN (нажми Enter для значений по умолчанию)"
read -rp "$(echo -e "${BOLD}Порт VLESS-Reality     [8443]:${NC} ")" P_VLESS_REALITY;  P_VLESS_REALITY=${P_VLESS_REALITY:-8443}
read -rp "$(echo -e "${BOLD}Порт VLESS-XHTTP       [8448]:${NC} ")" P_VLESS_XHTTP;    P_VLESS_XHTTP=${P_VLESS_XHTTP:-8448}
read -rp "$(echo -e "${BOLD}Порт Trojan            [8449]:${NC} ")" P_TROJAN;          P_TROJAN=${P_TROJAN:-8449}
read -rp "$(echo -e "${BOLD}Порт Shadowsocks       [8445]:${NC} ")" P_SS;              P_SS=${P_SS:-8445}
read -rp "$(echo -e "${BOLD}Порт Hysteria2 (UDP)   [8444]:${NC} ")" P_H2;              P_H2=${P_H2:-8444}
read -rp "$(echo -e "${BOLD}Порт Telemt MTProxy    [8446]:${NC} ")" P_TELEMT;          P_TELEMT=${P_TELEMT:-8446}

# ── Итоговая сводка ───────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║             СВОДКА ВВЕДЁННЫХ ДАННЫХ                 ║${NC}"
echo -e "${BOLD}${BLUE}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${BLUE}║${NC} Пользователь SSH   : ${GREEN}${NEW_USER}${NC}"
echo -e "${BOLD}${BLUE}║${NC} Email (Let's Enc.) : ${GREEN}${LE_EMAIL}${NC}"
echo -e "${BOLD}${BLUE}║${NC} IP сервера         : ${GREEN}${SERVER_IP}${NC}"
echo -e "${BOLD}${BLUE}║${NC} Корневой домен     : ${GREEN}${ROOT_DOMAIN}${NC}"
echo -e "${BOLD}${BLUE}║${NC} NPM панель         : ${GREEN}https://${NPM_DOMAIN}${NC}"
echo -e "${BOLD}${BLUE}║${NC} 3x-ui панель       : ${GREEN}https://${XUI_DOMAIN}${NC}"
echo -e "${BOLD}${BLUE}║${NC} Hysteria2 домен    : ${GREEN}${H2_DOMAIN}${NC}"
echo -e "${BOLD}${BLUE}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${BLUE}║${NC} Порт SSH           : ${GREEN}3270/tcp${NC}"
echo -e "${BOLD}${BLUE}║${NC} VLESS-Reality      : ${GREEN}${P_VLESS_REALITY}/tcp${NC}"
echo -e "${BOLD}${BLUE}║${NC} VLESS-XHTTP        : ${GREEN}${P_VLESS_XHTTP}/tcp${NC}"
echo -e "${BOLD}${BLUE}║${NC} Trojan             : ${GREEN}${P_TROJAN}/tcp${NC}"
echo -e "${BOLD}${BLUE}║${NC} Shadowsocks        : ${GREEN}${P_SS}/tcp+udp${NC}"
echo -e "${BOLD}${BLUE}║${NC} Hysteria2          : ${GREEN}${P_H2}/udp${NC}"
echo -e "${BOLD}${BLUE}║${NC} Telemt MTProxy     : ${GREEN}${P_TELEMT}/tcp${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
read -rp "$(echo -e "${BOLD}${RED}Всё верно? Продолжить установку? (yes/no):${NC} ")" FINAL_CONFIRM
[[ "$FINAL_CONFIRM" == "yes" ]] || die "Установка отменена"

# =============================================================================
#  ШАБЛОН ПАУЗЫ И ПРОВЕРКИ
# =============================================================================
check_ok() {
  local desc="$1"; local cmd="$2"; local expected="$3"
  local result
  result=$(eval "$cmd" 2>/dev/null || true)
  if echo "$result" | grep -q "$expected"; then
    log_ok "$desc"
  else
    log_warn "$desc — неожиданный результат: $result"
  fi
}

# =============================================================================
#  ШАГ 1 — БАЗОВАЯ НАСТРОЙКА СЕРВЕРА
# =============================================================================
log_step "ШАГ 1 — Базовая настройка сервера"

# ── 1.1 Пользователь ─────────────────────────────────────────────────────────
log_section "1.1 — Создание пользователя ${NEW_USER}"

if id "$NEW_USER" &>/dev/null; then
  log_warn "Пользователь ${NEW_USER} уже существует — пропускаю создание"
else
  useradd -m -s /bin/bash "$NEW_USER"
  echo "${NEW_USER}:${USER_PASS}" | chpasswd
  usermod -aG sudo "$NEW_USER"
  log_ok "Пользователь ${NEW_USER} создан"
fi

# Sudo без пароля (для скрипта; уберём после, если нужно)
echo "${NEW_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"${NEW_USER}"
chmod 440 /etc/sudoers.d/"${NEW_USER}"

check_ok "Пользователь в группе sudo" "id ${NEW_USER}" "sudo"

# ── 1.2 SSH ───────────────────────────────────────────────────────────────────
log_section "1.2 — Настройка SSH (порт 3270)"

cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Применяем параметры через sed (идемпотентно)
configure_ssh() {
  local param="$1"; local value="$2"; local file="/etc/ssh/sshd_config"
  # Если параметр уже есть (закомментирован или нет) — заменяем
  if grep -qE "^#?\s*${param}\s" "$file"; then
    sed -i "s|^#\?\s*${param}\s.*|${param} ${value}|" "$file"
  else
    echo "${param} ${value}" >> "$file"
  fi
}

configure_ssh "Port"                   "3270"
configure_ssh "PermitRootLogin"        "no"
configure_ssh "PasswordAuthentication" "yes"
configure_ssh "PubkeyAuthentication"   "yes"
configure_ssh "MaxAuthTries"           "3"
configure_ssh "LoginGraceTime"         "30"
configure_ssh "AllowUsers"             "${NEW_USER}"
configure_ssh "ClientAliveInterval"    "300"
configure_ssh "ClientAliveCountMax"    "2"
configure_ssh "X11Forwarding"          "no"
configure_ssh "AllowTcpForwarding"     "no"

# Проверка синтаксиса
sshd -t || die "Ошибка синтаксиса sshd_config! Откат..."
systemctl enable ssh
systemctl restart ssh

check_ok "SSH слушает порт 3270" "ss -tlnp" ":3270"
log_ok "SSH настроен. Подключись в НОВОМ терминале: ssh -p 3270 ${NEW_USER}@${SERVER_IP}"
log_warn "НЕ ЗАКРЫВАЙ текущий сеанс до проверки нового подключения!"
echo ""
read -rp "$(echo -e "${BOLD}Открой новый терминал, войди как ${NEW_USER} на порт 3270, потом вернись и нажми Enter:${NC} ")" _

# ── 1.3 ICMP (ping) ──────────────────────────────────────────────────────────
log_section "1.3 — Отключение ICMP (ping)"

# Добавляем в /etc/sysctl.conf если не было
grep -q "net.ipv4.icmp_echo_ignore_all" /etc/sysctl.conf || \
  echo "net.ipv4.icmp_echo_ignore_all = 1" >> /etc/sysctl.conf
grep -q "net.ipv6.icmp.echo_ignore_all" /etc/sysctl.conf || \
  echo "net.ipv6.icmp.echo_ignore_all = 1" >> /etc/sysctl.conf
sysctl -p

log_ok "ICMP отключён (ping не будет отвечать)"

# ── 1.4 Swap ─────────────────────────────────────────────────────────────────
log_section "1.4 — Swap-файл 1 ГБ"

if swapon --show | grep -q /swapfile; then
  log_warn "Swap уже активен — пропускаю"
else
  fallocate -l 1G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  log_ok "Swap 1 ГБ создан"
fi

grep -q "vm.swappiness=10" /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf
sysctl -p
check_ok "Swap активен" "free -h" "Swap"

# ── 1.5 Обновление системы ───────────────────────────────────────────────────
log_section "1.5 — Обновление системы"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -o Dpkg::Options::="--force-confold" -qq
apt-get autoremove -y -qq
apt-get install -y curl wget git htop net-tools ufw fail2ban unzip \
                   python3 openssl unattended-upgrades apt-listchanges -qq

# Автообновления безопасности
dpkg-reconfigure -plow unattended-upgrades <<< $'\n'
log_ok "Система обновлена, базовые утилиты установлены"

# ── 1.6 Часовой пояс ─────────────────────────────────────────────────────────
timedatectl set-timezone Europe/Moscow
log_ok "Часовой пояс: $(timedatectl | grep 'Time zone')"

# ── 1.7 UFW ──────────────────────────────────────────────────────────────────
log_section "1.6 — UFW брандмауэр"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow 3270/tcp              comment 'SSH'
ufw allow 80/tcp                comment 'HTTP → NPM'
ufw allow 81/tcp                comment 'NPM Admin (временно)'
ufw allow 443/tcp               comment 'HTTPS → NPM'
ufw allow "${P_VLESS_REALITY}/tcp"  comment 'VLESS-Reality (3x-ui)'
ufw allow "${P_VLESS_XHTTP}/tcp"    comment 'VLESS-XHTTP (3x-ui)'
ufw allow "${P_TROJAN}/tcp"         comment 'Trojan (3x-ui)'
ufw allow "${P_SS}/tcp"             comment 'Shadowsocks TCP (3x-ui)'
ufw allow "${P_SS}/udp"             comment 'Shadowsocks UDP (3x-ui)'
ufw allow "${P_H2}/udp"             comment 'Hysteria2'
ufw allow "${P_TELEMT}/tcp"         comment 'Telemt MTProxy'

ufw --force enable
check_ok "UFW активен" "ufw status" "Status: active"

# ── 1.8 Fail2Ban ─────────────────────────────────────────────────────────────
log_section "1.7 — Fail2Ban"

tee /etc/fail2ban/jail.local > /dev/null << EOF
[DEFAULT]
bantime  = 5h
findtime = 2m
maxretry = 2
backend  = systemd

[sshd]
enabled = true
port    = 3270
EOF

systemctl enable fail2ban
systemctl restart fail2ban
sleep 2
check_ok "Fail2Ban работает" "fail2ban-client ping" "pong"
log_ok "ШАГ 1 завершён"

# =============================================================================
#  ШАГ 2 — DOCKER
# =============================================================================
log_step "ШАГ 2 — Docker + структура папок + сеть"

# ── 2.1 Установка Docker ─────────────────────────────────────────────────────
log_section "2.1 — Установка Docker"

if command -v docker &>/dev/null; then
  log_warn "Docker уже установлен — пропускаю"
else
  curl -fsSL https://get.docker.com | sh
  log_ok "Docker установлен"
fi

usermod -aG docker "$NEW_USER"
systemctl enable docker
systemctl start docker

check_ok "Docker запущен" "docker version" "Version"

# ── 2.2 Лимиты логов Docker ──────────────────────────────────────────────────
log_section "2.2 — Лимиты логов Docker"

mkdir -p /etc/docker
tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "3"
  }
}
EOF

systemctl restart docker
check_ok "Docker daemon перезапущен" "docker info" "Logging Driver"

# ── 2.3 Структура папок ───────────────────────────────────────────────────────
log_section "2.3 — Структура папок /opt/docker"

mkdir -p /opt/docker/{nginx-proxy-manager/data,nginx-proxy-manager/letsencrypt,\
nginx-site/html,3x-ui/db,3x-ui/cert,telemt,hysteria2/cert}
chown -R "${NEW_USER}:${NEW_USER}" /opt/docker
log_ok "Папки созданы в /opt/docker/"

# ── 2.4 Сеть proxy-net ───────────────────────────────────────────────────────
log_section "2.4 — Docker-сеть proxy-net"

if docker network ls | grep -q proxy-net; then
  log_warn "Сеть proxy-net уже существует — пропускаю"
else
  docker network create --subnet=172.18.0.0/16 proxy-net
  log_ok "Сеть proxy-net создана"
fi

check_ok "Сеть proxy-net существует" "docker network ls" "proxy-net"
log_ok "ШАГ 2 завершён"

# =============================================================================
#  ШАГ 3 — NGINX PROXY MANAGER
# =============================================================================
log_step "ШАГ 3 — Nginx Proxy Manager"

log_section "3.1 — docker-compose.yml для NPM"

tee /opt/docker/nginx-proxy-manager/docker-compose.yml > /dev/null << EOF
services:
  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    volumes:
      - /opt/docker/nginx-proxy-manager/data:/data
      - /opt/docker/nginx-proxy-manager/letsencrypt:/etc/letsencrypt
    deploy:
      resources:
        limits:
          memory: 200M
          cpus: "0.5"
        reservations:
          memory: 64M
    networks:
      - proxy-net

networks:
  proxy-net:
    external: true
EOF

log_section "3.2 — Запуск NPM"

cd /opt/docker/nginx-proxy-manager
docker compose up -d
log_info "Ждём 20 секунд пока NPM инициализируется..."
sleep 20

check_ok "NPM запущен" "docker compose ps" "Up"

echo ""
echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${YELLOW}║  ВАЖНО: РУЧНЫЕ ДЕЙСТВИЯ В NPM                       ║${NC}"
echo -e "${BOLD}${YELLOW}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${YELLOW}║${NC} 1. Открой в браузере: ${CYAN}http://${SERVER_IP}:81${NC}"
echo -e "${BOLD}${YELLOW}║${NC} 2. Войди: admin@example.com / changeme"
echo -e "${BOLD}${YELLOW}║${NC} 3. Смени email на: ${GREEN}${LE_EMAIL}${NC}"
echo -e "${BOLD}${YELLOW}║${NC} 4. Смени пароль на надёжный"
echo -e "${BOLD}${YELLOW}║${NC}"
echo -e "${BOLD}${YELLOW}║${NC} 5. Добавь Proxy Host для ${CYAN}${NPM_DOMAIN}${NC}:"
echo -e "${BOLD}${YELLOW}║${NC}    Forward Hostname: nginx-proxy-manager"
echo -e "${BOLD}${YELLOW}║${NC}    Forward Port:     81"
echo -e "${BOLD}${YELLOW}║${NC}    SSL: Let's Encrypt + Force SSL + HTTP/2"
echo -e "${BOLD}${YELLOW}║${NC}"
echo -e "${BOLD}${YELLOW}║${NC} DNS должна быть настроена ДО этого!"
echo -e "${BOLD}${YELLOW}║${NC} ${ROOT_DOMAIN}     → ${SERVER_IP}"
echo -e "${BOLD}${YELLOW}║${NC} www.${ROOT_DOMAIN} → ${SERVER_IP}"
echo -e "${BOLD}${YELLOW}║${NC} ${NPM_DOMAIN}  → ${SERVER_IP}"
echo -e "${BOLD}${YELLOW}║${NC} ${XUI_DOMAIN}  → ${SERVER_IP}"
echo -e "${BOLD}${YELLOW}║${NC} ${H2_DOMAIN}   → ${SERVER_IP}"
echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
read -rp "$(echo -e "${BOLD}Выполни всё выше, проверь https://${NPM_DOMAIN} — потом нажми Enter:${NC} ")" _

# Закрываем прямой доступ к порту 81
log_section "3.3 — Закрываем прямой доступ к порту 81"

ufw delete allow 81/tcp 2>/dev/null || true
# Переводим на localhost в compose
sed -i 's|- "81:81"|- "127.0.0.1:81:81"|' \
  /opt/docker/nginx-proxy-manager/docker-compose.yml

cd /opt/docker/nginx-proxy-manager
docker compose down && docker compose up -d
sleep 10

check_ok "NPM работает через домен" \
  "curl -s -o /dev/null -w '%{http_code}' https://${NPM_DOMAIN}" "200"

log_ok "ШАГ 3 завершён. Панель NPM: https://${NPM_DOMAIN}"

# =============================================================================
#  ШАГ 4 — NGINX САЙТ-ЗАГЛУШКА
# =============================================================================
log_step "ШАГ 4 — Nginx сайт-заглушка"

# ── HTML страница ─────────────────────────────────────────────────────────────
tee /opt/docker/nginx-site/html/index.html > /dev/null << EOF
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${ROOT_DOMAIN}</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            background: #0f0f0f;
            font-family: 'Courier New', monospace;
            color: #e0e0e0;
        }
        .container { text-align: center; padding: 2rem; }
        .title { font-size: 2.5rem; color: #00ff88; margin-bottom: 1rem; }
        .subtitle { font-size: 1rem; color: #888; margin-bottom: 2rem; }
        .status {
            display: inline-block;
            padding: 0.5rem 1.5rem;
            border: 1px solid #00ff88;
            color: #00ff88;
            font-size: 0.85rem;
            letter-spacing: 2px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="title">${ROOT_DOMAIN}</div>
        <div class="subtitle">site under construction</div>
        <div class="status">[ COMING SOON ]</div>
    </div>
</body>
</html>
EOF

# ── docker-compose.yml ────────────────────────────────────────────────────────
tee /opt/docker/nginx-site/docker-compose.yml > /dev/null << 'EOF'
services:
  nginx-site:
    image: nginx:alpine
    container_name: nginx-site
    restart: unless-stopped
    volumes:
      - /opt/docker/nginx-site/html:/usr/share/nginx/html:ro
    expose:
      - "80"
    deploy:
      resources:
        limits:
          memory: 64M
          cpus: "0.25"
        reservations:
          memory: 16M
    networks:
      - proxy-net

networks:
  proxy-net:
    external: true
EOF

cd /opt/docker/nginx-site
docker compose up -d
sleep 5
check_ok "nginx-site запущен" "docker compose ps" "Up"

echo ""
echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${YELLOW}║  ВАЖНО: ДОБАВЬ PROXY HOST В NPM ДЛЯ САЙТА          ║${NC}"
echo -e "${BOLD}${YELLOW}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${YELLOW}║${NC} В NPM → Hosts → Proxy Hosts → Add:"
echo -e "${BOLD}${YELLOW}║${NC}   Domain Names:     ${CYAN}${ROOT_DOMAIN}${NC} + ${CYAN}www.${ROOT_DOMAIN}${NC}"
echo -e "${BOLD}${YELLOW}║${NC}   Forward Hostname: nginx-site"
echo -e "${BOLD}${YELLOW}║${NC}   Forward Port:     80"
echo -e "${BOLD}${YELLOW}║${NC}   SSL: Let's Encrypt + Force SSL + HTTP/2"
echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
read -rp "$(echo -e "${BOLD}Настрой Proxy Host, проверь https://${ROOT_DOMAIN} — нажми Enter:${NC} ")" _

log_ok "ШАГ 4 завершён. Сайт: https://${ROOT_DOMAIN}"

# =============================================================================
#  ШАГ 5 — 3x-ui (VLESS-Reality, VLESS-XHTTP, Trojan, Shadowsocks)
# =============================================================================
log_step "ШАГ 5 — 3x-ui (панель управления VPN)"

# ── docker-compose.yml ────────────────────────────────────────────────────────
tee /opt/docker/3x-ui/docker-compose.yml > /dev/null << EOF
services:
  3x-ui:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: 3x-ui
    restart: unless-stopped
    environment:
      XRAY_VMESS_AEAD_FORCED: "false"
    ports:
      - "${P_VLESS_REALITY}:${P_VLESS_REALITY}"
      - "${P_VLESS_XHTTP}:${P_VLESS_XHTTP}"
      - "${P_TROJAN}:${P_TROJAN}"
      - "${P_SS}:${P_SS}"
      - "${P_SS}:${P_SS}/udp"
    expose:
      - "2053"
    volumes:
      - /opt/docker/3x-ui/db:/etc/x-ui
      - /opt/docker/3x-ui/cert:/root/cert
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: "0.5"
        reservations:
          memory: 64M
    networks:
      - proxy-net

networks:
  proxy-net:
    external: true
EOF

# ── Запуск ────────────────────────────────────────────────────────────────────
cd /opt/docker/3x-ui
docker compose pull
docker compose up -d
log_info "Ждём 15 секунд..."
sleep 15

check_ok "3x-ui запущен" "docker compose ps" "Up"

# ── Смена пароля через API ────────────────────────────────────────────────────
log_section "5.1 — Смена учётных данных 3x-ui"
log_info "Меняем логин/пароль через CLI внутри контейнера..."

docker exec 3x-ui x-ui setting -username "${NEW_USER}" -password "${XUI_PASS}" || \
  log_warn "Не удалось сменить пароль автоматически — сделай вручную в панели"

docker restart 3x-ui
sleep 10

# ── Proxy Host в NPM ─────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${YELLOW}║  ВАЖНО: ДОБАВЬ PROXY HOST В NPM ДЛЯ 3x-ui          ║${NC}"
echo -e "${BOLD}${YELLOW}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${YELLOW}║${NC} В NPM → Hosts → Proxy Hosts → Add:"
echo -e "${BOLD}${YELLOW}║${NC}   Domain Names:     ${CYAN}${XUI_DOMAIN}${NC}"
echo -e "${BOLD}${YELLOW}║${NC}   Forward Hostname: 3x-ui"
echo -e "${BOLD}${YELLOW}║${NC}   Forward Port:     2053"
echo -e "${BOLD}${YELLOW}║${NC}   Websockets: ✔"
echo -e "${BOLD}${YELLOW}║${NC}   SSL: Let's Encrypt + Force SSL + HTTP/2"
echo -e "${BOLD}${YELLOW}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${YELLOW}║  ВОЙДИ В ПАНЕЛЬ 3x-ui и НАСТРОЙ INBOUNDS:          ║${NC}"
echo -e "${BOLD}${YELLOW}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${YELLOW}║${NC} URL: ${CYAN}https://${XUI_DOMAIN}${NC}"
echo -e "${BOLD}${YELLOW}║${NC} Логин:  ${GREEN}${NEW_USER}${NC}"
echo -e "${BOLD}${YELLOW}║${NC} Пароль: ${GREEN}${XUI_PASS}${NC}"
echo -e "${BOLD}${YELLOW}║${NC}"
echo -e "${BOLD}${YELLOW}║  VLESS-Reality (порт ${P_VLESS_REALITY}):${NC}"
echo -e "${BOLD}${YELLOW}║${NC}   Protocol: vless | Network: tcp"
echo -e "${BOLD}${YELLOW}║${NC}   Security: reality"
echo -e "${BOLD}${YELLOW}║${NC}   uTLS: chrome | Dest: www.apple.com:443"
echo -e "${BOLD}${YELLOW}║${NC}   Server Names: www.apple.com"
echo -e "${BOLD}${YELLOW}║${NC}   Flow: xtls-rprx-vision"
echo -e "${BOLD}${YELLOW}║${NC}"
echo -e "${BOLD}${YELLOW}║  VLESS-XHTTP (порт ${P_VLESS_XHTTP}):${NC}"
echo -e "${BOLD}${YELLOW}║${NC}   Protocol: vless | Network: xhttp"
echo -e "${BOLD}${YELLOW}║${NC}   Security: tls (self-signed ok)"
echo -e "${BOLD}${YELLOW}║${NC}   Path: /xhttp"
echo -e "${BOLD}${YELLOW}║${NC}"
echo -e "${BOLD}${YELLOW}║  Trojan (порт ${P_TROJAN}):${NC}"
echo -e "${BOLD}${YELLOW}║${NC}   Protocol: trojan | Network: tcp"
echo -e "${BOLD}${YELLOW}║${NC}   Security: tls"
echo -e "${BOLD}${YELLOW}║${NC}"
echo -e "${BOLD}${YELLOW}║  Shadowsocks (порт ${P_SS}):${NC}"
echo -e "${BOLD}${YELLOW}║${NC}   Protocol: shadowsocks"
echo -e "${BOLD}${YELLOW}║${NC}   Method: chacha20-ietf-poly1305"
echo -e "${BOLD}${YELLOW}║${NC}   Network: tcp,udp"
echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
read -rp "$(echo -e "${BOLD}Настрой всё выше, проверь https://${XUI_DOMAIN} — нажми Enter:${NC} ")" _

log_ok "ШАГ 5 завершён. 3x-ui: https://${XUI_DOMAIN}"

# =============================================================================
#  ШАГ 6 — HYSTERIA 2
# =============================================================================
log_step "ШАГ 6 — Hysteria 2 (QUIC/UDP)"

# ── Установка acme.sh ─────────────────────────────────────────────────────────
log_section "6.1 — Установка acme.sh"

HOME_DIR=$(getent passwd "$NEW_USER" | cut -d: -f6)
ACME="${HOME_DIR}/.acme.sh/acme.sh"

if [[ -f "$ACME" ]]; then
  log_warn "acme.sh уже установлен — пропускаю"
else
  su - "$NEW_USER" -c \
    "curl https://get.acme.sh | sh -s email=${LE_EMAIL}"
  log_ok "acme.sh установлен"
fi

check_ok "acme.sh доступен" "su - ${NEW_USER} -c '${ACME} --version'" "acme"

# ── Выпуск сертификата ────────────────────────────────────────────────────────
log_section "6.2 — Выпуск TLS-сертификата для ${H2_DOMAIN}"

CERT_DIR="/opt/docker/hysteria2/cert"
chown -R "${NEW_USER}:${NEW_USER}" "${CERT_DIR}"

log_info "Пытаемся получить сертификат через webroot (NPM должен быть запущен)..."

ACME_WEBROOT="/opt/docker/nginx-proxy-manager/data/letsencrypt-acme-challenge"
mkdir -p "$ACME_WEBROOT"

# Сначала пробуем webroot через NPM
if su - "$NEW_USER" -c "
  ${ACME} --issue \
    -d ${H2_DOMAIN} \
    --webroot ${ACME_WEBROOT} \
    --server letsencrypt \
    --force 2>&1
" ; then
  log_ok "Сертификат получен через webroot"
else
  log_warn "Webroot не сработал — пробуем standalone (NPM остановим на 60 секунд)"
  cd /opt/docker/nginx-proxy-manager && docker compose stop
  sleep 5

  su - "$NEW_USER" -c "
    ${ACME} --issue \
      -d ${H2_DOMAIN} \
      --standalone \
      --server letsencrypt \
      --httpport 80 \
      --force 2>&1
  " || die "Не удалось получить сертификат. Убедись что DNS ${H2_DOMAIN} → ${SERVER_IP}"

  cd /opt/docker/nginx-proxy-manager && docker compose up -d
  sleep 10
fi

# ── Установка сертификата ─────────────────────────────────────────────────────
su - "$NEW_USER" -c "
  ${ACME} --install-cert -d ${H2_DOMAIN} \
    --cert-file     ${CERT_DIR}/cert.pem \
    --key-file      ${CERT_DIR}/key.pem \
    --fullchain-file ${CERT_DIR}/fullchain.pem \
    --reloadcmd 'docker restart hysteria2 2>/dev/null || true'
"

check_ok "Сертификат установлен" "ls ${CERT_DIR}" "fullchain.pem"

# ── Конфиг Hysteria2 ─────────────────────────────────────────────────────────
log_section "6.3 — Конфиг Hysteria 2"

tee /opt/docker/hysteria2/config.yaml > /dev/null << EOF
listen: :${P_H2}

tls:
  cert: /cert/fullchain.pem
  key: /cert/key.pem

auth:
  type: password
  password: ${H2_PASS}

masquerade:
  type: proxy
  proxy:
    url: https://news.ycombinator.com
    rewriteHost: true

bandwidth:
  up: 100 mbps
  down: 100 mbps
EOF

# ── docker-compose.yml ────────────────────────────────────────────────────────
tee /opt/docker/hysteria2/docker-compose.yml > /dev/null << EOF
services:
  hysteria2:
    image: tobyxdd/hysteria:latest
    container_name: hysteria2
    restart: unless-stopped
    ports:
      - "${P_H2}:${P_H2}/udp"
    volumes:
      - /opt/docker/hysteria2/cert:/cert:ro
      - /opt/docker/hysteria2/config.yaml:/etc/hysteria/config.yaml:ro
    command: server
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: "0.5"
        reservations:
          memory: 32M
    networks:
      - proxy-net

networks:
  proxy-net:
    external: true
EOF

cd /opt/docker/hysteria2
docker compose up -d
sleep 10
check_ok "Hysteria2 запущен" "docker compose ps" "Up"
check_ok "UDP порт ${P_H2} слушает" "ss -ulnp" "${P_H2}"

log_ok "ШАГ 6 завершён. Hysteria2 запущен на UDP ${P_H2}"

# =============================================================================
#  ШАГ 7 — TELEMT MTProxy
# =============================================================================
log_step "ШАГ 7 — Telemt (MTProxy для Telegram)"

tee /opt/docker/telemt/config.toml > /dev/null << EOF
[general]
use_middle_proxy = true

[general.modes]
classic = false
secure  = false
tls     = true

[general.links]
show = "*"

[server]
port = ${P_TELEMT}

[censorship]
tls_domain = "www.apple.com"

[access.users]
main = "${TELEMT_SECRET}"
EOF

tee /opt/docker/telemt/docker-compose.yml > /dev/null << EOF
services:
  telemt:
    image: ghcr.io/telemt/telemt:latest
    container_name: telemt
    restart: unless-stopped
    ports:
      - "${P_TELEMT}:${P_TELEMT}"
    volumes:
      - ./config.toml:/run/telemt/config.toml:ro
    working_dir: /run/telemt
    environment:
      - RUST_LOG=info
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    read_only: true
    security_opt:
      - no-new-privileges:true
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    tmpfs:
      - /run/telemt:rw,mode=1777,size=1m
    deploy:
      resources:
        limits:
          memory: 64M
          cpus: "0.25"
        reservations:
          memory: 16M
    networks:
      - proxy-net

networks:
  proxy-net:
    external: true
EOF

cd /opt/docker/telemt
docker compose pull
docker compose up -d
sleep 10
check_ok "Telemt запущен" "docker compose ps" "Up"

# =============================================================================
#  ИТОГОВАЯ СВОДКА
# =============================================================================
log_step "УСТАНОВКА ЗАВЕРШЕНА"

# Получаем ссылки Telemt из логов
TELEMT_LINK=$(docker logs telemt 2>&1 | grep -i "tg://" | head -1 || echo "см. docker logs telemt")

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║                   ИТОГ УСТАНОВКИ                           ║${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║  SSH                                                        ║${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Подключение:  ${CYAN}ssh -p 3270 ${NEW_USER}@${SERVER_IP}${NC}"
echo -e "${BOLD}${GREEN}║                                                             ║${NC}"
echo -e "${BOLD}${GREEN}║  ПАНЕЛИ УПРАВЛЕНИЯ                                          ║${NC}"
echo -e "${BOLD}${GREEN}║${NC}  NPM:          ${CYAN}https://${NPM_DOMAIN}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  3x-ui:        ${CYAN}https://${XUI_DOMAIN}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  3x-ui логин:  ${YELLOW}${NEW_USER}${NC} / ${YELLOW}${XUI_PASS}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Сайт:         ${CYAN}https://${ROOT_DOMAIN}${NC}"
echo -e "${BOLD}${GREEN}║                                                             ║${NC}"
echo -e "${BOLD}${GREEN}║  VPN-ПРОТОКОЛЫ (настрой Inbounds в 3x-ui)                 ║${NC}"
echo -e "${BOLD}${GREEN}║${NC}  VLESS-Reality: ${YELLOW}${SERVER_IP}:${P_VLESS_REALITY}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  VLESS-XHTTP:   ${YELLOW}${SERVER_IP}:${P_VLESS_XHTTP}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Trojan:         ${YELLOW}${SERVER_IP}:${P_TROJAN}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Shadowsocks:    ${YELLOW}${SERVER_IP}:${P_SS}${NC}"
echo -e "${BOLD}${GREEN}║                                                             ║${NC}"
echo -e "${BOLD}${GREEN}║  HYSTERIA 2                                                 ║${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Домен/порт:   ${YELLOW}${H2_DOMAIN}:${P_H2}${NC} (UDP)"
echo -e "${BOLD}${GREEN}║${NC}  Пароль:       ${YELLOW}${H2_PASS}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  URI:          ${CYAN}hysteria2://${H2_PASS}@${H2_DOMAIN}:${P_H2}?sni=${H2_DOMAIN}#H2${NC}"
echo -e "${BOLD}${GREEN}║                                                             ║${NC}"
echo -e "${BOLD}${GREEN}║  TELEGRAM MTPROXY                                           ║${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Секрет:       ${YELLOW}${TELEMT_SECRET}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Ссылка:       ${CYAN}${TELEMT_LINK}${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║  ОТКРЫТЫЕ ПОРТЫ                                             ║${NC}"
echo -e "${BOLD}${GREEN}║${NC}  3270/tcp  — SSH"
echo -e "${BOLD}${GREEN}║${NC}  80/tcp    — HTTP (NPM)"
echo -e "${BOLD}${GREEN}║${NC}  443/tcp   — HTTPS (NPM)"
echo -e "${BOLD}${GREEN}║${NC}  ${P_VLESS_REALITY}/tcp  — VLESS-Reality"
echo -e "${BOLD}${GREEN}║${NC}  ${P_VLESS_XHTTP}/tcp  — VLESS-XHTTP"
echo -e "${BOLD}${GREEN}║${NC}  ${P_TROJAN}/tcp  — Trojan"
echo -e "${BOLD}${GREEN}║${NC}  ${P_SS}/tcp+udp — Shadowsocks"
echo -e "${BOLD}${GREEN}║${NC}  ${P_H2}/udp  — Hysteria2"
echo -e "${BOLD}${GREEN}║${NC}  ${P_TELEMT}/tcp  — Telemt MTProxy"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"

# Сохраняем итог в файл
SUMMARY_FILE="/root/vps-setup-summary.txt"
{
  echo "=== VPS SETUP SUMMARY ==="
  echo "Date: $(date)"
  echo ""
  echo "SSH: ssh -p 3270 ${NEW_USER}@${SERVER_IP}"
  echo ""
  echo "--- Panels ---"
  echo "NPM:   https://${NPM_DOMAIN}"
  echo "3x-ui: https://${XUI_DOMAIN}  login: ${NEW_USER} / ${XUI_PASS}"
  echo "Site:  https://${ROOT_DOMAIN}"
  echo ""
  echo "--- VPN Ports ---"
  echo "VLESS-Reality: ${SERVER_IP}:${P_VLESS_REALITY}"
  echo "VLESS-XHTTP:   ${SERVER_IP}:${P_VLESS_XHTTP}"
  echo "Trojan:        ${SERVER_IP}:${P_TROJAN}"
  echo "Shadowsocks:   ${SERVER_IP}:${P_SS}"
  echo ""
  echo "--- Hysteria2 ---"
  echo "Server: ${H2_DOMAIN}:${P_H2} (UDP)"
  echo "Pass:   ${H2_PASS}"
  echo "URI:    hysteria2://${H2_PASS}@${H2_DOMAIN}:${P_H2}?sni=${H2_DOMAIN}#H2"
  echo ""
  echo "--- Telemt ---"
  echo "Secret: ${TELEMT_SECRET}"
  echo "Link:   ${TELEMT_LINK}"
} > "$SUMMARY_FILE"

chmod 600 "$SUMMARY_FILE"
log_ok "Сводка сохранена в ${SUMMARY_FILE}"

echo ""
log_info "Проверка всех контейнеров:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
log_info "Использование памяти:"
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}"

echo ""
log_info "UFW статус:"
ufw status verbose

echo ""
echo -e "${BOLD}${GREEN}Установка завершена! Все данные сохранены в ${SUMMARY_FILE}${NC}"
echo -e "${BOLD}${YELLOW}ВАЖНО: Удали этот файл после сохранения данных в менеджер паролей!${NC}"
echo -e "${BOLD}${YELLOW}       rm ${SUMMARY_FILE}${NC}"
