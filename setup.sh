#!/usr/bin/env bash
# =============================================================================
#  VPS SETUP SCRIPT v2.1
#  Ubuntu 24.04 LTS · Docker · NPM · 3x-ui · Hysteria2 · Telemt
# =============================================================================
set -euo pipefail

# ─── Цвета ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()    { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════════${NC}"
                echo -e "${BOLD}${BLUE}  $*${NC}"
                echo -e "${BOLD}${BLUE}══════════════════════════════════════════════${NC}\n"; }
log_section() { echo -e "\n${BOLD}${CYAN}── $* ──${NC}\n"; }

die() { log_error "$*"; exit 1; }

# ─── Проверка root ────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Запусти скрипт от root: sudo bash setup.sh"

# ─── Файл состояния ──────────────────────────────────────────────────────────
STATE_FILE="/root/.vps-setup-state"
VARS_FILE="/root/.vps-setup-vars"

save_state() { echo "$1" > "$STATE_FILE"; }
get_state()  { [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" || echo "0"; }

# Сохраняем переменные между запусками
# ВАЖНО: heredoc без кавычек вокруг метки (VARS) выполняет подстановку переменных —
# это нужное поведение, но спецсимволы в паролях могут сломать heredoc.
# Поэтому каждую переменную пишем через printf.
save_vars() {
  {
    printf 'NEW_USER=%q\n'         "${NEW_USER}"
    printf 'USER_PASS=%q\n'        "${USER_PASS}"
    printf 'LE_EMAIL=%q\n'         "${LE_EMAIL}"
    printf 'ROOT_DOMAIN=%q\n'      "${ROOT_DOMAIN}"
    printf 'NPM_DOMAIN=%q\n'       "${NPM_DOMAIN}"
    printf 'XUI_DOMAIN=%q\n'       "${XUI_DOMAIN}"
    printf 'H2_DOMAIN=%q\n'        "${H2_DOMAIN}"
    printf 'SERVER_IP=%q\n'        "${SERVER_IP}"
    printf 'H2_PASS=%q\n'          "${H2_PASS}"
    printf 'TELEMT_SECRET=%q\n'    "${TELEMT_SECRET}"
    printf 'SSH_PORT=%q\n'         "${SSH_PORT}"
    printf 'XUI_PORT=%q\n'         "${XUI_PORT}"
    printf 'P_VLESS_REALITY=%q\n'  "${P_VLESS_REALITY}"
    printf 'P_VLESS_XHTTP=%q\n'    "${P_VLESS_XHTTP}"
    printf 'P_TROJAN=%q\n'         "${P_TROJAN}"
    printf 'P_SS=%q\n'             "${P_SS}"
    printf 'P_H2=%q\n'             "${P_H2}"
    printf 'P_TELEMT=%q\n'         "${P_TELEMT}"
  } > "$VARS_FILE"
  chmod 600 "$VARS_FILE"
}

load_vars() {
  [[ -f "$VARS_FILE" ]] && source "$VARS_FILE" || true
}

# ─── Проверка DNS ─────────────────────────────────────────────────────────────
check_dns() {
  local domain="$1"; local expected_ip="$2"
  local resolved
  resolved=$(dig +short "$domain" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)
  if [[ "$resolved" == "$expected_ip" ]]; then
    log_ok "DNS: ${domain} → ${resolved} ✓"
    return 0
  elif [[ -z "$resolved" ]]; then
    log_warn "DNS: ${domain} → не резолвится (ещё не распространился или запись не добавлена)"
    return 1
  else
    log_warn "DNS: ${domain} → ${resolved} (ожидаем ${expected_ip})"
    return 1
  fi
}

wait_dns() {
  local domain="$1"; local expected_ip="$2"
  log_info "Проверяем DNS для ${domain}..."
  if check_dns "$domain" "$expected_ip"; then
    return 0
  fi
  echo ""
  echo -e "${YELLOW}DNS ещё не распространился. Варианты:${NC}"
  echo "  1) Подождать и проверить снова"
  echo "  2) Продолжить без проверки (если уверен что DNS настроен)"
  echo "  3) Выйти и настроить DNS"
  read -rp "Выбор [1/2/3]: " dns_choice
  case "$dns_choice" in
    1)
      log_info "Ждём 30 секунд..."
      sleep 30
      wait_dns "$domain" "$expected_ip"
      ;;
    2)
      log_warn "Продолжаем без подтверждения DNS — Let's Encrypt может упасть"
      ;;
    *)
      die "Настрой DNS и перезапусти скрипт с нужного этапа"
      ;;
  esac
}

# ─── Итог этапа ──────────────────────────────────────────────────────────────
stage_done() {
  local stage_num="$1"; local stage_name="$2"; local rollback_hint="$3"
  save_state "$stage_num"
  echo ""
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${GREEN}║  ✓ Этап ${stage_num} завершён: ${stage_name}${NC}"
  echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
  echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}Если нужно откатить этот этап:${NC}"
  echo -e "${BOLD}${GREEN}║${NC}  ${rollback_hint}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
}

# =============================================================================
#  МЕНЮ СТАРТА
# =============================================================================
CURRENT_STATE=$(get_state)

echo -e "\n${BOLD}${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║           VPS SETUP SCRIPT v2.1                     ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════╝${NC}\n"

if [[ "$CURRENT_STATE" != "0" ]]; then
  echo -e "${YELLOW}Найдено сохранённое состояние: завершён этап ${CURRENT_STATE}${NC}"
  echo ""
  echo "Выбери действие:"
  echo "  1) Продолжить с этапа $((CURRENT_STATE + 1))"
  echo "  2) Начать заново (новая установка)"
  echo "  3) Начать с конкретного этапа"
  echo "  4) Показать список этапов"
  echo ""
  read -rp "Выбор [1/2/3/4]: " start_choice
  case "$start_choice" in
    1) START_STAGE=$((CURRENT_STATE + 1))
       load_vars ;;
    2) START_STAGE=0
       rm -f "$STATE_FILE" "$VARS_FILE" ;;
    3) echo ""
       echo "Этапы:"
       echo "  0 — Сбор данных + обновление системы"
       echo "  1 — Пользователь, SSH, Swap, UFW, Fail2Ban"
       echo "  2 — Docker, папки, сеть"
       echo "  3 — Nginx Proxy Manager"
       echo "  4 — Nginx сайт-заглушка"
       echo "  5 — 3x-ui (VPN панель)"
       echo "  6 — Hysteria 2"
       echo "  7 — Telemt MTProxy"
       read -rp "Начать с этапа: " START_STAGE
       load_vars ;;
    4) echo ""
       echo "Этапы:"
       echo "  0 — Сбор данных + обновление системы"
       echo "  1 — Пользователь, SSH, Swap, UFW, Fail2Ban"
       echo "  2 — Docker, папки, сеть"
       echo "  3 — Nginx Proxy Manager"
       echo "  4 — Nginx сайт-заглушка"
       echo "  5 — 3x-ui (VPN панель)"
       echo "  6 — Hysteria 2"
       echo "  7 — Telemt MTProxy"
       echo ""
       read -rp "Начать с этапа: " START_STAGE
       load_vars ;;
    *) START_STAGE=0 ;;
  esac
else
  START_STAGE=0
fi

# =============================================================================
#  ЭТАП 0 — СБОР ДАННЫХ + ОБНОВЛЕНИЕ СИСТЕМЫ
# =============================================================================
if [[ "$START_STAGE" -le 0 ]]; then

log_step "ЭТАП 0 — Сбор данных"
echo -e "${YELLOW}Все данные вводятся сейчас. Скрипт больше не будет спрашивать.${NC}\n"

# ── Имя пользователя ──────────────────────────────────────────────────────────
while true; do
  read -rp "$(echo -e "${BOLD}Имя нового SSH-пользователя:${NC} ")" NEW_USER
  [[ "$NEW_USER" =~ ^[a-z_][a-z0-9_-]{1,31}$ ]] && break
  log_warn "Только строчные буквы, цифры, _ и - (2–32 символа)"
done

# ── Пароль пользователя ───────────────────────────────────────────────────────
echo -e "${CYAN}Рекомендуем пароль 12+ символов. Подтверждение паролей обязательно.${NC}"
while true; do
  read -rsp "$(echo -e "${BOLD}Пароль для ${NEW_USER}:${NC} ")" USER_PASS; echo
  [[ -z "$USER_PASS" ]] && { log_warn "Пароль не может быть пустым"; continue; }
  read -rsp "$(echo -e "${BOLD}Повтори пароль:${NC} ")" USER_PASS2; echo
  [[ "$USER_PASS" == "$USER_PASS2" ]] && break
  log_warn "Пароли не совпадают"
done

# ── Email ─────────────────────────────────────────────────────────────────────
while true; do
  read -rp "$(echo -e "${BOLD}Email для Let's Encrypt / acme.sh:${NC} ")" LE_EMAIL
  [[ "$LE_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]] && break
  log_warn "Введи корректный email"
done

# ── Основной домен ────────────────────────────────────────────────────────────
while true; do
  read -rp "$(echo -e "${BOLD}Основной домен (например: example.ru):${NC} ")" ROOT_DOMAIN
  [[ "$ROOT_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] && break
  log_warn "Введи домен без http:// и слешей"
done

echo ""
echo -e "${CYAN}Субдомены по умолчанию:${NC}"
echo -e "  npm.${ROOT_DOMAIN}   → NPM панель"
echo -e "  cdn.${ROOT_DOMAIN}   → 3x-ui панель"
echo -e "  hist.${ROOT_DOMAIN}  → Hysteria2"
echo ""
read -rp "$(echo -e "${BOLD}Использовать эти субдомены? (y/n):${NC} ")" SUBDOMAIN_CONFIRM
if [[ "$SUBDOMAIN_CONFIRM" =~ ^[Yy]$ ]]; then
  NPM_DOMAIN="npm.${ROOT_DOMAIN}"
  XUI_DOMAIN="cdn.${ROOT_DOMAIN}"
  H2_DOMAIN="hist.${ROOT_DOMAIN}"
else
  read -rp "$(echo -e "${BOLD}Субдомен для NPM-панели:${NC} ")"  NPM_DOMAIN
  read -rp "$(echo -e "${BOLD}Субдомен для 3x-ui:${NC} ")"       XUI_DOMAIN
  read -rp "$(echo -e "${BOLD}Субдомен для Hysteria2:${NC} ")"   H2_DOMAIN
fi

# ── IP сервера ────────────────────────────────────────────────────────────────
SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
            curl -s --max-time 5 https://ifconfig.me  2>/dev/null || \
            hostname -I | awk '{print $1}')
echo ""
log_info "Определён IP: ${GREEN}${SERVER_IP}${NC}"
read -rp "$(echo -e "${BOLD}Верно? Или введи IP вручную (Enter = ${SERVER_IP}):${NC} ")" IP_INPUT
[[ -n "$IP_INPUT" ]] && SERVER_IP="$IP_INPUT"

# ── Порт SSH ──────────────────────────────────────────────────────────────────
echo ""
read -rp "$(echo -e "${BOLD}Порт SSH (Enter = 3270):${NC} ")" SSH_PORT
SSH_PORT=${SSH_PORT:-3270}

# ── Порт панели 3x-ui ────────────────────────────────────────────────────────
read -rp "$(echo -e "${BOLD}Порт панели 3x-ui (Enter = 2053):${NC} ")" XUI_PORT
XUI_PORT=${XUI_PORT:-2053}

# ── Автогенерация секретов ────────────────────────────────────────────────────
H2_PASS=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
TELEMT_SECRET=$(openssl rand -hex 16)
log_info "Пароль Hysteria2 сгенерирован автоматически"
log_info "Секрет Telemt MTProxy сгенерирован автоматически"

# ── Порты VPN ─────────────────────────────────────────────────────────────────
echo ""
log_section "Порты VPN (Enter = значение по умолчанию)"
read -rp "$(echo -e "${BOLD}VLESS-Reality  [8443]:${NC} ")" P_VLESS_REALITY; P_VLESS_REALITY=${P_VLESS_REALITY:-8443}
read -rp "$(echo -e "${BOLD}VLESS-XHTTP    [8448]:${NC} ")" P_VLESS_XHTTP;   P_VLESS_XHTTP=${P_VLESS_XHTTP:-8448}
read -rp "$(echo -e "${BOLD}Trojan         [8449]:${NC} ")" P_TROJAN;         P_TROJAN=${P_TROJAN:-8449}
read -rp "$(echo -e "${BOLD}Shadowsocks    [8445]:${NC} ")" P_SS;             P_SS=${P_SS:-8445}
read -rp "$(echo -e "${BOLD}Hysteria2 UDP  [8444]:${NC} ")" P_H2;             P_H2=${P_H2:-8444}
read -rp "$(echo -e "${BOLD}Telemt MTProxy [8446]:${NC} ")" P_TELEMT;         P_TELEMT=${P_TELEMT:-8446}

# ── Сводка ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║           СВОДКА ВВЕДЁННЫХ ДАННЫХ                   ║${NC}"
echo -e "${BOLD}${BLUE}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${BLUE}║${NC} Пользователь  : ${GREEN}${NEW_USER}${NC}"
echo -e "${BOLD}${BLUE}║${NC} Email         : ${GREEN}${LE_EMAIL}${NC}"
echo -e "${BOLD}${BLUE}║${NC} IP сервера    : ${GREEN}${SERVER_IP}${NC}"
echo -e "${BOLD}${BLUE}║${NC} Корневой домен: ${GREEN}${ROOT_DOMAIN}${NC}"
echo -e "${BOLD}${BLUE}║${NC} NPM панель    : ${GREEN}https://${NPM_DOMAIN}${NC}"
echo -e "${BOLD}${BLUE}║${NC} 3x-ui панель  : ${GREEN}https://${XUI_DOMAIN}${NC}"
echo -e "${BOLD}${BLUE}║${NC} Hysteria2     : ${GREEN}${H2_DOMAIN}${NC}"
echo -e "${BOLD}${BLUE}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${BLUE}║${NC} SSH порт      : ${GREEN}${SSH_PORT}/tcp${NC}"
echo -e "${BOLD}${BLUE}║${NC} 3x-ui порт   : ${GREEN}${XUI_PORT}/tcp (внутренний)${NC}"
echo -e "${BOLD}${BLUE}║${NC} VLESS-Reality : ${GREEN}${P_VLESS_REALITY}/tcp${NC}"
echo -e "${BOLD}${BLUE}║${NC} VLESS-XHTTP  : ${GREEN}${P_VLESS_XHTTP}/tcp${NC}"
echo -e "${BOLD}${BLUE}║${NC} Trojan        : ${GREEN}${P_TROJAN}/tcp${NC}"
echo -e "${BOLD}${BLUE}║${NC} Shadowsocks   : ${GREEN}${P_SS}/tcp+udp${NC}"
echo -e "${BOLD}${BLUE}║${NC} Hysteria2     : ${GREEN}${P_H2}/udp${NC}"
echo -e "${BOLD}${BLUE}║${NC} Telemt        : ${GREEN}${P_TELEMT}/tcp${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
read -rp "$(echo -e "${BOLD}${RED}Всё верно? Продолжить? (yes/no):${NC} ")" FINAL_CONFIRM
[[ "$FINAL_CONFIRM" == "yes" ]] || die "Установка отменена"

# Сохраняем переменные сразу
save_vars

# ── Обновление системы ────────────────────────────────────────────────────────
log_section "Обновление системы"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -o Dpkg::Options::="--force-confold" -qq
apt-get install -y -o Dpkg::Options::="--force-confold" -qq \
  curl wget git htop net-tools ufw fail2ban unzip \
  python3 openssl unattended-upgrades apt-listchanges dnsutils
apt-get autoremove -y -qq

# Автообновления безопасности
dpkg-reconfigure -plow unattended-upgrades <<< $'\n' 2>/dev/null || true
log_ok "Система обновлена"

stage_done 0 "Сбор данных + запуск обновления" \
  "rm -f /root/.vps-setup-state /root/.vps-setup-vars — сбросит прогресс"

fi  # END STAGE 0

# После любого START_STAGE нам нужны переменные
load_vars

# =============================================================================
#  ЭТАП 1 — ПОЛЬЗОВАТЕЛЬ, SSH, SWAP, UFW, FAIL2BAN
# =============================================================================
if [[ "$START_STAGE" -le 1 ]]; then

log_step "ЭТАП 1 — Пользователь, SSH, Swap, UFW, Fail2Ban"

# ── 1.1 Пользователь ─────────────────────────────────────────────────────────
log_section "1.1 — Создание пользователя ${NEW_USER}"

if id "$NEW_USER" &>/dev/null; then
  log_warn "Пользователь ${NEW_USER} уже существует — обновляю пароль"
  echo "${NEW_USER}:${USER_PASS}" | chpasswd
else
  useradd -m -s /bin/bash "$NEW_USER"
  echo "${NEW_USER}:${USER_PASS}" | chpasswd
  log_ok "Пользователь ${NEW_USER} создан"
fi

usermod -aG sudo "$NEW_USER"
echo "${NEW_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"${NEW_USER}"
chmod 440 /etc/sudoers.d/"${NEW_USER}"

id "$NEW_USER" | grep -q sudo && log_ok "Пользователь в группе sudo" || \
  log_warn "Пользователь НЕ в группе sudo!"

# ── 1.2 SSH ───────────────────────────────────────────────────────────────────
log_section "1.2 — Настройка SSH (порт ${SSH_PORT})"

cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

configure_ssh() {
  local param="$1"; local value="$2"; local file="/etc/ssh/sshd_config"
  if grep -qE "^#?\s*${param}\b" "$file"; then
    sed -i -E "s|^#?\s*${param}\b.*|${param} ${value}|" "$file"
  else
    echo "${param} ${value}" >> "$file"
  fi
}

configure_ssh "Port"                   "${SSH_PORT}"
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

sshd -t || { cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config; die "Ошибка sshd_config — откат выполнен"; }
systemctl enable ssh
systemctl restart ssh
sleep 2

ss -tlnp | grep -q ":${SSH_PORT}" && log_ok "SSH слушает порт ${SSH_PORT}" || \
  log_warn "SSH не найден на порту ${SSH_PORT}!"

echo ""
echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${YELLOW}║  ВАЖНО: ПРОВЕРЬ SSH ДО ЗАКРЫТИЯ ЭТОГО ОКНА!        ║${NC}"
echo -e "${BOLD}${YELLOW}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${YELLOW}║${NC}  Открой НОВЫЙ терминал и выполни:"
echo -e "${BOLD}${YELLOW}║${NC}  ${CYAN}ssh -p ${SSH_PORT} ${NEW_USER}@${SERVER_IP}${NC}"
echo -e "${BOLD}${YELLOW}║${NC}"
echo -e "${BOLD}${YELLOW}║${NC}  Если вход не удался — в ЭТОМ терминале:"
echo -e "${BOLD}${YELLOW}║${NC}  ${RED}cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config${NC}"
echo -e "${BOLD}${YELLOW}║${NC}  ${RED}systemctl restart ssh${NC}"
echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
read -rp "$(echo -e "${BOLD}Подтверди успешный вход в новом терминале, затем нажми Enter:${NC} ")" _

# ── 1.3 ICMP ─────────────────────────────────────────────────────────────────
log_section "1.3 — Отключение ICMP (ping)"
grep -q "icmp_echo_ignore_all" /etc/sysctl.conf || \
  printf '\nnet.ipv4.icmp_echo_ignore_all = 1\nnet.ipv6.icmp.echo_ignore_all = 1\n' >> /etc/sysctl.conf
sysctl -p > /dev/null
log_ok "ICMP отключён"

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
sysctl -p > /dev/null
free -h

# ── 1.5 Часовой пояс ─────────────────────────────────────────────────────────
timedatectl set-timezone Europe/Moscow
log_ok "Часовой пояс: Europe/Moscow"

# ── 1.6 UFW ──────────────────────────────────────────────────────────────────
log_section "1.5 — UFW брандмауэр"

ufw --force reset > /dev/null
ufw default deny incoming
ufw default allow outgoing

ufw allow "${SSH_PORT}/tcp"           comment 'SSH'
ufw allow 80/tcp                      comment 'HTTP → NPM'
ufw allow 81/tcp                      comment 'NPM Admin (временно)'
ufw allow 443/tcp                     comment 'HTTPS → NPM'
ufw allow "${P_VLESS_REALITY}/tcp"    comment 'VLESS-Reality'
ufw allow "${P_VLESS_XHTTP}/tcp"      comment 'VLESS-XHTTP'
ufw allow "${P_TROJAN}/tcp"           comment 'Trojan'
ufw allow "${P_SS}/tcp"               comment 'Shadowsocks TCP'
ufw allow "${P_SS}/udp"               comment 'Shadowsocks UDP'
ufw allow "${P_H2}/udp"               comment 'Hysteria2'
ufw allow "${P_TELEMT}/tcp"           comment 'Telemt MTProxy'

ufw --force enable > /dev/null
ufw status verbose

# ── 1.7 Fail2Ban ─────────────────────────────────────────────────────────────
log_section "1.6 — Fail2Ban"

cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime  = 5h
findtime = 2m
maxretry = 2
backend  = systemd

[sshd]
enabled = true
port    = ${SSH_PORT}
EOF

systemctl enable fail2ban > /dev/null 2>&1
systemctl restart fail2ban
sleep 2
fail2ban-client ping 2>/dev/null | grep -q "pong" && log_ok "Fail2Ban работает" || \
  log_warn "Fail2Ban не отвечает — проверь: journalctl -u fail2ban"


stage_done 1 "Пользователь, SSH, Swap, UFW, Fail2Ban" \
  "SSH откат: cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config && systemctl restart ssh
  UFW откат:  ufw disable
  Swap откат: swapoff /swapfile && rm /swapfile"

fi  # END STAGE 1

# =============================================================================
#  ЭТАП 2 — DOCKER
# =============================================================================
if [[ "$START_STAGE" -le 2 ]]; then

log_step "ЭТАП 2 — Docker + структура папок + сеть proxy-net"

# ── 2.1 Установка ─────────────────────────────────────────────────────────────
log_section "2.1 — Установка Docker"

if command -v docker &>/dev/null; then
  log_warn "Docker уже установлен: $(docker --version)"
else
  curl -fsSL https://get.docker.com | sh
  log_ok "Docker установлен"
fi

usermod -aG docker "$NEW_USER"
systemctl enable docker > /dev/null 2>&1
systemctl start docker
docker version --format 'Server: {{.Server.Version}}' 2>/dev/null && log_ok "Docker запущен" || \
  die "Docker не запустился!"

# ── 2.2 Лимиты логов ─────────────────────────────────────────────────────────
log_section "2.2 — Лимиты логов Docker"

mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "3"
  }
}
EOF

systemctl restart docker
sleep 2
log_ok "Лимиты логов: 20m × 3 файла"

# ── 2.3 Структура папок ───────────────────────────────────────────────────────
log_section "2.3 — Структура /opt/docker"

mkdir -p /opt/docker/{nginx-proxy-manager/data,nginx-proxy-manager/letsencrypt,\
nginx-site/html,3x-ui/db,3x-ui/cert,telemt,hysteria2/cert}
chown -R "${NEW_USER}:${NEW_USER}" /opt/docker
log_ok "Папки созданы"

# ── 2.4 Сеть proxy-net ───────────────────────────────────────────────────────
log_section "2.4 — Сеть proxy-net"

if docker network ls | grep -q proxy-net; then
  log_warn "Сеть proxy-net уже существует"
else
  docker network create --subnet=172.18.0.0/16 proxy-net
  log_ok "Сеть proxy-net (172.18.0.0/16) создана"
fi

stage_done 2 "Docker, папки, proxy-net" \
  "docker network rm proxy-net
  apt-get remove -y docker-ce docker-ce-cli containerd.io"

fi  # END STAGE 2

# =============================================================================
#  ЭТАП 3 — NGINX PROXY MANAGER
# =============================================================================
if [[ "$START_STAGE" -le 3 ]]; then

log_step "ЭТАП 3 — Nginx Proxy Manager"

# DNS проверка
echo ""
log_info "Проверяем DNS-записи (нужны до получения SSL):"
wait_dns "${NPM_DOMAIN}"  "${SERVER_IP}"
wait_dns "${XUI_DOMAIN}"  "${SERVER_IP}"
wait_dns "${ROOT_DOMAIN}" "${SERVER_IP}"
wait_dns "${H2_DOMAIN}"   "${SERVER_IP}"

# ── docker-compose.yml ────────────────────────────────────────────────────────
cat > /opt/docker/nginx-proxy-manager/docker-compose.yml << EOF
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

cd /opt/docker/nginx-proxy-manager

if docker ps --format '{{.Names}}' | grep -q "^nginx-proxy-manager$"; then
  log_warn "NPM уже запущен — перезапускаю"
  docker compose down
fi

docker compose up -d
log_info "Ждём инициализации NPM (25 секунд)..."
sleep 25

docker ps --format '{{.Names}} {{.Status}}' | grep "nginx-proxy-manager" | \
  grep -q "Up" && log_ok "NPM запущен" || \
  die "NPM не запустился — смотри: docker logs nginx-proxy-manager"

echo ""
echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${YELLOW}║  ДЕЙСТВИЯ В БРАУЗЕРЕ — NPM                          ║${NC}"
echo -e "${BOLD}${YELLOW}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${YELLOW}║${NC} 1. Открой: ${CYAN}http://${SERVER_IP}:81${NC}"
echo -e "${BOLD}${YELLOW}║${NC} 2. Войди:  admin@example.com / changeme"
echo -e "${BOLD}${YELLOW}║${NC} 3. Смени email → ${GREEN}${LE_EMAIL}${NC} и задай новый пароль"
echo -e "${BOLD}${YELLOW}║${NC}"
echo -e "${BOLD}${YELLOW}║${NC} 4. Add Proxy Host для ${CYAN}${NPM_DOMAIN}${NC}:"
echo -e "${BOLD}${YELLOW}║${NC}    Forward Hostname: ${GREEN}nginx-proxy-manager${NC}"
echo -e "${BOLD}${YELLOW}║${NC}    Forward Port:     ${GREEN}81${NC}"
echo -e "${BOLD}${YELLOW}║${NC}    SSL: Let's Encrypt + Force SSL + HTTP/2"
echo -e "${BOLD}${YELLOW}║${NC}"
echo -e "${BOLD}${YELLOW}║${NC} DNS должна быть настроена:"
echo -e "${BOLD}${YELLOW}║${NC}   ${ROOT_DOMAIN}     → ${SERVER_IP}"
echo -e "${BOLD}${YELLOW}║${NC}   www.${ROOT_DOMAIN} → ${SERVER_IP}"
echo -e "${BOLD}${YELLOW}║${NC}   ${NPM_DOMAIN} → ${SERVER_IP}"
echo -e "${BOLD}${YELLOW}║${NC}   ${XUI_DOMAIN} → ${SERVER_IP}"
echo -e "${BOLD}${YELLOW}║${NC}   ${H2_DOMAIN}  → ${SERVER_IP}"
echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
read -rp "$(echo -e "${BOLD}Выполни всё выше, убедись что https://${NPM_DOMAIN} открывается → Enter:${NC} ")" _

# ── Закрываем порт 81 ────────────────────────────────────────────────────────
log_section "Закрываем порт 81"
ufw delete allow 81/tcp 2>/dev/null || true
sed -i 's|- "81:81"|- "127.0.0.1:81:81"|' \
  /opt/docker/nginx-proxy-manager/docker-compose.yml

cd /opt/docker/nginx-proxy-manager
docker compose down && docker compose up -d
log_info "Ждём перезапуска NPM (15 секунд)..."
sleep 15

docker ps --format '{{.Names}} {{.Status}}' | grep "nginx-proxy-manager" | \
  grep -q "Up" && log_ok "NPM перезапущен" || \
  log_warn "NPM не запустился после перезапуска — проверь: docker logs nginx-proxy-manager"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://${NPM_DOMAIN}" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "301" || "$HTTP_CODE" == "302" ]]; then
  log_ok "https://${NPM_DOMAIN} отвечает (HTTP ${HTTP_CODE})"
else
  log_warn "https://${NPM_DOMAIN} вернул HTTP ${HTTP_CODE} — проверь настройки NPM"
fi

DIRECT_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://${SERVER_IP}:81" 2>/dev/null || echo "000")
[[ "$DIRECT_CODE" == "000" ]] && log_ok "Прямой доступ к :81 закрыт ✓" || \
  log_warn "Порт 81 всё ещё доступен напрямую (HTTP ${DIRECT_CODE})"

stage_done 3 "Nginx Proxy Manager" \
  "cd /opt/docker/nginx-proxy-manager && docker compose down
  ufw delete allow 80/tcp && ufw delete allow 443/tcp"

fi  # END STAGE 3

# =============================================================================
#  ЭТАП 4 — NGINX САЙТ-ЗАГЛУШКА
# =============================================================================
if [[ "$START_STAGE" -le 4 ]]; then

log_step "ЭТАП 4 — Nginx сайт-заглушка"

cat > /opt/docker/nginx-site/html/index.html << EOF
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

cat > /opt/docker/nginx-site/docker-compose.yml << 'EOF'
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
if docker ps --format '{{.Names}}' | grep -q "^nginx-site$"; then
  docker compose down
fi
docker compose up -d
sleep 5

docker ps --format '{{.Names}} {{.Status}}' | grep "nginx-site" | grep -q "Up" && \
  log_ok "nginx-site запущен" || log_warn "nginx-site не запустился"

echo ""
echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${YELLOW}║  ДЕЙСТВИЯ В NPM — САЙТ-ЗАГЛУШКА                    ║${NC}"
echo -e "${BOLD}${YELLOW}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${YELLOW}║${NC} Add Proxy Host:"
echo -e "${BOLD}${YELLOW}║${NC}   Domain Names:     ${CYAN}${ROOT_DOMAIN}${NC} + ${CYAN}www.${ROOT_DOMAIN}${NC}"
echo -e "${BOLD}${YELLOW}║${NC}   Forward Hostname: ${GREEN}nginx-site${NC}"
echo -e "${BOLD}${YELLOW}║${NC}   Forward Port:     ${GREEN}80${NC}"
echo -e "${BOLD}${YELLOW}║${NC}   Websockets: ✔ | Block Common Exploits: ✔"
echo -e "${BOLD}${YELLOW}║${NC}   SSL: Let's Encrypt + Force SSL + HTTP/2"
echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
read -rp "$(echo -e "${BOLD}Настрой Proxy Host, проверь https://${ROOT_DOMAIN} → Enter:${NC} ")" _

stage_done 4 "Nginx сайт-заглушка" \
  "cd /opt/docker/nginx-site && docker compose down"

fi  # END STAGE 4

# =============================================================================
#  ЭТАП 5 — 3x-ui
# =============================================================================
if [[ "$START_STAGE" -le 5 ]]; then

log_step "ЭТАП 5 — 3x-ui (панель управления VPN)"

cat > /opt/docker/3x-ui/docker-compose.yml << EOF
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
      - "${XUI_PORT}"
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

cd /opt/docker/3x-ui
if docker ps --format '{{.Names}}' | grep -q "^3x-ui$"; then
  docker compose down
fi

docker compose pull
docker compose up -d
log_info "Ждём запуска 3x-ui (20 секунд)..."
sleep 20

docker ps --format '{{.Names}} {{.Status}}' | grep "3x-ui" | grep -q "Up" && \
  log_ok "3x-ui запущен" || log_warn "3x-ui не запустился — см. docker logs 3x-ui"

# ── Proxy Host в NPM + сертификат для панели ─────────────────────────────────
echo ""
echo -e "${BOLD}${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${YELLOW}║  ДЕЙСТВИЯ В NPM — 3x-ui                                       ║${NC}"
echo -e "${BOLD}${YELLOW}╠════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${YELLOW}║${NC}"
echo -e "${BOLD}${YELLOW}║${NC}  Шаг 1 — Add Proxy Host:"
echo -e "${BOLD}${YELLOW}║${NC}    Domain Names:     ${CYAN}${XUI_DOMAIN}${NC}"
echo -e "${BOLD}${YELLOW}║${NC}    Forward Hostname: ${GREEN}3x-ui${NC}"
echo -e "${BOLD}${YELLOW}║${NC}    Forward Port:     ${GREEN}${XUI_PORT}${NC}"
echo -e "${BOLD}${YELLOW}║${NC}    Websockets: ✔ | Block Common Exploits: ✔"
echo -e "${BOLD}${YELLOW}║${NC}    SSL → Let's Encrypt + Force SSL + HTTP/2"
echo -e "${BOLD}${YELLOW}║${NC}"
echo -e "${BOLD}${YELLOW}║${NC}  Шаг 2 — Зайди в панель по адресу:"
echo -e "${BOLD}${YELLOW}║${NC}    ${CYAN}https://${XUI_DOMAIN}${NC}"
echo -e "${BOLD}${YELLOW}║${NC}    Логин по умолчанию: ${GREEN}admin / admin${NC}"
echo -e "${BOLD}${YELLOW}║${NC}"
echo -e "${BOLD}${YELLOW}║${NC}  Шаг 3 — Смена логина/пароля (если не работает через UI):"
echo -e "${BOLD}${YELLOW}║${NC}    ${CYAN}docker exec -it 3x-ui x-ui${NC}"
echo -e "${BOLD}${YELLOW}║${NC}    Выбери пункт 7 — 'Reset username and password'${NC}"
echo -e "${BOLD}${YELLOW}║${NC}"
echo -e "${BOLD}${YELLOW}║${NC}  Шаг 4 — Установка сертификата для Xray-inbounds:"
echo -e "${BOLD}${YELLOW}║${NC}    Найди сертификат NPM для ${XUI_DOMAIN}:"
echo -e "${BOLD}${YELLOW}║${NC}    ${CYAN}ls /opt/docker/nginx-proxy-manager/letsencrypt/live/${NC}"
echo -e "${BOLD}${YELLOW}║${NC}    Скопируй в папку 3x-ui:"
echo -e "${BOLD}${YELLOW}║${NC}    ${CYAN}XUI_CERT_DIR=\$(ls /opt/docker/nginx-proxy-manager/letsencrypt/live/ \\${NC}"
echo -e "${BOLD}${YELLOW}║${NC}    ${CYAN}  | grep ${XUI_DOMAIN} | head -1)${NC}"
echo -e "${BOLD}${YELLOW}║${NC}    ${CYAN}cp /opt/docker/nginx-proxy-manager/letsencrypt/live/\${XUI_CERT_DIR}/fullchain.pem \\${NC}"
echo -e "${BOLD}${YELLOW}║${NC}    ${CYAN}   /opt/docker/3x-ui/cert/fullchain.pem${NC}"
echo -e "${BOLD}${YELLOW}║${NC}    ${CYAN}cp /opt/docker/nginx-proxy-manager/letsencrypt/live/\${XUI_CERT_DIR}/privkey.pem \\${NC}"
echo -e "${BOLD}${YELLOW}║${NC}    ${CYAN}   /opt/docker/3x-ui/cert/privkey.pem${NC}"
echo -e "${BOLD}${YELLOW}║${NC}"
echo -e "${BOLD}${YELLOW}║${NC}  Шаг 5 — В панели 3x-ui → Panel Settings:"
echo -e "${BOLD}${YELLOW}║${NC}    Panel Certificate Public Key  : ${GREEN}/root/cert/fullchain.pem${NC}"
echo -e "${BOLD}${YELLOW}║${NC}    Panel Certificate Private Key : ${GREEN}/root/cert/privkey.pem${NC}"
echo -e "${BOLD}${YELLOW}║${NC}    (путь внутри контейнера — так и вводи)"
echo -e "${BOLD}${YELLOW}║${NC}"
echo -e "${BOLD}${YELLOW}║${NC}  Шаг 6 — Проверка:"
echo -e "${BOLD}${YELLOW}║${NC}    ${CYAN}docker ps | grep 3x-ui${NC}"
echo -e "${BOLD}${YELLOW}║${NC}    ${CYAN}docker logs 3x-ui --tail 20${NC}"
echo -e "${BOLD}${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Автоматическое копирование сертификата ───────────────────────────────────
log_section "5.1 — Копируем сертификат NPM → 3x-ui"

LETSENCRYPT_DIR="/opt/docker/nginx-proxy-manager/letsencrypt/live"
log_info "Ищем сертификат для ${XUI_DOMAIN}..."

# NPM называет папки по-разному — по домену или по числовому ID + домену
CERT_FOUND=""
for dir in "${LETSENCRYPT_DIR}"/*/; do
  if echo "$dir" | grep -qi "${XUI_DOMAIN}"; then
    CERT_FOUND="$dir"
    break
  fi
done

# Если не нашли по домену — ищем по fullchain.pem (берём самый свежий)
if [[ -z "$CERT_FOUND" ]]; then
  CERT_FOUND=$(find "${LETSENCRYPT_DIR}" -name "fullchain.pem" \
    -exec stat --format='%Y %n' {} \; 2>/dev/null | sort -rn | head -1 | awk '{print $2}' | xargs dirname 2>/dev/null || true)
fi

if [[ -n "$CERT_FOUND" && -f "${CERT_FOUND}/fullchain.pem" ]]; then
  cp "${CERT_FOUND}/fullchain.pem" /opt/docker/3x-ui/cert/fullchain.pem
  cp "${CERT_FOUND}/privkey.pem"   /opt/docker/3x-ui/cert/privkey.pem
  chmod 644 /opt/docker/3x-ui/cert/fullchain.pem
  chmod 600 /opt/docker/3x-ui/cert/privkey.pem
  log_ok "Сертификат скопирован: ${CERT_FOUND} → /opt/docker/3x-ui/cert/"
  log_info "Пути внутри контейнера для Panel Settings:"
  log_info "  Public key:  /root/cert/fullchain.pem"
  log_info "  Private key: /root/cert/privkey.pem"
else
  log_warn "Сертификат NPM ещё не создан — выполни шаги 1–3 выше, затем:"
  log_warn "  XUI_CERT_DIR=\$(ls ${LETSENCRYPT_DIR} | grep ${XUI_DOMAIN} | head -1)"
  log_warn "  cp ${LETSENCRYPT_DIR}/\${XUI_CERT_DIR}/fullchain.pem /opt/docker/3x-ui/cert/fullchain.pem"
  log_warn "  cp ${LETSENCRYPT_DIR}/\${XUI_CERT_DIR}/privkey.pem   /opt/docker/3x-ui/cert/privkey.pem"
fi

read -rp "$(echo -e "${BOLD}Настрой NPM Proxy Host и войди в панель → Enter:${NC} ")" _

stage_done 5 "3x-ui" \
  "cd /opt/docker/3x-ui && docker compose down
  (данные сохранены в /opt/docker/3x-ui/db/)"

fi  # END STAGE 5

# =============================================================================
#  ЭТАП 6 — HYSTERIA 2
# =============================================================================
if [[ "$START_STAGE" -le 6 ]]; then

log_step "ЭТАП 6 — Hysteria 2 (QUIC/UDP)"

HOME_DIR=$(getent passwd "$NEW_USER" | cut -d: -f6)
ACME="${HOME_DIR}/.acme.sh/acme.sh"
CERT_DIR="/opt/docker/hysteria2/cert"

# Убеждаемся что папка принадлежит пользователю ДО запуска acme.sh
chown -R "${NEW_USER}:${NEW_USER}" "${CERT_DIR}"

# ── DNS проверка ──────────────────────────────────────────────────────────────
wait_dns "${H2_DOMAIN}" "${SERVER_IP}"

# ── Установка acme.sh ─────────────────────────────────────────────────────────
log_section "6.1 — acme.sh"

if [[ -f "$ACME" ]]; then
  log_warn "acme.sh уже установлен"
else
  su - "$NEW_USER" -c "curl https://get.acme.sh | sh -s email=${LE_EMAIL}"
  log_ok "acme.sh установлен"
fi

# ── Сертификат ───────────────────────────────────────────────────────────────
log_section "6.2 — TLS-сертификат для ${H2_DOMAIN}"

CERT_OBTAINED=false

# Проверяем — может сертификат уже есть и действителен
if [[ -f "${CERT_DIR}/fullchain.pem" ]]; then
  EXPIRY=$(openssl x509 -in "${CERT_DIR}/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "?")
  log_warn "Сертификат уже существует (истекает: ${EXPIRY}) — пропускаю получение"
  CERT_OBTAINED=true
fi

if [[ "$CERT_OBTAINED" == "false" ]]; then
  # Acme challenge dir, который NPM отдаёт через port 80
  ACME_WEBROOT="/opt/docker/nginx-proxy-manager/data/letsencrypt-acme-challenge"
  mkdir -p "$ACME_WEBROOT"
  chown -R "${NEW_USER}:${NEW_USER}" "$ACME_WEBROOT"

  log_info "Пробуем webroot через NPM..."
  if su - "$NEW_USER" -c "
    ${ACME} --issue -d ${H2_DOMAIN} \
      --webroot ${ACME_WEBROOT} \
      --server letsencrypt --force 2>&1
  "; then
    log_ok "Сертификат получен через webroot"
    CERT_OBTAINED=true
  else
    log_warn "Webroot не сработал — пробуем standalone (NPM остановим на ~60 сек)"
    cd /opt/docker/nginx-proxy-manager && docker compose stop
    sleep 3

    if su - "$NEW_USER" -c "
      ${ACME} --issue -d ${H2_DOMAIN} \
        --standalone --httpport 80 \
        --server letsencrypt --force 2>&1
    "; then
      log_ok "Сертификат получен через standalone"
      CERT_OBTAINED=true
    fi

    cd /opt/docker/nginx-proxy-manager && docker compose up -d
    sleep 10
  fi
fi

[[ "$CERT_OBTAINED" == "true" ]] || die "Не удалось получить сертификат для ${H2_DOMAIN}. Убедись что DNS настроен и порт 80 открыт."

# ── Установка сертификата в нужное место ─────────────────────────────────────
log_section "6.3 — Установка сертификата"

# chown снова — acme.sh мог создать файлы от имени пользователя
chown -R "${NEW_USER}:${NEW_USER}" "${CERT_DIR}"

su - "$NEW_USER" -c "
  ${ACME} --install-cert -d ${H2_DOMAIN} \
    --cert-file     ${CERT_DIR}/cert.pem \
    --key-file      ${CERT_DIR}/key.pem \
    --fullchain-file ${CERT_DIR}/fullchain.pem \
    --reloadcmd 'docker restart hysteria2 2>/dev/null || true'
" && log_ok "Сертификат установлен в ${CERT_DIR}/"

[[ -f "${CERT_DIR}/fullchain.pem" ]] || die "Файл сертификата не найден в ${CERT_DIR}/"

# ── Конфиг ───────────────────────────────────────────────────────────────────
log_section "6.4 — Конфиг Hysteria 2"

cat > /opt/docker/hysteria2/config.yaml << EOF
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

cat > /opt/docker/hysteria2/docker-compose.yml << EOF
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
if docker ps --format '{{.Names}}' | grep -q "^hysteria2$"; then
  docker compose down
fi
docker compose up -d
sleep 10

docker ps --format '{{.Names}} {{.Status}}' | grep "hysteria2" | grep -q "Up" && \
  log_ok "Hysteria2 запущен" || log_warn "Hysteria2 не запустился — см. docker logs hysteria2"
ss -ulnp | grep -q ":${P_H2}" && log_ok "UDP ${P_H2} слушает" || \
  log_warn "UDP ${P_H2} не найден — проверь: docker logs hysteria2"

stage_done 6 "Hysteria 2" \
  "cd /opt/docker/hysteria2 && docker compose down
  ufw delete allow ${P_H2}/udp"

fi  # END STAGE 6

# =============================================================================
#  ЭТАП 7 — TELEMT MTProxy
# =============================================================================
if [[ "$START_STAGE" -le 7 ]]; then

log_step "ЭТАП 7 — Telemt MTProxy (Telegram)"

# Telemt FakeTLS: секрет для ссылки = ee + RAW_SECRET(32hex) + hex(tls_domain)
# tls_domain должен ТОЧНО совпадать с censorship.tls_domain в config.toml
TELEMT_TLS_DOMAIN="www.apple.com"
TELEMT_DOMAIN_HEX=$(python3 -c "print('${TELEMT_TLS_DOMAIN}'.encode().hex())")
TELEMT_LINK_SECRET="ee${TELEMT_SECRET}${TELEMT_DOMAIN_HEX}"
TELEMT_TG_LINK="tg://proxy?server=${SERVER_IP}&port=${P_TELEMT}&secret=${TELEMT_LINK_SECRET}"
TELEMT_HTTPS_LINK="https://t.me/proxy?server=${SERVER_IP}&port=${P_TELEMT}&secret=${TELEMT_LINK_SECRET}"

# ВАЖНО: config.toml пишем через python3, чтобы Telegram Desktop
# не мог повредить строку с доменом через markdown-конвертацию при копировании.
# Значение tls_domain не должно содержать www.example.com как гиперссылку.
python3 -c "
import sys
config = '''[general]
use_middle_proxy = true

[general.modes]
classic = false
secure  = false
tls     = true

[general.links]
show = \"*\"

[server]
port = ${P_TELEMT}

[censorship]
tls_domain = \"www.apple.com\"

[access.users]
main = \"${TELEMT_SECRET}\"
'''
with open('/opt/docker/telemt/config.toml', 'w') as f:
    f.write(config)
"

# Docker Compose для Telemt
# ВАЖНО: tmpfs убран — он конфликтовал с volumes (монтировал tmpfs поверх config.toml).
# Безопасность обеспечивается cap_drop + read_only + no-new-privileges.
cat > /opt/docker/telemt/docker-compose.yml << EOF
services:
  telemt:
    image: ghcr.io/telemt/telemt:latest
    container_name: telemt
    restart: unless-stopped
    ports:
      - "${P_TELEMT}:${P_TELEMT}"
    volumes:
      - /opt/docker/telemt/config.toml:/run/telemt/config.toml:ro
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
if docker ps --format '{{.Names}}' | grep -q "^telemt$"; then
  docker compose down
fi
docker compose pull
docker compose up -d
sleep 10

docker ps --format '{{.Names}} {{.Status}}' | grep "telemt" | grep -q "Up" && \
  log_ok "Telemt запущен" || log_warn "Telemt не запустился — см. docker logs telemt"

echo ""
log_info "Telegram MTProxy ссылки:"
echo -e "  ${CYAN}${TELEMT_TG_LINK}${NC}"
echo -e "  ${CYAN}${TELEMT_HTTPS_LINK}${NC}"

stage_done 7 "Telemt MTProxy" \
  "cd /opt/docker/telemt && docker compose down
  ufw delete allow ${P_TELEMT}/tcp"

fi  # END STAGE 7

# =============================================================================
#  ИТОГОВАЯ СВОДКА
# =============================================================================
log_step "УСТАНОВКА ЗАВЕРШЕНА"

# Формируем правильную FakeTLS ссылку (на случай если переменные живы)
TELEMT_TLS_DOMAIN="www.apple.com"
TELEMT_DOMAIN_HEX=$(python3 -c "print('${TELEMT_TLS_DOMAIN}'.encode().hex())" 2>/dev/null || echo "")
TELEMT_LINK_SECRET="ee${TELEMT_SECRET}${TELEMT_DOMAIN_HEX}"
TELEMT_TG_LINK="tg://proxy?server=${SERVER_IP}&port=${P_TELEMT}&secret=${TELEMT_LINK_SECRET}"

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║                   ИТОГ УСТАНОВКИ                           ║${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║  SSH${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${CYAN}ssh -p ${SSH_PORT} ${NEW_USER}@${SERVER_IP}${NC}"
echo -e "${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║  ПАНЕЛИ${NC}"
echo -e "${BOLD}${GREEN}║${NC}  NPM:   ${CYAN}https://${NPM_DOMAIN}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  3x-ui: ${CYAN}https://${XUI_DOMAIN}${NC}  (admin / admin → смени через x-ui CLI)"
echo -e "${BOLD}${GREEN}║${NC}  Сайт:  ${CYAN}https://${ROOT_DOMAIN}${NC}"
echo -e "${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║  Смена логина/пароля 3x-ui:${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${CYAN}docker exec -it 3x-ui x-ui${NC}  → пункт 7"
echo -e "${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║  VPN${NC}"
echo -e "${BOLD}${GREEN}║${NC}  VLESS-Reality : ${YELLOW}${SERVER_IP}:${P_VLESS_REALITY}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  VLESS-XHTTP   : ${YELLOW}${SERVER_IP}:${P_VLESS_XHTTP}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Trojan        : ${YELLOW}${SERVER_IP}:${P_TROJAN}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Shadowsocks   : ${YELLOW}${SERVER_IP}:${P_SS}${NC}"
echo -e "${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║  HYSTERIA 2${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${YELLOW}${H2_DOMAIN}:${P_H2}${NC} (UDP)"
echo -e "${BOLD}${GREEN}║${NC}  Пароль: ${YELLOW}${H2_PASS}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  URI: ${CYAN}hysteria2://${H2_PASS}@${H2_DOMAIN}:${P_H2}?sni=${H2_DOMAIN}#H2${NC}"
echo -e "${BOLD}${GREEN}║${NC}"
echo -e "${BOLD}${GREEN}║  TELEGRAM MTProxy (FakeTLS)${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Сервер:  ${YELLOW}${SERVER_IP}:${P_TELEMT}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  Секрет:  ${YELLOW}${TELEMT_LINK_SECRET}${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${CYAN}${TELEMT_TG_LINK}${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║  КОНТЕЙНЕРЫ${NC}"
docker ps --format "  {{.Names}}: {{.Status}}" 2>/dev/null || true
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║  ПАМЯТЬ${NC}"
docker stats --no-stream --format "  {{.Name}}: {{.MemUsage}}" 2>/dev/null || true
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"

# ── Сохраняем сводку в файл ───────────────────────────────────────────────────
SUMMARY_FILE="/root/vps-setup-summary.txt"
{
  echo "=== VPS SETUP SUMMARY — $(date) ==="
  echo ""
  echo "SSH: ssh -p ${SSH_PORT} ${NEW_USER}@${SERVER_IP}"
  echo ""
  echo "--- Panels ---"
  echo "NPM:          https://${NPM_DOMAIN}"
  echo "3x-ui:        https://${XUI_DOMAIN}"
  echo "  Логин/пароль менять через: docker exec -it 3x-ui x-ui  (пункт 7)"
  echo "Site:         https://${ROOT_DOMAIN}"
  echo ""
  echo "--- Сертификаты для 3x-ui (inbounds) ---"
  echo "Public key:  /root/cert/fullchain.pem  (внутри контейнера)"
  echo "Private key: /root/cert/privkey.pem   (внутри контейнера)"
  echo "На хосте: /opt/docker/3x-ui/cert/"
  echo ""
  echo "--- VPN Ports ---"
  echo "VLESS-Reality: ${SERVER_IP}:${P_VLESS_REALITY}"
  echo "VLESS-XHTTP:   ${SERVER_IP}:${P_VLESS_XHTTP}"
  echo "Trojan:        ${SERVER_IP}:${P_TROJAN}"
  echo "Shadowsocks:   ${SERVER_IP}:${P_SS}"
  echo ""
  echo "--- Hysteria2 ---"
  echo "Server:  ${H2_DOMAIN}:${P_H2} (UDP)"
  echo "Pass:    ${H2_PASS}"
  echo "URI:     hysteria2://${H2_PASS}@${H2_DOMAIN}:${P_H2}?sni=${H2_DOMAIN}#H2"
  echo ""
  echo "--- Telemt FakeTLS ---"
  echo "Сервер:  ${SERVER_IP}:${P_TELEMT}"
  echo "Секрет:  ${TELEMT_LINK_SECRET}"
  echo "Ссылка:  ${TELEMT_TG_LINK}"
  echo ""
  echo "--- Полезные команды ---"
  echo "docker exec -it 3x-ui x-ui           # CLI панели 3x-ui"
  echo "docker logs nginx-proxy-manager -f    # логи NPM"
  echo "docker logs 3x-ui -f                 # логи 3x-ui"
  echo "docker logs hysteria2 -f             # логи Hysteria2"
  echo "docker logs telemt -f                # логи Telemt"
  echo "docker stats --no-stream             # потребление памяти"
  echo "ufw status verbose                   # статус брандмауэра"
  echo "fail2ban-client status sshd          # статус Fail2Ban"
} > "$SUMMARY_FILE"
chmod 600 "$SUMMARY_FILE"

save_state "done"

echo ""
log_ok "Сводка сохранена в ${SUMMARY_FILE}"
log_warn "Удали файл после сохранения данных в менеджер паролей:"
echo -e "  ${RED}rm ${SUMMARY_FILE}${NC}"
echo -e "  ${RED}rm /root/.vps-setup-vars${NC}"
