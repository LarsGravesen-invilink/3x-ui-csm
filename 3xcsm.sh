#!/bin/bash
# ===========================================================================
# 3X-UI CSM - CLI Subscription Manager
# ===========================================================================
#
# Автор: LarsGravesen
# Версия: 1.0
# Telegram: https://t.me/LarsInvilink
#
# Скрипт для сбора VPN-ключей с панелей 3x-UI,
# объединения в единый RAW-файл подписки (base64),
# с автообновлением по расписанию (cron).
#
# Требования: 3x-UI v2.4.0+ (рекомендуется v2.5.0+)
# Поддержка: HTTP/HTTPS, self-signed SSL, Let's Encrypt
#
# Запуск: 3xsub (после установки)
# ===========================================================================

readonly VERSION="1.0"
readonly AUTHOR="LarsGravesen"
readonly TELEGRAM="https://t.me/LarsInvilink"
readonly PROJECT_NAME="3X-UI CSM"
readonly MIN_3XUI_VERSION="2.4.0"
readonly RECOMMENDED_3XUI_VERSION="2.5.0"
readonly BASE_DIR="/opt/3xcsm"
readonly SERVERS_FILE="${BASE_DIR}/servers.json"
readonly CONFIG_FILE="${BASE_DIR}/config.json"
readonly WEB_DIR="/var/www/3xcsm"
readonly DEFAULT_SUB_FILENAME="sub.txt"
readonly RAW_FILE="${BASE_DIR}/raw_keys.txt"
readonly LOG_FILE="${BASE_DIR}/3xcsm.log"
readonly COOKIE_DIR="${BASE_DIR}/cookies"
readonly SUBUP_CMD="/usr/local/bin/3xsub"
readonly NGINX_CONF="/etc/nginx/sites-available/3xcsm"
readonly NGINX_LINK="/etc/nginx/sites-enabled/3xcsm"
readonly CRON_MARKER="# SUBUP_AUTO_UPDATE"
readonly LINE_WIDTH=62
readonly CURL_CONNECT_TIMEOUT=15
readonly CURL_MAX_TIME=30

readonly WHITE='\033[1;37m'
readonly GREEN='\033[1;32m'
readonly RED='\033[1;31m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[1;36m'
readonly BLUE='\033[1;34m'
readonly MAGENTA='\033[1;35m'
readonly GRAY='\033[0;37m'
readonly DARK_GRAY='\033[0;37m'
readonly NC='\033[0m'
readonly BG_GREEN='\033[42m'
readonly BG_RED='\033[41m'
readonly BG_BLUE='\033[44m'
readonly BG_CYAN='\033[46m'

clear_screen() {
    clear
}

print_line() {
    echo -e "${CYAN}$(printf '═%.0s' $(seq 1 $LINE_WIDTH))${NC}"
}

print_thin_line() {
    echo -e "${DARK_GRAY}$(printf '─%.0s' $(seq 1 $LINE_WIDTH))${NC}"
}

print_double_line() {
    echo -e "${MAGENTA}$(printf '▀%.0s' $(seq 1 $LINE_WIDTH))${NC}"
}

print_logo() {
    echo ""
    echo -e "${CYAN}  ██████╗ ${MAGENTA}██╗  ██╗${WHITE}    ██╗   ██╗██╗  ${CYAN} ██████╗███████╗███╗   ███╗${NC}"
    echo -e "${CYAN}  ╚════██╗${MAGENTA}╚██╗██╔╝${WHITE}    ██║   ██║██║  ${CYAN}██╔════╝██╔════╝████╗ ████║${NC}"
    echo -e "${CYAN}   █████╔╝${MAGENTA} ╚███╔╝ ${WHITE}    ██║   ██║██║  ${CYAN}██║     ███████╗██╔████╔██║${NC}"
    echo -e "${CYAN}   ╚═══██╗${MAGENTA} ██╔██╗ ${WHITE}    ██║   ██║██║  ${CYAN}██║     ╚════██║██║╚██╔╝██║${NC}"
    echo -e "${CYAN}  ██████╔╝${MAGENTA}██╔╝ ██╗${WHITE}    ╚██████╔╝██║  ${CYAN}╚██████╗███████║██║ ╚═╝ ██║${NC}"
    echo -e "${CYAN}  ╚═════╝ ${MAGENTA}╚═╝  ╚═╝${WHITE}     ╚═════╝ ╚═╝  ${CYAN} ╚═════╝╚══════╝╚═╝     ╚═╝${NC}"
    echo ""
}

print_header() {
    clear_screen
    print_logo
    
    local info_line="v${VERSION} │ ${AUTHOR} │ ${TELEGRAM}"
    local pad=$(( (LINE_WIDTH - ${#info_line} + 8) / 2 ))
    
    print_double_line
    printf "${DARK_GRAY}%*s${WHITE}v${VERSION}${DARK_GRAY} │ ${GRAY}${AUTHOR}${DARK_GRAY} │ ${CYAN}${TELEGRAM}${NC}\n" $((pad - 5)) ""
    print_double_line
    echo ""
}

print_section_header() {
    local title="$1"
    local title_len=${#title}
    local pad=$(( (LINE_WIDTH - title_len - 4) / 2 ))
    
    echo ""
    echo -e "${CYAN}┌$(printf '─%.0s' $(seq 1 $((LINE_WIDTH - 2))))┐${NC}"
    printf "${CYAN}│${NC}%*s${WHITE}${title}%*s${CYAN}│${NC}\n" $((pad)) "" $((LINE_WIDTH - pad - title_len - 2)) ""
    echo -e "${CYAN}└$(printf '─%.0s' $(seq 1 $((LINE_WIDTH - 2))))┘${NC}"
    echo ""
}

msg_ok() {
    echo -e "  ${GREEN}✔${NC} ${WHITE}$1${NC}"
}

msg_err() {
    echo -e "  ${RED}✘${NC} ${WHITE}$1${NC}"
}

msg_info() {
    echo -e "  ${CYAN}ℹ${NC} ${GRAY}$1${NC}"
}

msg_warn() {
    echo -e "  ${YELLOW}⚠${NC} ${YELLOW}$1${NC}"
}

msg_hint() {
    echo -e "  ${DARK_GRAY}💡 $1${NC}"
}

DEBUG=${DEBUG:-0}
debug_log() {
    if [[ "$DEBUG" == "1" ]]; then
        echo -e "  ${DARK_GRAY}[DEBUG] $1${NC}" >&2
    fi
}

progress_bar() {
    local current=$1
    local total=$2
    local desc="$3"
    local width=40
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    local bar_filled=$(printf '█%.0s' $(seq 1 $filled) 2>/dev/null)
    local bar_empty=$(printf '░%.0s' $(seq 1 $empty) 2>/dev/null)
    
    local color="${CYAN}"
    [[ $percent -ge 50 ]] && color="${BLUE}"
    [[ $percent -ge 80 ]] && color="${GREEN}"
    [[ $percent -eq 100 ]] && color="${GREEN}"
    
    printf "\r  ${color}${bar_filled}${DARK_GRAY}${bar_empty}${NC} ${WHITE}%3d%%${NC} ${GRAY}%s${NC}%-20s" "$percent" "$desc" ""
}

progress_done() {
    local desc="$1"
    printf "\r  ${GREEN}$(printf '█%.0s' $(seq 1 40))${NC} ${GREEN}100%%${NC} ${WHITE}%s${NC}%-20s\n" "$desc" ""
}

SPIN_PID=""
spin_start() {
    local msg="$1"
    (
        local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        while true; do
            for (( i=0; i<${#chars}; i++ )); do
                printf "\r  ${CYAN}${chars:$i:1}${NC} ${WHITE}%s${NC}" "$msg"
                sleep 0.1
            done
        done
    ) &
    SPIN_PID=$!
    disown $SPIN_PID 2>/dev/null
}

spin_stop() {
    if [[ -n "$SPIN_PID" ]]; then
        kill $SPIN_PID 2>/dev/null
        wait $SPIN_PID 2>/dev/null
        SPIN_PID=""
        printf "\r%-70s\r" " "
    fi
}

pause_key() {
    echo ""
    echo -ne "  ${DARK_GRAY}Нажмите Enter для продолжения...${NC}"
    read -r
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        msg_err "Скрипт необходимо запускать от имени root!"
        msg_info "Используйте: sudo bash $0"
        exit 1
    fi
}

check_dependencies() {
    local deps=("curl" "jq" "nginx" "crontab" "base64" "nano" "qrencode" "openssl")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            return 1
        fi
    done
    return 0
}

check_3xui_version() {
    local panel_address="$1"
    local panel_port="$2"
    local protocol="$3"
    local web_path="$4"
    local cookie_file="$5"
    
    # Пробуем получить версию через API
    local base_url
    base_url=$(build_panel_url "$panel_address" "$panel_port" "$web_path" "$protocol")
    
    # Версия может быть в разных местах
    local version_endpoints=(
        "/server/status"
        "/xui/API/server/status"
        "/panel/api/server/status"
    )
    
    for endpoint in "${version_endpoints[@]}"; do
        local response
        response=$(curl -sS -k -L \
            -b "$cookie_file" \
            -H "Accept: application/json" \
            --connect-timeout 5 \
            --max-time 10 \
            "${base_url}${endpoint}" 2>/dev/null)
        
        local version
        version=$(echo "$response" | jq -r '.obj.xray.version // .obj.appVersion // empty' 2>/dev/null)
        
        if [[ -n "$version" && "$version" != "null" ]]; then
            echo "$version"
            return 0
        fi
    done
    
    echo "unknown"
    return 1
}

version_compare() {
    local v1="$1"
    local v2="$2"
    
    if [[ "$v1" == "$v2" ]]; then
        return 0
    fi
    
    local IFS=.
    local i v1_arr=($v1) v2_arr=($v2)
    
    for ((i=0; i<${#v1_arr[@]} || i<${#v2_arr[@]}; i++)); do
        local n1=${v1_arr[i]:-0}
        local n2=${v2_arr[i]:-0}
        
        if ((n1 > n2)); then
            return 0
        elif ((n1 < n2)); then
            return 1
        fi
    done
    
    return 0
}

print_installer_header() {
    clear_screen
    echo ""
    echo -e "${CYAN}  ══════════════════════════════════════════════════${NC}"
    echo -e "  ${WHITE}       3X-UI CSM - Subscription Manager${NC}"
    echo -e "${CYAN}  ══════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GRAY}Автор:${NC}     ${WHITE}LarsGravesen${NC}"
    echo -e "  ${GRAY}Версия:${NC}    ${GREEN}${VERSION}${NC}"
    echo -e "  ${GRAY}Telegram:${NC}  ${CYAN}https://t.me/LarsInvilink${NC}"
    echo ""
    echo -e "${CYAN}  ──────────────────────────────────────────────────${NC}"
    echo -e "  ${GRAY}Скрипт для сбора VPN-ключей с панелей 3x-UI,${NC}"
    echo -e "  ${GRAY}объединения в RAW-файл подписки (base64)${NC}"
    echo -e "  ${GRAY}с автообновлением по расписанию cron.${NC}"
    echo ""
    echo -e "${CYAN}  ──────────────────────────────────────────────────${NC}"
    echo -e "  ${YELLOW}Требования:${NC} 3x-UI v${MIN_3XUI_VERSION}+ (рек. v${RECOMMENDED_3XUI_VERSION}+)"
    echo -e "  ${GRAY}Поддержка:${NC}  HTTP/HTTPS, SSL, Let's Encrypt"
    echo ""
    echo -e "${CYAN}  ──────────────────────────────────────────────────${NC}"
    echo -e "  ${WHITE}Возможности:${NC}"
    echo -e "  ${GREEN}*${NC} Добавление и редактирование серверов"
    echo -e "  ${GREEN}*${NC} Выбор инбаундов для каждого сервера"
    echo -e "  ${GREEN}*${NC} Сбор VPN-ключей и формирование подписки"
    echo -e "  ${GREEN}*${NC} VLESS, VMess, Trojan, Shadowsocks, Hysteria2"
    echo -e "  ${GREEN}*${NC} Base64-кодирование файла подписки"
    echo -e "  ${GREEN}*${NC} Автообновление: минуты / часы / дни"
    echo -e "  ${GREEN}*${NC} Раздача через Nginx (HTTP / HTTPS)"
    echo -e "  ${GREEN}*${NC} Обзор подписки и диагностика"
    echo -e "  ${GREEN}*${NC} Домен и SSL Let's Encrypt"
    echo -e "  ${GREEN}*${NC} Полное удаление и сброс настроек"
    echo ""
    echo -e "${CYAN}  ──────────────────────────────────────────────────${NC}"
    echo -e "  ${GRAY}Запуск:${NC} ${WHITE}3xsub${NC}"
    echo -e "${CYAN}  ══════════════════════════════════════════════════${NC}"
    echo ""
}

show_welcome_screen() {
    print_installer_header
    
    echo ""
    echo -ne "  ${GREEN}➜${NC}  ${WHITE}Нажмите ${GREEN}ENTER${NC}${WHITE} для продолжения или ${RED}Ctrl+C${NC}${WHITE} для выхода...${NC}"
    read -r
    
    print_installer_header
    
    echo ""
    echo -e "  ${CYAN}>>>${NC} ${WHITE}Установщик CLI SUBSCRIPTION MANAGER${NC} ${CYAN}<<<${NC}"
    echo ""
    echo ""
    
    echo -e "  ${WHITE}Будут установлены/проверены следующие компоненты:${NC}"
    echo ""
    printf "  ${GRAY}%-50s${NC}\n" "$(printf '%.0s-' {1..50})"
    printf "  ${GREEN}+${NC} ${WHITE}%-10s${NC} ${GRAY}%-37s${NC}\n" "curl"    "HTTP-клиент для работы с API"
    printf "  ${GREEN}+${NC} ${WHITE}%-10s${NC} ${GRAY}%-37s${NC}\n" "jq"      "Парсер JSON для обработки данных"
    printf "  ${GREEN}+${NC} ${WHITE}%-10s${NC} ${GRAY}%-37s${NC}\n" "nginx"   "Веб-сервер для раздачи подписки"
    printf "  ${GREEN}+${NC} ${WHITE}%-10s${NC} ${GRAY}%-37s${NC}\n" "cron"    "Планировщик для автообновления"
    printf "  ${GREEN}+${NC} ${WHITE}%-10s${NC} ${GRAY}%-37s${NC}\n" "certbot" "Получение SSL-сертификатов"
    printf "  ${GREEN}+${NC} ${WHITE}%-10s${NC} ${GRAY}%-37s${NC}\n" "nano"    "Текстовый редактор"
    printf "  ${GREEN}+${NC} ${WHITE}%-10s${NC} ${GRAY}%-37s${NC}\n" "base64"  "Кодирование/декодирование данных"
    printf "  ${GREEN}+${NC} ${WHITE}%-10s${NC} ${GRAY}%-37s${NC}\n" "qrencode" "Генерация QR-кодов в терминале"
    printf "  ${GREEN}+${NC} ${WHITE}%-10s${NC} ${GRAY}%-37s${NC}\n" "openssl"  "Шифрование данных серверов"
    printf "  ${GRAY}%-50s${NC}\n" "$(printf '%.0s-' {1..50})"
    echo ""
    
    echo -e "  ${WHITE}Также будут созданы:${NC}"
    echo ""
    printf "  ${GRAY}%-50s${NC}\n" "$(printf '%.0s-' {1..50})"
    printf "  ${CYAN}>${NC} ${WHITE}%-16s${NC} ${GRAY}%-31s${NC}\n" "${BASE_DIR}" "Директория конфигурации"
    printf "  ${CYAN}>${NC} ${WHITE}%-16s${NC} ${GRAY}%-31s${NC}\n" "${WEB_DIR}" "Директория веб-сервера"
    printf "  ${CYAN}>${NC} ${WHITE}%-16s${NC} ${GRAY}%-31s${NC}\n" "3xsub" "Команда быстрого запуска"
    printf "  ${GRAY}%-50s${NC}\n" "$(printf '%.0s-' {1..50})"
    echo ""
    
    echo -e "  ${RED}Порты, которые должны быть свободны:${NC}"
    echo ""
    printf "  ${RED}%-50s${NC}\n" "$(printf '%.0s-' {1..50})"
    printf "  ${RED}>${NC} ${WHITE}%-6s${NC} ${RED}%-41s${NC}\n" "80"   "HTTP, для получения SSL-сертификата"
    printf "  ${RED}>${NC} ${WHITE}%-6s${NC} ${RED}%-41s${NC}\n" "443"  "HTTPS, если используется домен с SSL"
    printf "  ${RED}>${NC} ${WHITE}%-6s${NC} ${RED}%-41s${NC}\n" "8443" "По умолчанию для раздачи подписки"
    echo ""
    printf "  ${YELLOW}!${NC} ${WHITE}%-47s${NC}\n" "Если порты заняты другими сервисами"
    printf "    ${WHITE}%-47s${NC}\n" "(Apache, Caddy и т.д.) - возможны конфликты."
    printf "    ${WHITE}%-47s${NC}\n" "При установке можно указать другой порт."
    printf "  ${RED}%-50s${NC}\n" "$(printf '%.0s-' {1..50})"
    echo ""

    print_thin_line
    echo ""
    echo -e "  ${YELLOW}⚠${NC}  ${WHITE}Скрипт требует прав root и выполняет установку пакетов через apt.${NC}"
    echo ""
    echo -ne "  ${GREEN}➜${NC}  ${WHITE}Нажмите ${GREEN}ENTER${NC}${WHITE} для начала установки или ${RED}Ctrl+C${NC}${WHITE} для отмены...${NC}"
    read -r
}

install_dependencies() {
    # Показываем начальный экран приветствия
    show_welcome_screen
    
    # Экран установки пакетов
    print_installer_header
    
    echo ""
    echo -e "  ${CYAN}>>>${NC} ${WHITE}УСТАНОВКА КОМПОНЕНТОВ${NC} ${CYAN}<<<${NC}"
    echo ""
    echo ""
    
    local total_steps=11
    local current_step=0
    
    # --- Шаг 1: Обновление пакетов ---
    current_step=$((current_step + 1))
    echo ""
    progress_bar $current_step $total_steps "Обновление списка пакетов..."
    apt-get update -qq > /dev/null 2>&1
    progress_bar $current_step $total_steps "Список пакетов обновлён"
    sleep 0.3
    
    # --- Шаг 2: curl ---
    current_step=$((current_step + 1))
    progress_bar $current_step $total_steps "Установка curl..."
    if ! command -v curl &>/dev/null; then
        apt-get install -y -qq curl > /dev/null 2>&1
    fi
    progress_bar $current_step $total_steps "curl готов"
    sleep 0.2
    
    # --- Шаг 3: jq ---
    current_step=$((current_step + 1))
    progress_bar $current_step $total_steps "Установка jq..."
    if ! command -v jq &>/dev/null; then
        apt-get install -y -qq jq > /dev/null 2>&1
    fi
    progress_bar $current_step $total_steps "jq готов"
    sleep 0.2
    
    # --- Шаг 4: nginx ---
    current_step=$((current_step + 1))
    progress_bar $current_step $total_steps "Установка Nginx..."
    if ! command -v nginx &>/dev/null; then
        apt-get install -y -qq nginx > /dev/null 2>&1
    fi
    progress_bar $current_step $total_steps "Nginx готов"
    sleep 0.2
    
    # --- Шаг 5: cron ---
    current_step=$((current_step + 1))
    progress_bar $current_step $total_steps "Установка cron..."
    if ! command -v crontab &>/dev/null; then
        apt-get install -y -qq cron > /dev/null 2>&1
    fi
    systemctl enable cron > /dev/null 2>&1
    systemctl start cron > /dev/null 2>&1
    progress_bar $current_step $total_steps "cron готов"
    sleep 0.2
    
    # --- Шаг 6: certbot (для SSL) ---
    current_step=$((current_step + 1))
    progress_bar $current_step $total_steps "Установка Certbot..."
    if ! command -v certbot &>/dev/null; then
        apt-get install -y -qq certbot python3-certbot-nginx > /dev/null 2>&1
    fi
    progress_bar $current_step $total_steps "Certbot готов"
    sleep 0.2
    
    current_step=$((current_step + 1))
    progress_bar $current_step $total_steps "Установка qrencode..."
    if ! command -v qrencode &>/dev/null; then
        apt-get install -y -qq qrencode > /dev/null 2>&1
    fi
    progress_bar $current_step $total_steps "qrencode готов"
    sleep 0.2
    
    # --- Шаг 8: Создание директорий ---
    current_step=$((current_step + 1))
    progress_bar $current_step $total_steps "Создание директорий..."
    mkdir -p "$BASE_DIR" "$COOKIE_DIR" "$WEB_DIR" 2>/dev/null
    chmod 700 "$BASE_DIR" "$COOKIE_DIR"
    chmod 755 "$WEB_DIR"
    progress_bar $current_step $total_steps "Директории созданы"
    sleep 0.2
    
    # --- Шаг 8: Инициализация конфигов ---
    current_step=$((current_step + 1))
    progress_bar $current_step $total_steps "Инициализация конфигурации..."
    
    if [[ ! -f "$SERVERS_FILE" ]]; then
        echo '[]' > "$SERVERS_FILE"
    fi
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" <<EOJSON
{
    "update_interval": "59",
    "update_unit": "minutes",
    "sub_title": "3X-UI-CSM-SUB",
    "client_update_interval": "12",
    "support_url": "https://t.me/LarsInvilink",
    "sub_upload": "0",
    "sub_download": "0",
    "sub_total": "0",
    "sub_expire": "1798761600",
    "header_profile_title": "true",
    "header_profile_update_interval": "true",
    "header_support_url": "false",
    "header_profile_web_page_url": "false",
    "header_subscription_userinfo": "false",
    "web_port": "8443",
    "use_domain": "false",
    "domain": "",
    "use_ssl": "false",
    "encode_url": "false",
    "encoded_path": "",
    "installed": "true"
}
EOJSON
    fi
    progress_bar $current_step $total_steps "Конфигурация готова"
    sleep 0.2
    
    # --- Шаг 9: Команда 3xsub ---
    current_step=$((current_step + 1))
    progress_bar $current_step $total_steps "Создание команды 3xsub..."
    
    cp -f "$(realpath "$0" 2>/dev/null || echo "$0")" "${BASE_DIR}/3xcsm.sh" 2>/dev/null
    chmod +x "${BASE_DIR}/3xcsm.sh" 2>/dev/null
    
    cat > "$SUBUP_CMD" <<'SUBCMD'
#!/bin/bash
exec bash /opt/3xcsm/3xcsm.sh --menu "$@"
SUBCMD
    chmod +x "$SUBUP_CMD"
    progress_bar $current_step $total_steps "Команда 3xsub создана"
    sleep 0.2
    
    # --- Шаг 10: Финализация ---
    current_step=$((current_step + 1))
    progress_done "Установка компонентов завершена!"
    
    sleep 1
    
    # Запрос настроек домена и SSL
    setup_domain_and_ssl
    
    # Настройка Nginx
    setup_nginx_config
    
    # Финальный вывод
    show_installation_complete
}

setup_domain_and_ssl() {
    local use_domain="false"
    local domain=""
    local use_ssl="false"
    local encode_url="false"
    local encoded_path=""
    local web_port="8443"
    
    local server_ip
    server_ip=$(curl -4 -s --connect-timeout 5 ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "ВАШ_IP")
    
    # ═══════════════════════════════════════════════════════════════════════════
    # ШАГ 1: ВОПРОС О ДОМЕНЕ
    # ═══════════════════════════════════════════════════════════════════════════
    print_installer_header
    
    echo ""
    echo -e "  ${CYAN}>>>${NC} ${WHITE}НАСТРОЙКА ДОСТУПА К ПОДПИСКЕ${NC} ${CYAN}<<<${NC}"
    echo -e "  ${GRAY}Шаг 1 из 6: Домен${NC}"
    echo ""
    echo ""
    
    echo -e "  ${WHITE}IP-адрес вашего сервера:${NC} ${CYAN}${server_ip}${NC}"
    echo ""
    print_thin_line
    echo ""
    
    echo -e "  ${WHITE}Использовать домен вместо IP для подписки?${NC}"
    echo ""
    msg_hint "Домен удобнее для пользователей и позволяет использовать HTTPS"
    msg_hint "Если у вас нет домена — выберите 'n' и будет использован IP"
    echo ""
    echo -ne "  ${GREEN}➜${NC}  ${WHITE}Использовать домен? (y/n) [n]: ${NC}"
    read -r use_domain_answer
    
    if [[ "$use_domain_answer" =~ ^[Yy]$ ]]; then
        use_domain="true"
        
        # ═══════════════════════════════════════════════════════════════════════
        # ШАГ 1.1: ВВОД ДОМЕНА
        # ═══════════════════════════════════════════════════════════════════════
        print_installer_header
        
        echo ""
        echo -e "  ${CYAN}>>>${NC} ${WHITE}НАСТРОЙКА ДОСТУПА К ПОДПИСКЕ${NC} ${CYAN}<<<${NC}"
        echo -e "  ${GRAY}Шаг 2 из 6: Ввод домена${NC}"
        echo ""
        echo ""
        
        echo -e "  ${WHITE}Введите ваш домен для подписки:${NC}"
        echo ""
        msg_hint "Примеры: sub.example.com, vpn.mydomain.ru, subs.mysite.org"
        msg_hint "Домен должен быть направлен (A-запись) на IP: ${server_ip}"
        echo ""
        echo -ne "  ${GREEN}➜${NC}  ${WHITE}Домен: ${NC}"
        read -r domain
        
        if [[ -z "$domain" ]]; then
            msg_warn "Домен не указан, будет использован IP-адрес"
            use_domain="false"
            sleep 1
        else
            # ═══════════════════════════════════════════════════════════════════
            # ШАГ 1.2: ВОПРОС О SSL
            # ═══════════════════════════════════════════════════════════════════
            print_installer_header
            
            echo ""
            echo -e "  ${CYAN}>>>${NC} ${WHITE}НАСТРОЙКА SSL-СЕРТИФИКАТА${NC} ${CYAN}<<<${NC}"
            echo -e "  ${GRAY}Шаг 3 из 6: SSL для ${domain}${NC}"
            echo ""
            echo ""
            
            echo -e "  ${WHITE}Домен:${NC} ${CYAN}${domain}${NC}"
            echo ""
            print_thin_line
            echo ""
            
            echo -e "  ${WHITE}Настроить бесплатный SSL-сертификат (Let's Encrypt)?${NC}"
            echo ""
            msg_hint "HTTPS защищает данные и выглядит профессиональнее"
            msg_hint "Требуется: домен должен быть направлен на этот сервер"
            msg_hint "Сертификат будет автоматически обновляться"
            echo ""
            echo -ne "  ${GREEN}➜${NC}  ${WHITE}Установить SSL? (y/n) [y]: ${NC}"
            read -r use_ssl_answer
            
            if [[ ! "$use_ssl_answer" =~ ^[Nn]$ ]]; then
                use_ssl="true"
                web_port="443"
            else
                echo ""
                echo -ne "  ${GREEN}➜${NC}  ${WHITE}Порт для HTTP [80]: ${NC}"
                read -r custom_port
                [[ -n "$custom_port" ]] && web_port="$custom_port" || web_port="80"
            fi
        fi
    fi
    
    # Если домен не используется — запрашиваем порт
    if [[ "$use_domain" == "false" ]]; then
        print_installer_header
        
        echo ""
        echo -e "  ${CYAN}>>>${NC} ${WHITE}НАСТРОЙКА ДОСТУПА К ПОДПИСКЕ${NC} ${CYAN}<<<${NC}"
        echo -e "  ${GRAY}Шаг 2 из 6: Порт сервера${NC}"
        echo ""
        echo ""
        
        echo -e "  ${WHITE}Подписка будет доступна по адресу:${NC}"
        echo -e "  ${CYAN}  http://${server_ip}:<порт>/sub.txt${NC}"
        echo ""
        print_thin_line
        echo ""
        msg_hint "Стандартный порт: 8443 (не конфликтует с другими сервисами)"
        msg_hint "Можно использовать любой свободный порт"
        echo ""
        echo -ne "  ${GREEN}➜${NC}  ${WHITE}Порт для раздачи подписки [8443]: ${NC}"
        read -r custom_port
        [[ -n "$custom_port" ]] && web_port="$custom_port"
    fi
    
    # ═══════════════════════════════════════════════════════════════════════════
    # ШАГ 2: КОДИРОВАНИЕ URL
    # ═══════════════════════════════════════════════════════════════════════════
    print_installer_header
    
    echo ""
    echo -e "  ${CYAN}>>>${NC} ${WHITE}ЗАЩИТА ССЫЛКИ ПОДПИСКИ${NC} ${CYAN}<<<${NC}"
    echo -e "  ${GRAY}Шаг 4 из 6: Кодирование URL${NC}"
    echo ""
    echo ""
    
    echo -e "  ${WHITE}Закодировать путь к подписке в base64?${NC}"
    echo ""
    echo -e "  ${GRAY}Обычный путь:${NC}      ${WHITE}/sub.txt${NC}"
    echo -e "  ${GRAY}Закодированный:${NC}   ${WHITE}/aHR0cHM6Ly9leGFtcGxl...${NC}"
    echo ""
    print_thin_line
    echo ""
    msg_hint "Закодированный путь сложнее угадать — дополнительная защита"
    msg_hint "Рекомендуется включить, если подписка должна быть приватной"
    echo ""
    echo -ne "  ${GREEN}➜${NC}  ${WHITE}Закодировать путь? (y/n) [n]: ${NC}"
    read -r encode_answer
    
    if [[ "$encode_answer" =~ ^[Yy]$ ]]; then
        encode_url="true"
        # Генерируем случайный путь и кодируем в base64
        local random_string
        random_string=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 16)
        encoded_path=$(echo -n "$random_string" | base64 | tr -d '=' | tr '+/' '-_')
        msg_ok "Путь будет закодирован: /${encoded_path}"
        sleep 1
    fi
    
   
    print_installer_header
    
    echo ""
    echo -e "  ${CYAN}>>>${NC} ${WHITE}ИМЯ ФАЙЛА ПОДПИСКИ${NC} ${CYAN}<<<${NC}"
    echo -e "  ${GRAY}Шаг 5 из 6: Имя файла${NC}"
    echo ""
    echo ""
    
    local sub_filename="${DEFAULT_SUB_FILENAME%.txt}"
    
    echo -e "  ${WHITE}Укажите имя файла подписки:${NC}"
    echo ""
    msg_hint "По умолчанию: ${DEFAULT_SUB_FILENAME%.txt}"
    msg_hint "Введите только имя файла БЕЗ расширения .txt"
    msg_hint "Примеры: mykeys, vpn, config"
    msg_hint "Пустой Enter — оставить значение по умолчанию"
    echo ""
    echo -ne "  ${GREEN}➜${NC}  ${WHITE}Имя файла [${DEFAULT_SUB_FILENAME%.txt}]: ${NC}"
    read -r custom_filename
    
    if [[ -n "$custom_filename" ]]; then
        if [[ "$custom_filename" =~ ^[a-zA-Z0-9._-]+$ ]]; then
            sub_filename="${custom_filename%.txt}"
            msg_ok "Имя файла: ${sub_filename}.txt"
        else
            msg_warn "Некорректное имя файла, используем: ${DEFAULT_SUB_FILENAME%.txt}"
            sub_filename="${DEFAULT_SUB_FILENAME%.txt}"
        fi
    fi
    sleep 0.5
    
    # Сохраняем настройки
    config_set "use_domain" "$use_domain"
    config_set "domain" "$domain"
    config_set "use_ssl" "$use_ssl"
    config_set "web_port" "$web_port"
    config_set "encode_url" "$encode_url"
    config_set "encoded_path" "$encoded_path"
    config_set "sub_filename" "${sub_filename%.txt}"
}

setup_nginx_config() {
    init_sub_vars
    
    print_installer_header
    
    echo ""
    echo -e "  ${CYAN}>>>${NC} ${WHITE}НАСТРОЙКА ВЕБ-СЕРВЕРА${NC} ${CYAN}<<<${NC}"
    echo -e "  ${GRAY}Шаг 6 из 6: Конфигурация Nginx${NC}"
    echo ""
    echo ""
    
    local use_domain=$(config_get "use_domain" "false")
    local domain=$(config_get "domain" "")
    local use_ssl=$(config_get "use_ssl" "false")
    local web_port=$(config_get "web_port" "8443")
    local encode_url=$(config_get "encode_url" "false")
    local encoded_path=$(config_get "encoded_path" "")
    local server_ip
    server_ip=$(curl -4 -s --connect-timeout 5 ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
    
    local server_name="${server_ip}"
    [[ "$use_domain" == "true" && -n "$domain" ]] && server_name="$domain"
    
    local sub_path="/${SUB_FILENAME}"
    if [[ "$encode_url" == "true" && -n "$encoded_path" ]]; then
        sub_path="/${encoded_path}"
    fi
    
    # Прогресс настройки
    progress_bar 1 4 "Создание конфигурации Nginx..."
    
    # Создаём базовую конфигурацию Nginx (HTTP)
    cat > "$NGINX_CONF" <<EONGINX
server {
    listen ${web_port};
    listen [::]:${web_port};

    server_name ${server_name};

    access_log /var/log/nginx/3xcsm_access.log;
    error_log /var/log/nginx/3xcsm_error.log;

    location = ${sub_path} {
        default_type "text/plain; charset=utf-8";
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        alias ${SUB_FILE};
    }

    location / {
        return 404;
    }
}
EONGINX
    sleep 0.3
    
    progress_bar 2 4 "Активация конфигурации..."
    
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null
    rm -f /etc/nginx/sites-enabled/subup 2>/dev/null
    ln -sf "$NGINX_CONF" "$NGINX_LINK" 2>/dev/null
    mkdir -p /var/log/nginx /var/www/html 2>/dev/null
    touch /var/log/nginx/access.log /var/log/nginx/error.log /var/log/nginx/3xcsm_access.log /var/log/nginx/3xcsm_error.log 2>/dev/null
    sleep 0.2
    
    progress_bar 3 4 "Перезагрузка Nginx..."
    
    if nginx -t > /dev/null 2>&1; then
        systemctl enable nginx > /dev/null 2>&1
        systemctl restart nginx > /dev/null 2>&1
    fi
    
    if command -v ufw &>/dev/null; then
        ufw allow "${web_port}/tcp" > /dev/null 2>&1
    fi
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="${web_port}/tcp" > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
    fi
    sleep 0.2
    
    progress_bar 4 4 "Создание файла подписки..."
    
    touch "$SUB_FILE"
    chmod 644 "$SUB_FILE"
    sleep 0.2
    
    progress_done "Nginx настроен"
    
    # Если нужен SSL — запускаем certbot
    if [[ "$use_ssl" == "true" && -n "$domain" ]]; then
        echo ""
        echo ""
        
        # Экран SSL
        print_installer_header
        
        echo ""
        echo -e "  ${CYAN}>>>${NC} ${WHITE}УСТАНОВКА SSL-СЕРТИФИКАТА${NC} ${CYAN}<<<${NC}"
        echo -e "  ${GRAY}Получение сертификата Let's Encrypt${NC}"
        echo ""
        echo ""
        
        echo -e "  ${WHITE}Домен:${NC} ${CYAN}${domain}${NC}"
        echo ""
        
        spin_start "Получение SSL-сертификата..."
        
        # Сначала нужен HTTP на 80 для проверки
        local temp_conf="/tmp/certbot_temp.conf"
        cat > "$temp_conf" <<EOTEMP
server {
    listen 80;
    server_name ${domain};
    root ${WEB_DIR};
    location / { try_files \$uri \$uri/ =404; }
}
EOTEMP
        cp "$temp_conf" "$NGINX_CONF"
        nginx -t > /dev/null 2>&1 && systemctl reload nginx > /dev/null 2>&1
        
        # Запускаем certbot
        certbot --nginx -d "$domain" --non-interactive --agree-tos --email "admin@${domain}" --redirect > /dev/null 2>&1
        local cert_rc=$?
        
        spin_stop
        
        if [[ $cert_rc -eq 0 ]]; then
            msg_ok "SSL-сертификат успешно установлен!"
            config_set "web_port" "443"
            update_nginx_config
        else
            msg_err "Не удалось получить SSL-сертификат"
            msg_info "Возможные причины:"
            echo -e "    ${GRAY}• Домен не направлен на этот сервер${NC}"
            echo -e "    ${GRAY}• Порт 80 занят или заблокирован${NC}"
            echo -e "    ${GRAY}• Лимит запросов к Let's Encrypt${NC}"
            msg_info "Продолжаем без SSL..."
            
            config_set "use_ssl" "false"
            # Восстанавливаем HTTP конфигурацию
            setup_nginx_config_http "$domain" "$web_port" "$sub_path"
        fi
        
        rm -f "$temp_conf" 2>/dev/null
    fi
}

setup_nginx_config_http() {
    local domain="$1"
    local port="$2"
    local sub_path="$3"
    
    cat > "$NGINX_CONF" <<EONGINX
server {
    listen ${port};
    listen [::]:${port};
    server_name ${domain};

    access_log /var/log/nginx/3xcsm_access.log;
    error_log /var/log/nginx/3xcsm_error.log;

    location = ${sub_path} {
        default_type "text/plain; charset=utf-8";
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        alias ${SUB_FILE};
    }

    location / {
        return 404;
    }
}
EONGINX
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null
    rm -f /etc/nginx/sites-enabled/subup 2>/dev/null
    ln -sf "$NGINX_CONF" "$NGINX_LINK"
    mkdir -p /var/log/nginx 2>/dev/null
    touch /var/log/nginx/access.log /var/log/nginx/error.log /var/log/nginx/3xcsm_access.log /var/log/nginx/3xcsm_error.log 2>/dev/null
    nginx -t > /dev/null 2>&1 && systemctl restart nginx > /dev/null 2>&1
}

show_installation_complete() {
    init_sub_vars
    
    local use_domain=$(config_get "use_domain" "false")
    local domain=$(config_get "domain" "")
    local use_ssl=$(config_get "use_ssl" "false")
    local web_port=$(config_get "web_port" "8443")
    local encode_url=$(config_get "encode_url" "false")
    local encoded_path=$(config_get "encoded_path" "")
    
    local server_ip
    server_ip=$(curl -4 -s --connect-timeout 5 ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "ВАШ_IP")
    
    # Формируем URL подписки
    local protocol="http"
    [[ "$use_ssl" == "true" ]] && protocol="https"
    
    local host="$server_ip"
    [[ "$use_domain" == "true" && -n "$domain" ]] && host="$domain"
    
    local path="/${SUB_FILENAME}"
    [[ "$encode_url" == "true" && -n "$encoded_path" ]] && path="/${encoded_path}"
    
    local port_str=":${web_port}"
    [[ "$web_port" == "443" || "$web_port" == "80" ]] && port_str=""
    
    local sub_url="${protocol}://${host}${port_str}${path}"
    
    # Финальный экран установки
    print_installer_header
    
    echo ""
    echo -e "  ${GREEN}══════════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}  [OK] УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!${NC}"
    echo -e "  ${GREEN}══════════════════════════════════════════════════${NC}"
    echo ""
    
    msg_ok "Все компоненты установлены"
    msg_ok "Веб-сервер настроен и запущен"
    msg_ok "Конфигурация сохранена"
    
    if [[ "$use_ssl" == "true" ]]; then
        msg_ok "SSL-сертификат установлен"
    fi
    
    echo ""
    print_thin_line
    echo ""
    msg_info "Команда для запуска меню: ${GREEN}3xsub${NC}"
    msg_info "URL подписки: ${CYAN}${sub_url}${NC}"
    msg_info "Файл подписки: ${GRAY}${SUB_FILE}${NC}"
    [[ "$use_ssl" == "true" ]] && msg_info "SSL: ${GREEN}Включён (Let's Encrypt)${NC}"
    [[ "$encode_url" == "true" ]] && msg_info "Путь: ${GREEN}Закодирован в base64${NC}"
    
    echo ""
    print_thin_line
    echo ""
    msg_info "Следующий шаг: добавьте серверы 3x-UI через меню (пункт 1)"
    echo ""
    
    pause_key
}

normalize_sub_filename() {
    local raw="$1"
    raw="${raw##*/}"
    raw="${raw%.txt}"
    echo "${raw}.txt"
}

get_sub_filename() {
    if [[ -f "$CONFIG_FILE" ]]; then
        local name
        name=$(jq -r '.sub_filename // empty' "$CONFIG_FILE" 2>/dev/null)
        if [[ -n "$name" && "$name" != "null" ]]; then
            normalize_sub_filename "$name"
        else
            echo "$DEFAULT_SUB_FILENAME"
        fi
    else
        echo "$DEFAULT_SUB_FILENAME"
    fi
}

get_sub_file() {
    echo "${WEB_DIR}/$(get_sub_filename)"
}

init_sub_vars() {
    SUB_FILENAME=$(get_sub_filename)
    SUB_FILE=$(get_sub_file)
}

SUB_FILENAME="$DEFAULT_SUB_FILENAME"
SUB_FILE="${WEB_DIR}/${SUB_FILENAME}"

config_get() {
    local key="$1"
    local default="$2"
    if [[ -f "$CONFIG_FILE" ]]; then
        local val
        val=$(jq -r --arg k "$key" --arg d "$default" '.[$k] // $d' "$CONFIG_FILE" 2>/dev/null)
        echo "${val:-$default}"
    else
        echo "$default"
    fi
}

config_set() {
    local key="$1"
    local value="$2"
    if [[ -f "$CONFIG_FILE" ]]; then
        local tmp
        tmp=$(mktemp)
        jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$CONFIG_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$CONFIG_FILE"
    fi
}

servers_count() {
    if [[ -f "$SERVERS_FILE" ]]; then
        jq 'length' "$SERVERS_FILE" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

server_get() {
    local index=$1
    jq ".[$index]" "$SERVERS_FILE" 2>/dev/null
}

server_add() {
    local name="$1"
    local address="$2"
    local port="$3"
    local username="$4"
    local password="$5"
    local web_path="$6"
    local use_ssl="$7"
    local inbounds_filter="$8"

    local protocol="http"
    [[ "$use_ssl" == "true" ]] && protocol="https"

    local tmp
    tmp=$(mktemp)

    local date_now
    date_now=$(date '+%Y-%m-%d %H:%M:%S')

    local enc_pw
    enc_pw=$(_encrypt "$password")
    
    jq --arg n "$name" \
       --arg a "$address" \
       --argjson p "$port" \
       --arg u "$username" \
       --arg pw "$enc_pw" \
       --arg wp "$web_path" \
       --argjson ssl "$use_ssl" \
       --arg pr "$protocol" \
       --argjson inf "$inbounds_filter" \
       --arg dt "$date_now" \
       '. += [{
            "name": $n,
            "address": $a,
            "port": $p,
            "username": $u,
            "password": $pw,
            "web_path": $wp,
            "use_ssl": $ssl,
            "protocol": $pr,
            "inbounds_filter": $inf,
            "enabled": true,
            "added": $dt
        }]' "$SERVERS_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$SERVERS_FILE"
}

server_delete() {
    local index=$1
    local tmp
    tmp=$(mktemp)
    jq "del(.[$index])" "$SERVERS_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$SERVERS_FILE"
}

server_update_field() {
    local index=$1
    local field="$2"
    local value="$3"
    local tmp
    tmp=$(mktemp)

    if [[ "$value" == "true" || "$value" == "false" ]]; then
        jq --argjson v "$value" ".[$index].$field = \$v" "$SERVERS_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$SERVERS_FILE"
    elif [[ "$value" =~ ^-?[0-9]+$ ]]; then
        jq --argjson v "$value" ".[$index].$field = \$v" "$SERVERS_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$SERVERS_FILE"
    elif [[ "$value" == \[* ]]; then
        jq --argjson v "$value" ".[$index].$field = \$v" "$SERVERS_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$SERVERS_FILE"
    else
        jq --arg v "$value" ".[$index].$field = \$v" "$SERVERS_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$SERVERS_FILE"
    fi
}

_get_enc_key() {
    local mid
    mid=$(cat /etc/machine-id 2>/dev/null || hostname | md5sum | awk '{print $1}')
    echo "${mid:0:32}"
}

_encrypt() {
    local text="$1"
    local key
    key=$(_get_enc_key)
    echo -n "$text" | openssl enc -aes-256-cbc -a -A -pbkdf2 -pass "pass:${key}" 2>/dev/null
}

_decrypt() {
    local cipher="$1"
    local key
    key=$(_get_enc_key)
    echo -n "$cipher" | openssl enc -aes-256-cbc -d -a -A -pbkdf2 -pass "pass:${key}" 2>/dev/null
}

# User-Agent для имитации браузера
readonly USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

rawurlencode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * ) printf -v o '%%%02X' "'$c" ;;
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

build_panel_url() {
    local address="$1"
    local port="$2"
    local web_path="$3"
    local protocol="$4"

    local url="${protocol}://${address}:${port}"

    if [[ -n "$web_path" && "$web_path" != "/" && "$web_path" != "null" && "$web_path" != "" ]]; then
        web_path="${web_path#/}"
        web_path="${web_path%/}"
        url="${url}/${web_path}"
    fi

    echo "$url"
}

api_login() {
    local address="$1"
    local port="$2"
    local username="$3"
    local password="$4"
    local web_path="$5"
    local protocol="$6"
    local cookie_file="$7"

    local base_url
    base_url=$(build_panel_url "$address" "$port" "$web_path" "$protocol")

    debug_log "Base URL: $base_url"
    debug_log "Username: $username"

    rm -f "$cookie_file" "${cookie_file}.error" "${cookie_file}.version" 2>/dev/null
    touch "$cookie_file"
    chmod 600 "$cookie_file"

    local response http_code success html_page csrf_token

    # ШАГ 1: GET главной страницы
    debug_log "Step 1: GET main page..."
    
    html_page=$(curl -sS -k -L \
        -c "$cookie_file" \
        -H "User-Agent: ${USER_AGENT}" \
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
        --connect-timeout "$CURL_CONNECT_TIMEOUT" \
        --max-time "$CURL_MAX_TIME" \
        "${base_url}/" 2>&1)

    csrf_token=$(echo "$html_page" | grep -oP 'csrf-token"\s*content="\K[^"]+' 2>/dev/null)
    
    if [[ -z "$csrf_token" ]]; then
        csrf_token=$(echo "$html_page" | sed -n 's/.*csrf-token.*content="\([^"]*\)".*/\1/p' 2>/dev/null | head -1)
    fi

    debug_log "CSRF Token: ${csrf_token:0:20}..."

    # ШАГ 2: POST /login с CSRF
    if [[ -n "$csrf_token" ]]; then
        debug_log "Step 2: POST /login with CSRF..."
        
        response=$(curl -sS -k \
            -w "\n%{http_code}" \
            -c "$cookie_file" \
            -b "$cookie_file" \
            -X POST \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -H "Accept: application/json" \
            -H "User-Agent: ${USER_AGENT}" \
            -H "Origin: ${base_url}" \
            -H "Referer: ${base_url}/" \
            -H "X-CSRF-Token: ${csrf_token}" \
            --data-urlencode "username=${username}" \
            --data-urlencode "password=${password}" \
            --connect-timeout "$CURL_CONNECT_TIMEOUT" \
            --max-time "$CURL_MAX_TIME" \
            "${base_url}/login" 2>&1)

        http_code=$(echo "$response" | tail -1)
        response=$(echo "$response" | sed '$d')

        debug_log "[/login + CSRF] HTTP: $http_code"

        success=$(echo "$response" | jq -r '.success // empty' 2>/dev/null)

        if [[ "$success" == "true" ]]; then
            debug_log "Login successful!"
            echo "v3-csrf" > "${cookie_file}.version"
            return 0
        fi

        # Пробуем JSON
        debug_log "Trying JSON body..."
        
        html_page=$(curl -sS -k -L -c "$cookie_file" \
            -H "User-Agent: ${USER_AGENT}" \
            "${base_url}/" 2>&1)
        csrf_token=$(echo "$html_page" | grep -oP 'csrf-token"\s*content="\K[^"]+' 2>/dev/null)
        
        local json_password
        json_password=$(printf '%s' "$password" | jq -Rs '.')

        response=$(curl -sS -k \
            -w "\n%{http_code}" \
            -c "$cookie_file" \
            -b "$cookie_file" \
            -X POST \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -H "User-Agent: ${USER_AGENT}" \
            -H "X-CSRF-Token: ${csrf_token}" \
            -d "{\"username\":\"${username}\",\"password\":${json_password}}" \
            --connect-timeout "$CURL_CONNECT_TIMEOUT" \
            --max-time "$CURL_MAX_TIME" \
            "${base_url}/login" 2>&1)

        http_code=$(echo "$response" | tail -1)
        response=$(echo "$response" | sed '$d')

        success=$(echo "$response" | jq -r '.success // empty' 2>/dev/null)

        if [[ "$success" == "true" ]]; then
            debug_log "Login successful with JSON!"
            return 0
        fi
    fi

    # ШАГ 3: Fallback
    debug_log "Step 3: Fallback endpoints..."
    
    local login_endpoints=(
        "/login"
        "/xui/API/login"
        "/panel/api/login"
    )

    for login_endpoint in "${login_endpoints[@]}"; do
        local login_url="${base_url}${login_endpoint}"
        debug_log "Trying: $login_url"

        curl -sS -k -L -c "$cookie_file" -o /dev/null \
            -H "User-Agent: ${USER_AGENT}" \
            "${base_url}/" 2>/dev/null

        response=$(curl -sS -k -L \
            -w "\n%{http_code}" \
            -c "$cookie_file" \
            -b "$cookie_file" \
            -X POST \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -H "Accept: application/json" \
            -H "User-Agent: ${USER_AGENT}" \
            -H "X-Requested-With: XMLHttpRequest" \
            --data-urlencode "username=${username}" \
            --data-urlencode "password=${password}" \
            --connect-timeout "$CURL_CONNECT_TIMEOUT" \
            --max-time "$CURL_MAX_TIME" \
            "$login_url" 2>&1)

        http_code=$(echo "$response" | tail -1)
        response=$(echo "$response" | sed '$d')

        [[ "$http_code" == "404" ]] && continue

        success=$(echo "$response" | jq -r '.success // empty' 2>/dev/null)

        if [[ "$success" == "true" ]]; then
            debug_log "Login successful at $login_endpoint"
            return 0
        fi
    done

    local error_msg
    error_msg=$(echo "$response" | jq -r '.msg // empty' 2>/dev/null)
    
    if [[ -z "$error_msg" ]]; then
        if [[ "$http_code" == "403" ]]; then
            error_msg="HTTP 403 - доступ запрещён"
        elif [[ "$http_code" == "404" ]]; then
            error_msg="HTTP 404 - endpoint не найден"
        else
            error_msg="Ошибка авторизации (HTTP $http_code)"
        fi
    fi
    
    echo "$error_msg" > "${cookie_file}.error" 2>/dev/null

    return 1
}

api_get_inbounds() {
    local address="$1"
    local port="$2"
    local web_path="$3"
    local protocol="$4"
    local cookie_file="$5"

    local base_url
    base_url=$(build_panel_url "$address" "$port" "$web_path" "$protocol")

    local api_paths=(
        "/xui/API/inbounds/list"
        "/xui/API/inbounds"
        "/panel/api/inbounds/list"
        "/panel/api/inbounds"
    )

    local response http_code success

    for api_path in "${api_paths[@]}"; do
        local api_url="${base_url}${api_path}"
        debug_log "Trying inbounds API: $api_url"

        response=$(curl -sS -k -L \
            -w "\n%{http_code}" \
            -b "$cookie_file" \
            -X GET \
            -H "Accept: application/json" \
            -H "User-Agent: ${USER_AGENT}" \
            --connect-timeout "$CURL_CONNECT_TIMEOUT" \
            --max-time "$CURL_MAX_TIME" \
            "$api_url" 2>&1)

        http_code=$(echo "$response" | tail -1)
        response=$(echo "$response" | sed '$d')

        [[ "$http_code" == "404" ]] && continue

        success=$(echo "$response" | jq -r '.success // empty' 2>/dev/null)

        if [[ "$success" == "true" ]]; then
            echo "$response" | jq '.obj // []' 2>/dev/null
            return 0
        fi

        if [[ "$http_code" == "200" ]]; then
            local is_array
            is_array=$(echo "$response" | jq 'if type == "array" then "yes" else "no" end' 2>/dev/null)
            if [[ "$is_array" == "\"yes\"" ]]; then
                echo "$response"
                return 0
            fi
        fi
    done

    echo "[]"
    return 1
}

api_test_connection() {
    local address="$1"
    local port="$2"
    local username="$3"
    local password="$4"
    local web_path="$5"
    local protocol="$6"

    local cookie_file
    cookie_file=$(mktemp)

    local display_path="$web_path"
    [[ -z "$display_path" || "$display_path" == "null" ]] && display_path="(не задан)"

    echo ""
    msg_info "Тестирование подключения к панели 3x-UI"
    echo -e "  ${GRAY}├─ Адрес: ${protocol}://${address}:${port}${NC}"
    echo -e "  ${GRAY}├─ Web Path: ${display_path}${NC}"
    echo -e "  ${GRAY}└─ Логин: ${username}${NC}"
    echo ""

    # Шаг 1: TCP
    msg_info "Шаг 1: Проверка TCP-соединения..."
    if timeout 5 bash -c "cat < /dev/null > /dev/tcp/${address}/${port}" 2>/dev/null; then
        msg_ok "TCP-порт $port открыт"
    else
        msg_err "TCP-порт $port недоступен"
        rm -f "$cookie_file"
        return 1
    fi

    # Шаг 2: HTTP
    msg_info "Шаг 2: Проверка HTTP-ответа..."
    local base_url
    base_url=$(build_panel_url "$address" "$port" "$web_path" "$protocol")
    
    local http_check
    http_check=$(curl -sS -k -L -o /dev/null -w "%{http_code}" \
        --connect-timeout 10 --max-time 15 \
        -H "User-Agent: ${USER_AGENT}" \
        "$base_url" 2>&1)
    
    if [[ "$http_check" == "200" || "$http_check" == "302" || "$http_check" == "301" ]]; then
        msg_ok "HTTP-ответ: $http_check"
    elif [[ "$http_check" == "404" ]]; then
        msg_err "HTTP 404 — URL не найден"
        rm -f "$cookie_file"
        return 1
    else
        msg_warn "HTTP-ответ: $http_check"
    fi

    # Шаг 3: Авторизация
    msg_info "Шаг 3: Авторизация в панели..."
    
    if api_login "$address" "$port" "$username" "$password" "$web_path" "$protocol" "$cookie_file"; then
        msg_ok "Авторизация успешна"
    else
        local alt_protocol
        [[ "$protocol" == "https" ]] && alt_protocol="http" || alt_protocol="https"

        msg_warn "Пробуем $alt_protocol..."
        
        if api_login "$address" "$port" "$username" "$password" "$web_path" "$alt_protocol" "$cookie_file"; then
            msg_ok "Авторизация успешна через $alt_protocol"
            protocol="$alt_protocol"
        else
            msg_err "Авторизация не удалась"
            rm -f "$cookie_file"
            return 1
        fi
    fi

    # Шаг 4: Инбаунды и версия
    msg_info "Шаг 4: Получение данных панели..."
    local inbounds
    inbounds=$(api_get_inbounds "$address" "$port" "$web_path" "$protocol" "$cookie_file")
    
    if [[ $? -eq 0 ]]; then
        local total_inb vless_inb
        total_inb=$(echo "$inbounds" | jq 'length' 2>/dev/null || echo "0")
        local supported_inb
        supported_inb=$(echo "$inbounds" | jq '[.[] | select(.protocol=="vless" or .protocol=="vmess" or .protocol=="trojan" or .protocol=="shadowsocks" or .protocol=="hysteria2")] | length' 2>/dev/null || echo "0")
        msg_ok "Инбаундов: $total_inb (поддерживаемых: $supported_inb)"
    fi

    # Проверка версии
    local panel_version
    panel_version=$(check_3xui_version "$address" "$port" "$protocol" "$web_path" "$cookie_file")
    
    if [[ -n "$panel_version" && "$panel_version" != "unknown" ]]; then
        if version_compare "$panel_version" "$MIN_3XUI_VERSION"; then
            msg_ok "Версия 3x-UI: $panel_version"
        else
            msg_warn "Версия 3x-UI: $panel_version (рекомендуется ${RECOMMENDED_3XUI_VERSION}+)"
            msg_info "Рекомендуется обновить панель через меню (пункт 8)"
        fi
    fi

    rm -f "$cookie_file"
    echo ""
    return 0
}

extract_keys() {
    local inbound_json="$1"
    local server_address="$2"

    local protocol port remark enable
    protocol=$(echo "$inbound_json" | jq -r '.protocol // ""' 2>/dev/null)
    port=$(echo "$inbound_json" | jq -r '.port // 0' 2>/dev/null)
    remark=$(echo "$inbound_json" | jq -r '.remark // "unknown"' 2>/dev/null)
    enable=$(echo "$inbound_json" | jq -r '.enable // true' 2>/dev/null)

    [[ "$enable" == "false" ]] && return

    case "$protocol" in
        vless|vmess|trojan|shadowsocks) ;;
        hysteria2) extract_hysteria2_keys "$inbound_json" "$server_address"; return ;;
        *) return ;;
    esac

    local stream_raw stream_settings
    stream_raw=$(echo "$inbound_json" | jq -r '.streamSettings // "{}"' 2>/dev/null)

    if echo "$stream_raw" | jq -e '.' >/dev/null 2>&1; then
        stream_settings="$stream_raw"
    else
        stream_settings=$(echo "$stream_raw" | jq -r '.' 2>/dev/null || echo '{}')
    fi

    local network security
    network=$(echo "$stream_settings" | jq -r '.network // "tcp"' 2>/dev/null)
    security=$(echo "$stream_settings" | jq -r '.security // "none"' 2>/dev/null)

    local params="type=${network}&security=${security}"

    # Reality
    if [[ "$security" == "reality" ]]; then
        local reality_settings pbk fp sni sid spx
        reality_settings=$(echo "$stream_settings" | jq '.realitySettings // {}' 2>/dev/null)

        pbk=$(echo "$reality_settings" | jq -r '.settings.publicKey // .publicKey // empty' 2>/dev/null)
        fp=$(echo "$reality_settings" | jq -r '.settings.fingerprint // .fingerprint // "chrome"' 2>/dev/null)
        sni=$(echo "$reality_settings" | jq -r '.serverNames[0] // .serverName // empty' 2>/dev/null)
        sid=$(echo "$reality_settings" | jq -r '.shortIds[0] // .shortId // empty' 2>/dev/null)
        spx=$(echo "$reality_settings" | jq -r '.settings.spiderX // .spiderX // empty' 2>/dev/null)

        [[ -n "$pbk" && "$pbk" != "null" ]] && params+="&pbk=${pbk}"
        [[ -n "$fp" && "$fp" != "null" ]] && params+="&fp=${fp}"
        [[ -n "$sni" && "$sni" != "null" ]] && params+="&sni=${sni}"
        [[ -n "$sid" && "$sid" != "null" ]] && params+="&sid=${sid}"
        [[ -n "$spx" && "$spx" != "null" && "$spx" != "/" ]] && params+="&spx=$(urlencode "$spx")"
    fi

    # TLS
    if [[ "$security" == "tls" ]]; then
        local tls_settings sni fp alpn
        tls_settings=$(echo "$stream_settings" | jq '.tlsSettings // {}' 2>/dev/null)

        sni=$(echo "$tls_settings" | jq -r '.serverName // empty' 2>/dev/null)
        fp=$(echo "$tls_settings" | jq -r '.settings.fingerprint // .fingerprint // empty' 2>/dev/null)
        alpn=$(echo "$tls_settings" | jq -r 'if .alpn then (.alpn | join(",")) else empty end' 2>/dev/null)

        [[ -n "$sni" && "$sni" != "null" ]] && params+="&sni=${sni}"
        [[ -n "$fp" && "$fp" != "null" && "$fp" != "" ]] && params+="&fp=${fp}"
        [[ -n "$alpn" && "$alpn" != "null" && "$alpn" != "" ]] && params+="&alpn=$(urlencode "$alpn")"
    fi

    # Network settings
    case "$network" in
        ws)
            local ws_path ws_host
            ws_path=$(echo "$stream_settings" | jq -r '.wsSettings.path // "/" ' 2>/dev/null)
            ws_host=$(echo "$stream_settings" | jq -r '.wsSettings.headers.Host // .wsSettings.headers.host // empty' 2>/dev/null)
            [[ -n "$ws_path" && "$ws_path" != "null" && "$ws_path" != "/" ]] && params+="&path=$(urlencode "$ws_path")"
            [[ -n "$ws_host" && "$ws_host" != "null" ]] && params+="&host=${ws_host}"
            ;;
        grpc)
            local service_name grpc_mode
            service_name=$(echo "$stream_settings" | jq -r '.grpcSettings.serviceName // empty' 2>/dev/null)
            grpc_mode=$(echo "$stream_settings" | jq -r '.grpcSettings.multiMode // false' 2>/dev/null)
            [[ -n "$service_name" && "$service_name" != "null" ]] && params+="&serviceName=${service_name}"
            [[ "$grpc_mode" == "true" ]] && params+="&mode=multi"
            ;;
        tcp)
            local header_type
            header_type=$(echo "$stream_settings" | jq -r '.tcpSettings.header.type // "none"' 2>/dev/null)
            [[ "$header_type" != "none" && "$header_type" != "null" ]] && params+="&headerType=${header_type}"
            ;;
        h2|http)
            local h2_path h2_host
            h2_path=$(echo "$stream_settings" | jq -r '.httpSettings.path // empty' 2>/dev/null)
            h2_host=$(echo "$stream_settings" | jq -r '.httpSettings.host[0] // empty' 2>/dev/null)
            [[ -n "$h2_path" && "$h2_path" != "null" ]] && params+="&path=$(urlencode "$h2_path")"
            [[ -n "$h2_host" && "$h2_host" != "null" ]] && params+="&host=${h2_host}"
            ;;
        kcp|mkcp)
            local kcp_seed kcp_type
            kcp_seed=$(echo "$stream_settings" | jq -r '.kcpSettings.seed // empty' 2>/dev/null)
            kcp_type=$(echo "$stream_settings" | jq -r '.kcpSettings.header.type // "none"' 2>/dev/null)
            [[ -n "$kcp_seed" && "$kcp_seed" != "null" ]] && params+="&seed=${kcp_seed}"
            [[ "$kcp_type" != "none" && "$kcp_type" != "null" ]] && params+="&headerType=${kcp_type}"
            ;;
        httpupgrade)
            local hu_path hu_host
            hu_path=$(echo "$stream_settings" | jq -r '.httpupgradeSettings.path // empty' 2>/dev/null)
            hu_host=$(echo "$stream_settings" | jq -r '.httpupgradeSettings.host // empty' 2>/dev/null)
            [[ -n "$hu_path" && "$hu_path" != "null" ]] && params+="&path=$(urlencode "$hu_path")"
            [[ -n "$hu_host" && "$hu_host" != "null" ]] && params+="&host=${hu_host}"
            ;;
        splithttp)
            local sh_path sh_host
            sh_path=$(echo "$stream_settings" | jq -r '.splithttpSettings.path // empty' 2>/dev/null)
            sh_host=$(echo "$stream_settings" | jq -r '.splithttpSettings.host // empty' 2>/dev/null)
            [[ -n "$sh_path" && "$sh_path" != "null" ]] && params+="&path=$(urlencode "$sh_path")"
            [[ -n "$sh_host" && "$sh_host" != "null" ]] && params+="&host=${sh_host}"
            ;;
    esac

    # Clients
    local settings_raw settings
    settings_raw=$(echo "$inbound_json" | jq -r '.settings // "{}"' 2>/dev/null)

    if echo "$settings_raw" | jq -e '.' >/dev/null 2>&1; then
        settings="$settings_raw"
    else
        settings=$(echo "$settings_raw" | jq -r '.' 2>/dev/null || echo '{"clients":[]}')
    fi

    local clients_count
    clients_count=$(echo "$settings" | jq '.clients | length // 0' 2>/dev/null)

    if [[ -z "$clients_count" || "$clients_count" == "null" || "$clients_count" -eq 0 ]]; then
        return
    fi

    for ((c=0; c<clients_count; c++)); do
        local uuid email flow client_enable client_password
        uuid=$(echo "$settings" | jq -r ".clients[$c].id // empty" 2>/dev/null)
        email=$(echo "$settings" | jq -r ".clients[$c].email // \"client${c}\"" 2>/dev/null)
        flow=$(echo "$settings" | jq -r ".clients[$c].flow // empty" 2>/dev/null)
        client_enable=$(echo "$settings" | jq -r ".clients[$c].enable // true" 2>/dev/null)
        client_password=$(echo "$settings" | jq -r ".clients[$c].password // empty" 2>/dev/null)

        [[ "$client_enable" == "false" ]] && continue

        case "$protocol" in
            vless)
                [[ -z "$uuid" || "$uuid" == "null" ]] && continue
                local full_params="$params"
                [[ -n "$flow" && "$flow" != "null" && "$flow" != "" ]] && full_params+="&flow=${flow}"
                printf '%s\t%s\n' "$email" "vless://${uuid}@${server_address}:${port}?${full_params}#$(urlencode "$email")"
                ;;
            vmess)
                [[ -z "$uuid" || "$uuid" == "null" ]] && continue
                local vmess_json
                vmess_json=$(jq -nc \
                    --arg v "2" \
                    --arg ps "$email" \
                    --arg add "$server_address" \
                    --argjson port "$port" \
                    --arg id "$uuid" \
                    --arg aid "0" \
                    --arg net "$network" \
                    --arg type "none" \
                    --arg host "" \
                    --arg path "" \
                    --arg tls "$security" \
                    --arg sni "" \
                    '{v:$v,ps:$ps,add:$add,port:$port,id:$id,aid:$aid,net:$net,type:$type,host:$host,path:$path,tls:$tls,sni:$sni}')
                local vmess_b64
                vmess_b64=$(echo -n "$vmess_json" | base64 -w0 2>/dev/null || echo -n "$vmess_json" | base64 2>/dev/null)
                printf '%s\t%s\n' "$email" "vmess://${vmess_b64}"
                ;;
            trojan)
                local trojan_pass="${client_password:-$uuid}"
                [[ -z "$trojan_pass" || "$trojan_pass" == "null" ]] && continue
                printf '%s\t%s\n' "$email" "trojan://${trojan_pass}@${server_address}:${port}?${params}#$(urlencode "$email")"
                ;;
            shadowsocks)
                local ss_method ss_password
                ss_method=$(echo "$settings" | jq -r '.method // "aes-256-gcm"' 2>/dev/null)
                ss_password="${client_password:-$(echo "$settings" | jq -r '.password // empty' 2>/dev/null)}"
                [[ -z "$ss_password" || "$ss_password" == "null" ]] && continue
                local ss_userinfo
                ss_userinfo=$(echo -n "${ss_method}:${ss_password}" | base64 -w0 2>/dev/null || echo -n "${ss_method}:${ss_password}" | base64 2>/dev/null)
                printf '%s\t%s\n' "$email" "ss://${ss_userinfo}@${server_address}:${port}#$(urlencode "$email")"
                ;;
        esac
    done
}

extract_hysteria2_keys() {
    local inbound_json="$1"
    local server_address="$2"
    
    local port enable
    port=$(echo "$inbound_json" | jq -r '.port // 0' 2>/dev/null)
    enable=$(echo "$inbound_json" | jq -r '.enable // true' 2>/dev/null)
    [[ "$enable" == "false" ]] && return
    
    local stream_raw obfs obfs_password sni
    stream_raw=$(echo "$inbound_json" | jq -r '.streamSettings // "{}"' 2>/dev/null)
    if echo "$stream_raw" | jq -e '.' >/dev/null 2>&1; then
        sni=$(echo "$stream_raw" | jq -r '.tlsSettings.serverName // empty' 2>/dev/null)
    fi
    
    local settings_raw settings
    settings_raw=$(echo "$inbound_json" | jq -r '.settings // "{}"' 2>/dev/null)
    if echo "$settings_raw" | jq -e '.' >/dev/null 2>&1; then
        settings="$settings_raw"
    else
        settings=$(echo "$settings_raw" | jq -r '.' 2>/dev/null || echo '{"clients":[]}')
    fi
    
    obfs=$(echo "$settings" | jq -r '.obfs.type // empty' 2>/dev/null)
    obfs_password=$(echo "$settings" | jq -r '.obfs.password // empty' 2>/dev/null)
    
    local clients_count
    clients_count=$(echo "$settings" | jq '.clients | length // 0' 2>/dev/null)
    [[ -z "$clients_count" || "$clients_count" == "null" || "$clients_count" -eq 0 ]] && return
    
    for ((c=0; c<clients_count; c++)); do
        local email password client_enable
        email=$(echo "$settings" | jq -r ".clients[$c].email // \"client${c}\"" 2>/dev/null)
        password=$(echo "$settings" | jq -r ".clients[$c].password // empty" 2>/dev/null)
        client_enable=$(echo "$settings" | jq -r ".clients[$c].enable // true" 2>/dev/null)
        
        [[ "$client_enable" == "false" ]] && continue
        [[ -z "$password" || "$password" == "null" ]] && continue
        
        local hy2_params=""
        [[ -n "$sni" && "$sni" != "null" ]] && hy2_params+="sni=${sni}&"
        [[ -n "$obfs" && "$obfs" != "null" ]] && hy2_params+="obfs=${obfs}&obfs-password=${obfs_password}&"
        hy2_params+="insecure=1"
        
        printf '%s\t%s\n' "$email" "hysteria2://${password}@${server_address}:${port}?${hy2_params}#$(urlencode "$email")"
    done
}

urlencode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * )               printf -v o '%%%02X' "'$c" ;;
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}


collect_keys() {
    local silent_mode="${1:-false}"
    
    # Обновляем переменные файла подписки
    init_sub_vars

    if [[ "$silent_mode" != "true" ]]; then
        print_header
        print_section_header "СБОР КЛЮЧЕЙ И ОБНОВЛЕНИЕ ПОДПИСКИ"
    fi

    > "$RAW_FILE"

    local total_servers
    total_servers=$(servers_count)

    if [[ "$total_servers" -eq 0 ]]; then
        [[ "$silent_mode" != "true" ]] && msg_warn "Нет добавленных серверов"
        [[ "$silent_mode" != "true" ]] && pause_key
        return 1
    fi

    local total_keys=0
    local failed_servers=0

    for ((s=0; s<total_servers; s++)); do
        local srv
        srv=$(server_get $s)

        local name address port username password web_path protocol enabled inbounds_filter clients_filter
        name=$(echo "$srv" | jq -r '.name')
        address=$(echo "$srv" | jq -r '.address')
        port=$(echo "$srv" | jq -r '.port')
        username=$(echo "$srv" | jq -r '.username')
        password=$(_decrypt "$(echo "$srv" | jq -r '.password')")
        web_path=$(echo "$srv" | jq -r '.web_path // ""')
        protocol=$(echo "$srv" | jq -r '.protocol // "https"')
        enabled=$(echo "$srv" | jq -r '.enabled // true')
        inbounds_filter=$(echo "$srv" | jq '.inbounds_filter // "all"' 2>/dev/null)
        clients_filter=$(echo "$srv" | jq '.clients_filter // "all"' 2>/dev/null)

        if [[ "$enabled" == "false" ]]; then
            [[ "$silent_mode" != "true" ]] && msg_info "Сервер \"$name\" отключён — пропуск"
            continue
        fi

        [[ "$silent_mode" != "true" ]] && echo -e "\n  ${WHITE}▸ Сервер: ${CYAN}$name${WHITE} ($address:$port)${NC}"

        local cookie_file="${COOKIE_DIR}/server_${s}.cookie"

        [[ "$silent_mode" != "true" ]] && spin_start "Авторизация..."
        api_login "$address" "$port" "$username" "$password" "$web_path" "$protocol" "$cookie_file"
        local login_rc=$?
        [[ "$silent_mode" != "true" ]] && spin_stop

        if [[ $login_rc -ne 0 ]]; then
            local alt_protocol
            [[ "$protocol" == "https" ]] && alt_protocol="http" || alt_protocol="https"

            [[ "$silent_mode" != "true" ]] && spin_start "Попытка через $alt_protocol..."
            api_login "$address" "$port" "$username" "$password" "$web_path" "$alt_protocol" "$cookie_file"
            login_rc=$?
            [[ "$silent_mode" != "true" ]] && spin_stop

            if [[ $login_rc -ne 0 ]]; then
                [[ "$silent_mode" != "true" ]] && msg_err "Не удалось авторизоваться"
                failed_servers=$((failed_servers + 1))
                continue
            fi
            protocol="$alt_protocol"
        fi
        [[ "$silent_mode" != "true" ]] && msg_ok "Авторизация успешна"

        [[ "$silent_mode" != "true" ]] && spin_start "Получение инбаундов..."
        local inbounds
        inbounds=$(api_get_inbounds "$address" "$port" "$web_path" "$protocol" "$cookie_file")
        local inb_rc=$?
        [[ "$silent_mode" != "true" ]] && spin_stop

        if [[ $inb_rc -ne 0 ]]; then
            [[ "$silent_mode" != "true" ]] && msg_err "Не удалось получить инбаунды"
            failed_servers=$((failed_servers + 1))
            continue
        fi

        local inb_count
        inb_count=$(echo "$inbounds" | jq 'length' 2>/dev/null || echo "0")
        [[ "$silent_mode" != "true" ]] && msg_ok "Получено инбаундов: $inb_count"

        local server_keys=0
        for ((i=0; i<inb_count; i++)); do
            local inbound
            inbound=$(echo "$inbounds" | jq ".[$i]" 2>/dev/null)

            local inb_id inb_protocol
            inb_id=$(echo "$inbound" | jq -r '.id' 2>/dev/null)
            inb_protocol=$(echo "$inbound" | jq -r '.protocol' 2>/dev/null)

            case "$inb_protocol" in
                vless|vmess|trojan|shadowsocks|hysteria2) ;;
                *) continue ;;
            esac

            local filter_str
            filter_str=$(echo "$inbounds_filter" | jq -r 'if type == "string" then . else "array" end' 2>/dev/null)

            if [[ "$filter_str" != "all" ]]; then
                local in_filter
                in_filter=$(echo "$inbounds_filter" | jq "index($inb_id)" 2>/dev/null)
                [[ "$in_filter" == "null" ]] && continue
            fi

            local keys
            keys=$(extract_keys "$inbound" "$address")

            if [[ -n "$keys" ]]; then
                while IFS=$'\t' read -r client_email key_uri; do
                    [[ -z "$key_uri" ]] && continue
                    
                    local client_key="${inb_id}|${client_email}"
                    
                    local cf_type
                    cf_type=$(echo "$clients_filter" | jq -r 'if type == "string" then . else "array" end' 2>/dev/null)
                    if [[ "$cf_type" != "all" ]]; then
                        local cf_match
                        cf_match=$(echo "$clients_filter" | jq --arg k "$client_key" --arg e "$client_email" 'index($k) // index($e)' 2>/dev/null)
                        [[ "$cf_match" == "null" ]] && continue
                    fi
                    
                    echo "$key_uri" >> "$RAW_FILE"
                    server_keys=$((server_keys + 1))
                done <<< "$keys"
            fi
        done

        total_keys=$((total_keys + server_keys))
        [[ "$silent_mode" != "true" ]] && msg_ok "Собрано ключей: $server_keys"

        rm -f "$cookie_file" 2>/dev/null
    done

    if [[ -s "$RAW_FILE" ]]; then
        local sub_title
        sub_title=$(config_get "sub_title" "3X-UI-CSM-SUB")
        local client_update_interval
        client_update_interval=$(config_get "client_update_interval" "12")
        local support_url
        support_url=$(config_get "support_url" "https://t.me/LarsInvilink")
        local encode_content
        encode_content=$(config_get "encode_content" "true")
        local header_profile_title
        header_profile_title=$(config_get "header_profile_title" "true")
        local header_profile_update_interval
        header_profile_update_interval=$(config_get "header_profile_update_interval" "true")
        local header_support_url
        header_support_url=$(config_get "header_support_url" "false")
        local header_profile_web_page_url
        header_profile_web_page_url=$(config_get "header_profile_web_page_url" "false")
        local header_subscription_userinfo
        header_subscription_userinfo=$(config_get "header_subscription_userinfo" "false")
        
        local temp_sub
        temp_sub=$(mktemp)
        
        if [[ "$header_profile_title" == "true" ]]; then
            echo "#profile-title: ${sub_title}" >> "$temp_sub"
        fi
        if [[ "$header_profile_update_interval" == "true" ]]; then
            echo "#profile-update-interval: ${client_update_interval}" >> "$temp_sub"
        fi
        if [[ "$header_support_url" == "true" && -n "$support_url" ]]; then
            echo "#support-url: ${support_url}" >> "$temp_sub"
        fi
        if [[ "$header_profile_web_page_url" == "true" && -n "$support_url" ]]; then
            echo "#profile-web-page-url: ${support_url}" >> "$temp_sub"
        fi
        local sub_upload_val sub_download_val sub_total_val sub_expire_val
        sub_upload_val=$(config_get "sub_upload" "0")
        sub_download_val=$(config_get "sub_download" "0")
        sub_total_val=$(config_get "sub_total" "0")
        sub_expire_val=$(config_get "sub_expire" "1798761600")
        if [[ "$header_subscription_userinfo" == "true" ]]; then
            echo "#subscription-userinfo: upload=${sub_upload_val}; download=${sub_download_val}; total=${sub_total_val}; expire=${sub_expire_val}" >> "$temp_sub"
        fi
        if [[ -s "$temp_sub" ]]; then
            echo "" >> "$temp_sub"
        fi
        
        cat "$RAW_FILE" >> "$temp_sub"
        
        if [[ "$encode_content" == "true" ]]; then
            base64 -w0 "$temp_sub" > "$SUB_FILE" 2>/dev/null || base64 "$temp_sub" | tr -d '\n' > "$SUB_FILE" 2>/dev/null
        else
            cp "$temp_sub" "$SUB_FILE"
        fi
        chmod 644 "$SUB_FILE"
        
        rm -f "$temp_sub" 2>/dev/null
    else
        > "$SUB_FILE"
    fi

    if [[ "$silent_mode" != "true" ]]; then
        echo ""
        print_thin_line

        if [[ $total_keys -gt 0 ]]; then
            msg_ok "Итого собрано ключей: $total_keys"
            msg_ok "Файл подписки обновлён"
        else
            msg_warn "Ключи не найдены"
        fi

        if [[ $failed_servers -gt 0 ]]; then
            msg_err "Серверов с ошибками: $failed_servers"
        fi

        pause_key
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Собрано ключей: $total_keys, ошибок: $failed_servers" >> "$LOG_FILE"

    return 0
}


cron_set() {
    local interval="$1"
    local unit="$2"

    if [[ "$unit" == "minutes" && "$interval" =~ ^[0-9]+$ && "$interval" -gt 59 ]]; then
        interval="59"
        config_set "update_interval" "59"
        config_set "update_unit" "minutes"
    elif [[ "$unit" == "hours" && "$interval" =~ ^[0-9]+$ && "$interval" -gt 23 ]]; then
        interval="23"
        config_set "update_interval" "23"
        config_set "update_unit" "hours"
    elif [[ "$unit" == "days" && "$interval" =~ ^[0-9]+$ && "$interval" -gt 30 ]]; then
        interval="30"
        config_set "update_interval" "30"
        config_set "update_unit" "days"
    fi

    cron_remove

    local cron_expr=""
    case "$unit" in
        minutes)
            cron_expr="*/${interval} * * * *"
            ;;
        hours)
            cron_expr="0 */${interval} * * *"
            ;;
        days)
            cron_expr="0 0 */${interval} * *"
            ;;
    esac

    (crontab -l 2>/dev/null; echo "${cron_expr} /bin/bash ${BASE_DIR}/3xcsm.sh --update ${CRON_MARKER}") | crontab -
}

cron_remove() {
    crontab -l 2>/dev/null | grep -v "$CRON_MARKER" | crontab - 2>/dev/null
}

cron_get() {
    crontab -l 2>/dev/null | grep "$CRON_MARKER" 2>/dev/null
}

menu_sub_overview() {
    print_header
    print_section_header "ОБЗОР ПОДПИСКИ"
    
    init_sub_vars
    local _enc
    _enc=$(config_get "encode_content" "true")
    
    local total_servers
    total_servers=$(servers_count)
    
    if [[ "$total_servers" -eq 0 ]]; then
        msg_warn "Нет добавленных серверов"
        echo ""
        echo -e "  ${WHITE}  0) ← Назад${NC}"
        echo ""
        echo -ne "  ${WHITE}Выбор: ${NC}"
        read -r
        return
    fi
    
    local grand_total=0
    
    for ((s=0; s<total_servers; s++)); do
        local srv
        srv=$(server_get $s)
        
        local srv_name srv_addr srv_port srv_proto srv_enabled srv_ibf srv_cf srv_no
        srv_name=$(echo "$srv" | jq -r '.name')
        srv_addr=$(echo "$srv" | jq -r '.address')
        srv_port=$(echo "$srv" | jq -r '.port')
        srv_proto=$(echo "$srv" | jq -r '.protocol // "https"')
        srv_enabled=$(echo "$srv" | jq -r '.enabled // true')
        srv_ibf=$(echo "$srv" | jq '.inbounds_filter // "all"' 2>/dev/null)
        srv_cf=$(echo "$srv" | jq '.clients_filter // "all"' 2>/dev/null)
        
        local status_icon="${GREEN}ON${NC}"
        [[ "$srv_enabled" == "false" ]] && status_icon="${RED}OFF${NC}"
        
        local ibf_text="все"
        local ibf_type
        ibf_type=$(echo "$srv_ibf" | jq -r 'if type == "string" then . else "array" end' 2>/dev/null)
        [[ "$ibf_type" == "array" ]] && ibf_text="$(echo "$srv_ibf" | jq 'length' 2>/dev/null) шт."
        
        local cf_text="все"
        local cf_type
        cf_type=$(echo "$srv_cf" | jq -r 'if type == "string" then . else "array" end' 2>/dev/null)
        [[ "$cf_type" == "array" ]] && cf_text="$(echo "$srv_cf" | jq 'length' 2>/dev/null) шт."
        
        echo -e "  ${CYAN}[$((s+1))]${NC} ${WHITE}${srv_name}${NC} ${status_icon}"
        echo -e "      ${GRAY}${srv_proto}://${srv_addr}:${srv_port}${NC}"
        echo -e "      ${GRAY}Инбаунды: ${ibf_text} | Клиенты: ${cf_text}${NC}"
        
        if [[ "$srv_enabled" == "false" ]]; then
            echo -e "      ${RED}(сервер отключён — ключи не собираются)${NC}"
        else
            if [[ -f "$RAW_FILE" && -s "$RAW_FILE" ]]; then
                local srv_keys_list
                srv_keys_list=$(grep -E "^(vless|vmess|trojan|ss|hysteria2)://.*@${srv_addr}:" "$RAW_FILE" 2>/dev/null)
                if [[ -n "$srv_keys_list" ]]; then
                    local srv_key_count
                    srv_key_count=$(echo "$srv_keys_list" | wc -l)
                    grand_total=$((grand_total + srv_key_count))
                    echo -e "      ${GREEN}Ключей в подписке: ${srv_key_count}${NC}"
                    echo "$srv_keys_list" | while IFS= read -r kl; do
                        local k_proto k_name
                        k_proto=$(echo "$kl" | grep -oP '^[a-z0-9]+(?=://)')
                        k_name=$(echo "$kl" | grep -oP '#\K.*$')
                        k_name=$(printf '%b' "${k_name//%/\\x}" 2>/dev/null || echo "$k_name")
                        local k_port
                        k_port=$(echo "$kl" | grep -oP "@${srv_addr}:\K[0-9]+")
                        echo -e "        ${GRAY}- [${k_proto}] :${k_port} ${CYAN}${k_name}${NC}"
                    done
                else
                    echo -e "      ${GRAY}(нет ключей с этого сервера)${NC}"
                fi
            else
                echo -e "      ${GRAY}(подписка не сгенерирована)${NC}"
            fi
        fi
        echo ""
    done
    
    print_thin_line
    echo -e "  ${WHITE}Всего ключей в подписке:${NC} ${CYAN}${grand_total}${NC}"
    if [[ -f "$SUB_FILE" ]]; then
        local lm
        lm=$(stat -c %y "$SUB_FILE" 2>/dev/null | cut -d. -f1 || echo "--")
        echo -e "  ${WHITE}Последнее обновление:${NC} ${CYAN}${lm}${NC}"
    fi
    echo ""
    echo -e "  ${WHITE}  0) ← Назад${NC}"
    echo ""
    echo -ne "  ${WHITE}Выбор: ${NC}"
    read -r
}

menu_about() {
    print_header
    print_section_header "ИНФОРМАЦИЯ И ОБНОВЛЕНИЕ"
    
    echo -e "  ${WHITE}${PROJECT_NAME}${NC} v${VERSION}"
    echo -e "  ${GRAY}Автор: ${AUTHOR}${NC}"
    echo ""
    print_thin_line
    echo ""
    echo -e "  ${WHITE}GitHub:${NC}"
    echo -e "  ${CYAN}https://github.com/LarsGravesen-invilink/3x-ui-csm${NC}"
    echo ""
    echo -e "  ${WHITE}Telegram:${NC}"
    echo -e "  ${CYAN}https://t.me/LarsInvilink${NC}"
    echo ""
    print_thin_line
    echo ""
    
    echo -e "  ${WHITE}QR-код Telegram-профиля:${NC}"
    echo ""
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "https://t.me/LarsInvilink"
    else
        echo -e "  ${GRAY}(qrencode не установлен для показа QR)${NC}"
    fi
    echo ""
    print_thin_line
    echo ""
    echo -e "  ${WHITE}Поддерживаемые протоколы:${NC}"
    echo -e "  ${GREEN}*${NC} VLESS (Reality, TLS, WS, gRPC, TCP, H2)"
    echo -e "  ${GREEN}*${NC} VMess"
    echo -e "  ${GREEN}*${NC} Trojan"
    echo -e "  ${GREEN}*${NC} Shadowsocks"
    echo -e "  ${GREEN}*${NC} Hysteria2"
    echo ""
    echo -e "  ${WHITE}Требования:${NC} 3x-UI v${MIN_3XUI_VERSION}+ (рек. v${RECOMMENDED_3XUI_VERSION}+)"
    echo ""
    
    pause_key
}


menu_add_server() {
    print_header
    print_section_header "ДОБАВЛЕНИЕ НОВОГО СЕРВЕРА 3x-UI"
    
    echo -e "  ${YELLOW}📋 Требования к версии панели:${NC}"
    echo -e "  ${GRAY}   Минимальная: ${MIN_3XUI_VERSION} │ Рекомендуемая: ${RECOMMENDED_3XUI_VERSION}+${NC}"
    echo ""
    echo -e "  ${DARK_GRAY}Введите 0 для отмены на любом шаге${NC}"
    echo ""
    print_thin_line
    echo ""

    # --- Название ---
    echo -e "  ${WHITE}1. Название сервера${NC}"
    msg_hint "Произвольное имя для идентификации (например: Germany-1, Основной)"
    echo ""
    echo -ne "  ${WHITE}   Название: ${NC}"
    read -r srv_name
    [[ "$srv_name" == "0" ]] && return
    [[ -z "$srv_name" ]] && { msg_err "Название не может быть пустым"; pause_key; return; }

    # --- Адрес ---
    echo ""
    echo -e "  ${WHITE}2. Адрес панели 3x-UI${NC}"
    msg_hint "IP-адрес или домен сервера, где установлена панель"
    msg_hint "Примеры: 192.168.1.100, panel.example.com"
    echo ""
    echo -ne "  ${WHITE}   Адрес: ${NC}"
    read -r srv_address
    [[ "$srv_address" == "0" ]] && return
    [[ -z "$srv_address" ]] && { msg_err "Адрес не может быть пустым"; pause_key; return; }

    # --- Порт ---
    echo ""
    echo -e "  ${WHITE}3. Порт панели${NC}"
    msg_hint "Стандартный порт 3x-UI: 2053 (HTTPS) или 2052 (HTTP)"
    msg_hint "Если изменяли порт в настройках панели — укажите его"
    echo ""
    echo -ne "  ${WHITE}   Порт [2053]: ${NC}"
    read -r srv_port
    [[ "$srv_port" == "0" ]] && return
    [[ -z "$srv_port" ]] && srv_port=2053

    # --- SSL ---
    echo ""
    echo -e "  ${WHITE}4. Протокол подключения${NC}"
    msg_hint "3x-UI v2.8+ по умолчанию использует HTTPS с self-signed SSL"
    msg_hint "Если у вас HTTP — выберите 'n'"
    echo ""
    echo -ne "  ${WHITE}   Использовать HTTPS? (y/n) [y]: ${NC}"
    read -r srv_ssl
    [[ "$srv_ssl" == "0" ]] && return
    local use_ssl="true"
    [[ "$srv_ssl" =~ ^[Nn]$ ]] && use_ssl="false"

    # --- Web Path ---
    echo ""
    echo -e "  ${WHITE}5. Web Base Path (секретный путь)${NC}"
    msg_hint "Находится в настройках панели: Panel Settings → Web Base Path"
    msg_hint "Вводите БЕЗ слешей! Например: secretpanel или mypanel123"
    msg_hint "Если путь не задан в панели — оставьте пустым"
    echo ""
    echo -ne "  ${WHITE}   Web Base Path (пусто если нет): ${NC}"
    read -r srv_webpath
    [[ "$srv_webpath" == "0" ]] && return
    # Убираем слеши если пользователь их ввёл
    srv_webpath="${srv_webpath#/}"
    srv_webpath="${srv_webpath%/}"

    # --- Логин ---
    echo ""
    echo -e "  ${WHITE}6. Логин от панели${NC}"
    msg_hint "Имя пользователя для входа в 3x-UI (обычно: admin)"
    echo ""
    echo -ne "  ${WHITE}   Логин: ${NC}"
    read -r srv_user
    [[ "$srv_user" == "0" ]] && return
    [[ -z "$srv_user" ]] && { msg_err "Логин не может быть пустым"; pause_key; return; }

    # --- Пароль ---
    echo ""
    echo -e "  ${WHITE}7. Пароль от панели${NC}"
    msg_hint "Пароль для входа (ввод скрыт)"
    echo ""
    echo -ne "  ${WHITE}   Пароль: ${NC}"
    read -rs srv_pass
    echo ""
    [[ "$srv_pass" == "0" ]] && return
    [[ -z "$srv_pass" ]] && { msg_err "Пароль не может быть пустым"; pause_key; return; }

    # --- Проверка подключения ---
    local protocol="http"
    [[ "$use_ssl" == "true" ]] && protocol="https"

    local test_cookie
    test_cookie=$(mktemp)

    echo ""
    print_thin_line
    echo ""
    
    spin_start "Проверка TCP-соединения..."
    local tcp_ok=false
    if timeout 5 bash -c "cat < /dev/null > /dev/tcp/${srv_address}/${srv_port}" 2>/dev/null; then
        tcp_ok=true
    fi
    spin_stop

    if [[ "$tcp_ok" == "false" ]]; then
        msg_err "TCP-порт $srv_port недоступен на $srv_address"
        msg_info "Проверьте IP/домен и порт панели"
        echo -ne "\n  ${WHITE}Всё равно добавить сервер? (y/n): ${NC}"
        read -r force_add
        if [[ ! "$force_add" =~ ^[Yy]$ ]]; then
            rm -f "$test_cookie"
            pause_key
            return
        fi
    else
        msg_ok "TCP-порт $srv_port открыт"
    fi

    spin_start "Авторизация в панели..."
    api_login "$srv_address" "$srv_port" "$srv_user" "$srv_pass" "$srv_webpath" "$protocol" "$test_cookie"
    local login_rc=$?
    spin_stop

    if [[ $login_rc -ne 0 ]]; then
        local alt_protocol
        [[ "$protocol" == "https" ]] && alt_protocol="http" || alt_protocol="https"

        spin_start "Попытка через $alt_protocol..."
        api_login "$srv_address" "$srv_port" "$srv_user" "$srv_pass" "$srv_webpath" "$alt_protocol" "$test_cookie"
        login_rc=$?
        spin_stop

        if [[ $login_rc -eq 0 ]]; then
            msg_ok "Подключение успешно через $alt_protocol"
            protocol="$alt_protocol"
            [[ "$alt_protocol" == "https" ]] && use_ssl="true" || use_ssl="false"
        else
            msg_err "Не удалось авторизоваться в панели!"
            echo ""
            msg_info "Возможные причины:"
            echo -e "  ${GRAY}├─ Неверный логин или пароль${NC}"
            echo -e "  ${GRAY}├─ Неверный Web Base Path${NC}"
            echo -e "  ${GRAY}├─ Неверный протокол (HTTP/HTTPS)${NC}"
            echo -e "  ${GRAY}└─ Устаревшая версия 3x-UI (нужна ${MIN_3XUI_VERSION}+)${NC}"
            echo ""
            echo -ne "  ${WHITE}Всё равно добавить сервер? (y/n): ${NC}"
            read -r force_add
            if [[ ! "$force_add" =~ ^[Yy]$ ]]; then
                rm -f "$test_cookie"
                pause_key
                return
            fi
        fi
    else
        msg_ok "Авторизация успешна!"
        
        # Проверка версии
        local panel_version
        panel_version=$(check_3xui_version "$srv_address" "$srv_port" "$protocol" "$srv_webpath" "$test_cookie")
        
        if [[ -n "$panel_version" && "$panel_version" != "unknown" ]]; then
            if ! version_compare "$panel_version" "$MIN_3XUI_VERSION"; then
                msg_warn "Версия панели: $panel_version"
                msg_warn "Рекомендуется обновить до ${RECOMMENDED_3XUI_VERSION}+"
            fi
        fi
    fi

    # --- Выбор инбаундов ---
    local inbounds_filter='"all"'

    if [[ $login_rc -eq 0 ]]; then
        echo ""
        spin_start "Загрузка списка инбаундов..."
        local inbounds
        inbounds=$(api_get_inbounds "$srv_address" "$srv_port" "$srv_webpath" "$protocol" "$test_cookie")
        spin_stop

        local inb_count
        inb_count=$(echo "$inbounds" | jq 'length' 2>/dev/null || echo "0")
        
        local total_inb vless_count
        total_inb="$inb_count"
        local supported_count
        supported_count=$(echo "$inbounds" | jq '[.[] | select(.protocol=="vless" or .protocol=="vmess" or .protocol=="trojan" or .protocol=="shadowsocks" or .protocol=="hysteria2")] | length' 2>/dev/null || echo "0")
        
        msg_ok "Найдено инбаундов: ${total_inb} (поддерживаемых: ${supported_count})"

        if [[ "$inb_count" -gt 0 ]]; then
            echo ""
            echo ""
            echo -e "  ${CYAN}>>>${NC} ${WHITE}ВЫБОР ИНБАУНДОВ ДЛЯ ПОДПИСКИ${NC} ${CYAN}<<<${NC}"
            echo ""
            echo ""

            local vless_ids=()
            local has_vless=false
            
            for ((i=0; i<inb_count; i++)); do
                local inb_protocol inb_id inb_remark inb_port inb_enable
                inb_protocol=$(echo "$inbounds" | jq -r ".[$i].protocol" 2>/dev/null)
                inb_id=$(echo "$inbounds" | jq -r ".[$i].id" 2>/dev/null)
                inb_remark=$(echo "$inbounds" | jq -r ".[$i].remark" 2>/dev/null)
                inb_port=$(echo "$inbounds" | jq -r ".[$i].port" 2>/dev/null)
                inb_enable=$(echo "$inbounds" | jq -r ".[$i].enable" 2>/dev/null)

                case "$inb_protocol" in
                    vless|vmess|trojan|shadowsocks|hysteria2)
                    has_vless=true
                    local status_icon="${GREEN}●${NC}"
                    [[ "$inb_enable" == "false" ]] && status_icon="${RED}○${NC}"

                    local clients_count
                    local settings_raw_tmp
                    settings_raw_tmp=$(echo "$inbounds" | jq -r ".[$i].settings" 2>/dev/null)
                    clients_count=$(echo "$settings_raw_tmp" | jq '.clients | length' 2>/dev/null 2>/dev/null || echo "?")

                    # Определяем тип транспорта
                    local stream_tmp network_tmp security_tmp transport_info
                    stream_tmp=$(echo "$inbounds" | jq -r ".[$i].streamSettings // \"{}\"" 2>/dev/null)
                    if echo "$stream_tmp" | jq -e '.' >/dev/null 2>&1; then
                        network_tmp=$(echo "$stream_tmp" | jq -r '.network // "tcp"' 2>/dev/null)
                        security_tmp=$(echo "$stream_tmp" | jq -r '.security // "none"' 2>/dev/null)
                    else
                        network_tmp="tcp"
                        security_tmp="none"
                    fi
                    transport_info="${network_tmp}+${security_tmp}"

                    echo -e "  ${WHITE}  ${#vless_ids[@]}) ${status_icon} [${inb_protocol}] ${inb_remark}${NC}"
                    echo -e "       ${GRAY}ID:${inb_id} │ :${inb_port} │ ${transport_info} │ ${clients_count} кл.${NC}"
                    vless_ids+=("$inb_id")
                    ;;
                esac
            done

            if [[ "$has_vless" == "true" && ${#vless_ids[@]} -gt 0 ]]; then
                echo ""
                print_thin_line
                echo ""
                echo -e "  ${WHITE}Выберите инбаунды для подписки:${NC}"
                echo ""
                echo -e "  ${WHITE}  a)${NC} ${GREEN}Добавить ВСЕ инбаунды${NC}"
                echo -e "  ${WHITE}  Или введите номера через пробел (например: ${CYAN}0 2 3${NC}${WHITE})${NC}"
                echo ""
                echo -ne "  ${GREEN}➜${NC}  ${WHITE}Выбор [a — все]: ${NC}"
                read -r selected_nums

                if [[ -z "$selected_nums" || "$selected_nums" =~ ^[Aa]$ ]]; then
                    inbounds_filter='"all"'
                    msg_ok "Добавлены все инбаунды (${#vless_ids[@]} шт.)"
                else
                    local selected_ids=()
                    for num in $selected_nums; do
                        if [[ "$num" =~ ^[0-9]+$ ]] && [[ $num -ge 0 ]] && [[ $num -lt ${#vless_ids[@]} ]]; then
                            selected_ids+=("${vless_ids[$num]}")
                        fi
                    done

                    if [[ ${#selected_ids[@]} -gt 0 ]]; then
                        inbounds_filter=$(printf '%s\n' "${selected_ids[@]}" | jq -R 'tonumber' | jq -s '.')
                        msg_ok "Выбрано инбаундов: ${#selected_ids[@]}"
                    else
                        inbounds_filter='"all"'
                        msg_warn "Ничего не выбрано, добавлены все"
                    fi
                fi
                
                # --- Выбор клиентов ---
                echo ""
                echo -e "  ${WHITE}Выбрать конкретных клиентов из инбаундов?${NC}"
                echo -ne "  ${WHITE}(y/n) [n — все]: ${NC}"
                read -r select_clients_yn
                
                local clients_filter_add='"all"'
                
                if [[ "$select_clients_yn" =~ ^[Yy]$ ]]; then
                    echo ""
                    echo -e "  ${WHITE}Клиенты на сервере:${NC}"
                    echo ""
                    local add_emails=()
                    local add_client_keys=()
                    for ((ci=0; ci<inb_count; ci++)); do
                        local ci_proto ci_remark ci_sraw ci_settings ci_id
                        ci_proto=$(echo "$inbounds" | jq -r ".[$ci].protocol" 2>/dev/null)
                        ci_remark=$(echo "$inbounds" | jq -r ".[$ci].remark" 2>/dev/null)
                        ci_id=$(echo "$inbounds" | jq -r ".[$ci].id" 2>/dev/null)
                        case "$ci_proto" in
                            vless|vmess|trojan|shadowsocks|hysteria2) ;;
                            *) continue ;;
                        esac
                        local add_ibf_type
                        add_ibf_type=$(echo "$inbounds_filter" | jq -r 'if type == "string" then . else "array" end' 2>/dev/null)
                        if [[ "$add_ibf_type" != "all" ]]; then
                            local add_in_match
                            add_in_match=$(echo "$inbounds_filter" | jq "index(${ci_id})" 2>/dev/null)
                            [[ "$add_in_match" == "null" ]] && continue
                        fi
                        ci_sraw=$(echo "$inbounds" | jq -r ".[$ci].settings" 2>/dev/null)
                        if echo "$ci_sraw" | jq -e '.' >/dev/null 2>&1; then
                            ci_settings="$ci_sraw"
                        else
                            ci_settings=$(echo "$ci_sraw" | jq -r '.' 2>/dev/null || echo '{"clients":[]}')
                        fi
                        local ci_cc
                        ci_cc=$(echo "$ci_settings" | jq '.clients | length // 0' 2>/dev/null)
                        echo -e "  ${GRAY}[Инбаунд ${ci_id}] ${ci_remark} [${ci_proto}]${NC}"
                        for ((cj=0; cj<ci_cc; cj++)); do
                            local ci_em ci_key
                            ci_em=$(echo "$ci_settings" | jq -r ".clients[$cj].email // \"client${cj}\"" 2>/dev/null)
                            ci_key="${ci_id}|${ci_em}"
                            echo -e "  ${WHITE}  ${#add_emails[@]})${NC} ${CYAN}${ci_em}${NC}"
                            add_emails+=("$ci_em")
                            add_client_keys+=("$ci_key")
                        done
                        echo ""
                    done
                    
                    if [[ ${#add_emails[@]} -gt 0 ]]; then
                        echo ""
                        echo -e "  ${WHITE}  a) Все клиенты${NC}"
                        echo -e "  ${WHITE}  Или номера через пробел${NC}"
                        echo ""
                        echo -ne "  ${GREEN}➜${NC}  ${WHITE}Выбор [a]: ${NC}"
                        read -r sel_cl
                        
                        if [[ -n "$sel_cl" && ! "$sel_cl" =~ ^[Aa]$ ]]; then
                            local sel_cl_arr=()
                            for nn in $sel_cl; do
                                if [[ "$nn" =~ ^[0-9]+$ ]] && [[ $nn -ge 0 ]] && [[ $nn -lt ${#add_client_keys[@]} ]]; then
                                    sel_cl_arr+=("${add_client_keys[$nn]}")
                                fi
                            done
                            if [[ ${#sel_cl_arr[@]} -gt 0 ]]; then
                                clients_filter_add=$(printf '%s\n' "${sel_cl_arr[@]}" | jq -R '.' | jq -s '.')
                                msg_ok "Выбрано клиентов: ${#sel_cl_arr[@]}"
                            fi
                        fi
                    fi
                fi
                
            else
                msg_warn "Поддерживаемые инбаунды не найдены"
            fi
        fi
    fi

    rm -f "$test_cookie" 2>/dev/null

    server_add "$srv_name" "$srv_address" "$srv_port" "$srv_user" "$srv_pass" "$srv_webpath" "$use_ssl" "$inbounds_filter"
    
    local new_srv_idx=$(( $(servers_count) - 1 ))
    if [[ "$clients_filter_add" != '"all"' ]]; then
        server_update_field $new_srv_idx "clients_filter" "$clients_filter_add"
    fi

    echo ""
    msg_ok "Сервер \"$srv_name\" успешно добавлен!"
    msg_info "Всего серверов: $(servers_count)"
    msg_info "Генерация подписки..."
    collect_keys "true"
    msg_ok "Подписка обновлена"

    pause_key
}

menu_servers_list() {
    while true; do
        print_header
        print_section_header "СПИСОК СЕРВЕРОВ 3x-UI"

        local total
        total=$(servers_count)

        if [[ "$total" -eq 0 ]]; then
            msg_warn "Список серверов пуст"
            msg_info "Добавьте сервер через пункт 1 главного меню"
            echo ""
            echo -e "  ${WHITE}  0) ← Назад в главное меню${NC}"
            echo ""
            echo -ne "  ${WHITE}Выберите действие: ${NC}"
            read -r choice
            return
        fi

        for ((s=0; s<total; s++)); do
            local srv
            srv=$(server_get $s)

            local name address port protocol enabled
            name=$(echo "$srv" | jq -r '.name')
            address=$(echo "$srv" | jq -r '.address')
            port=$(echo "$srv" | jq -r '.port')
            protocol=$(echo "$srv" | jq -r '.protocol // "https"')
            enabled=$(echo "$srv" | jq -r '.enabled // true')

            local status_icon status_color
            if [[ "$enabled" == "true" ]]; then
                status_icon="●"
                status_color="${GREEN}"
            else
                status_icon="○"
                status_color="${RED}"
            fi

            local inb_filter
            inb_filter=$(echo "$srv" | jq '.inbounds_filter' 2>/dev/null)
            local filter_text="все"
            local filter_type
            filter_type=$(echo "$inb_filter" | jq -r 'if type == "string" then "string" else "array" end' 2>/dev/null)
            if [[ "$filter_type" == "array" ]]; then
                local filter_count
                filter_count=$(echo "$inb_filter" | jq 'length' 2>/dev/null)
                filter_text="выбрано: $filter_count"
            fi

            echo -e "  ${WHITE}  $((s+1))) ${status_color}${status_icon}${WHITE} ${name}${NC}"
            echo -e "       ${GRAY}${protocol}://${address}:${port} │ Инбаунды: ${filter_text}${NC}"
        done

        echo ""
        print_thin_line
        echo -e "  ${WHITE}  0) ← Назад${NC}"
        echo ""
        echo -ne "  ${WHITE}Введите номер для редактирования: ${NC}"
        read -r choice

        case "$choice" in
            0) return ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$total" ]]; then
                    menu_edit_server $((choice - 1))
                else
                    msg_err "Неверный выбор"
                    sleep 1
                fi
                ;;
        esac
    done
}

menu_edit_server() {
    local index=$1

    while true; do
        print_header

        local srv
        srv=$(server_get $index)

        if [[ -z "$srv" || "$srv" == "null" ]]; then
            msg_err "Сервер не найден"
            pause_key
            return
        fi

        local name address port username web_path protocol enabled inbounds_filter added
        name=$(echo "$srv" | jq -r '.name')
        address=$(echo "$srv" | jq -r '.address')
        port=$(echo "$srv" | jq -r '.port')
        username=$(echo "$srv" | jq -r '.username')
        web_path=$(echo "$srv" | jq -r '.web_path // ""')
        protocol=$(echo "$srv" | jq -r '.protocol // "https"')
        enabled=$(echo "$srv" | jq -r '.enabled // true')
        inbounds_filter=$(echo "$srv" | jq '.inbounds_filter' 2>/dev/null)
        added=$(echo "$srv" | jq -r '.added // "N/A"')

        print_section_header "РЕДАКТИРОВАНИЕ: ${name}"

        local status_text
        if [[ "$enabled" == "true" ]]; then
            status_text="${GREEN}● Активен${NC}"
        else
            status_text="${RED}○ Отключён${NC}"
        fi

        local filter_text="все"
        local filter_type
        filter_type=$(echo "$inbounds_filter" | jq -r 'if type == "string" then . else "array" end' 2>/dev/null)
        if [[ "$filter_type" != "all" && "$filter_type" == "array" ]]; then
            filter_text="выбранные: $(echo "$inbounds_filter" | jq -c '.' 2>/dev/null)"
        fi

        echo -e "  ${GRAY}├─${NC} ${WHITE}Название:${NC}    ${CYAN}$name${NC}"
        echo -e "  ${GRAY}├─${NC} ${WHITE}Адрес:${NC}       ${CYAN}${protocol}://${address}:${port}${NC}"
        echo -e "  ${GRAY}├─${NC} ${WHITE}Web Path:${NC}    ${CYAN}${web_path:-не задан}${NC}"
        echo -e "  ${GRAY}├─${NC} ${WHITE}Логин:${NC}       ${CYAN}${username}${NC}"
        echo -e "  ${GRAY}├─${NC} ${WHITE}Инбаунды:${NC}    ${CYAN}${filter_text}${NC}"
        echo -e "  ${GRAY}├─${NC} ${WHITE}Статус:${NC}      ${status_text}"
        echo -e "  ${GRAY}└─${NC} ${WHITE}Добавлен:${NC}    ${DARK_GRAY}${added}${NC}"
        echo ""
        print_thin_line
        echo ""
        echo -e "  ${WHITE}  1) Изменить название${NC}"
        echo -e "  ${WHITE}  2) Изменить адрес${NC}"
        echo -e "  ${WHITE}  3) Изменить порт${NC}"
        echo -e "  ${WHITE}  4) Изменить логин${NC}"
        echo -e "  ${WHITE}  5) Изменить пароль${NC}"
        echo -e "  ${WHITE}  6) Изменить Web Path${NC}"
        echo -e "  ${WHITE}  7) Переключить HTTP/HTTPS${NC}"
        echo -e "  ${WHITE}  8) Выбрать инбаунды${NC}"
        echo -e "  ${WHITE}  9) Выбрать клиентов из инбаундов${NC}"
        echo ""

        if [[ "$enabled" == "true" ]]; then
            echo -e "  ${YELLOW}  10) Отключить сервер${NC}"
        else
            echo -e "  ${GREEN}  10) Включить сервер${NC}"
        fi
        echo -e "  ${WHITE}  11) Проверить подключение${NC}"
        echo -e "  ${RED}  12) Удалить сервер${NC}"
        echo ""
        echo -e "  ${WHITE}  0) ← Назад${NC}"
        echo ""
        echo -ne "  ${WHITE}Выберите действие: ${NC}"
        read -r action

        case "$action" in
            0) return ;;
            1)
                echo -ne "  ${WHITE}Новое название: ${NC}"
                read -r new_val
                if [[ -n "$new_val" ]]; then
                    server_update_field $index "name" "$new_val"
                    msg_ok "Название обновлено"
                fi
                sleep 1
                ;;
            2)
                echo -ne "  ${WHITE}Новый адрес: ${NC}"
                read -r new_val
                if [[ -n "$new_val" ]]; then
                    server_update_field $index "address" "$new_val"
                    msg_ok "Адрес обновлён"
                fi
                sleep 1
                ;;
            3)
                echo -ne "  ${WHITE}Новый порт: ${NC}"
                read -r new_val
                if [[ -n "$new_val" ]]; then
                    server_update_field $index "port" "$new_val"
                    msg_ok "Порт обновлён"
                fi
                sleep 1
                ;;
            4)
                echo -ne "  ${WHITE}Новый логин: ${NC}"
                read -r new_val
                if [[ -n "$new_val" ]]; then
                    server_update_field $index "username" "$new_val"
                    msg_ok "Логин обновлён"
                fi
                sleep 1
                ;;
            5)
                echo -ne "  ${WHITE}Новый пароль: ${NC}"
                read -rs new_val
                echo ""
                if [[ -n "$new_val" ]]; then
                    server_update_field $index "password" "$(_encrypt "$new_val")"
                    msg_ok "Пароль обновлён"
                fi
                sleep 1
                ;;
            6)
                msg_hint "Вводите БЕЗ слешей! Например: secretpanel"
                echo -ne "  ${WHITE}Новый Web Path: ${NC}"
                read -r new_val
                new_val="${new_val#/}"
                new_val="${new_val%/}"
                server_update_field $index "web_path" "$new_val"
                msg_ok "Web Path обновлён"
                sleep 1
                ;;
            7)
                if [[ "$protocol" == "https" ]]; then
                    server_update_field $index "protocol" "http"
                    server_update_field $index "use_ssl" "false"
                    msg_ok "Переключено на HTTP"
                else
                    server_update_field $index "protocol" "https"
                    server_update_field $index "use_ssl" "true"
                    msg_ok "Переключено на HTTPS"
                fi
                sleep 1
                ;;
            8)
                menu_select_inbounds $index
                ;;
            9)
                echo ""
                local srv9
                srv9=$(server_get $index)
                local cur_cf cur_ibf
                cur_cf=$(echo "$srv9" | jq '.clients_filter // "all"' 2>/dev/null)
                cur_ibf=$(echo "$srv9" | jq '.inbounds_filter // "all"' 2>/dev/null)
                
                local cf_type_cur
                cf_type_cur=$(echo "$cur_cf" | jq -r 'if type == "string" then . else "array" end' 2>/dev/null)
                local ibf_type_cur
                ibf_type_cur=$(echo "$cur_ibf" | jq -r 'if type == "string" then . else "array" end' 2>/dev/null)
                
                echo -e "  ${WHITE}Текущие настройки задания:${NC}"
                if [[ "$ibf_type_cur" == "array" ]]; then
                    echo -e "  ${GRAY}├─${NC} Инбаунды: ${CYAN}$(echo "$cur_ibf" | jq 'length') шт.${NC} $(echo "$cur_ibf" | jq -c '.')"
                else
                    echo -e "  ${GRAY}├─${NC} Инбаунды: ${CYAN}все${NC}"
                fi
                if [[ "$cf_type_cur" == "array" ]]; then
                    local cur_cf_count
                    cur_cf_count=$(echo "$cur_cf" | jq 'length')
                    echo -e "  ${GRAY}├─${NC} Клиенты: ${CYAN}${cur_cf_count} шт.${NC}"
                    echo "$cur_cf" | jq -r '.[]' 2>/dev/null | while IFS= read -r ckey; do
                        local cemail_show
                        cemail_show="${ckey#*|}"
                        echo -e "  ${GRAY}│  ${CYAN}${cemail_show}${NC}"
                    done
                else
                    echo -e "  ${GRAY}├─${NC} Клиенты: ${CYAN}все${NC}"
                fi
                echo ""
                print_thin_line
                echo ""
                echo -e "  ${WHITE}  1) Выбрать клиентов (подключиться к серверу)${NC}"
                echo -e "  ${WHITE}  2) Удалить клиента из задания${NC}"
                echo -e "  ${WHITE}  3) Удалить инбаунд из задания${NC}"
                echo -e "  ${RED}  4) Сбросить фильтр клиентов (все)${NC}"
                echo -e "  ${RED}  5) Сбросить фильтр инбаундов (все)${NC}"
                echo -e "  ${WHITE}  0) Назад${NC}"
                echo ""
                echo -ne "  ${GREEN}➜${NC}  ${WHITE}Выбор: ${NC}"
                read -r sub_action
                
                case "$sub_action" in
                    0) ;;
                    1) msg_info "Подключение к серверу..."
                        local a9 p9 u9 pw9 wp9 pr9
                        a9=$(echo "$srv9" | jq -r '.address')
                        p9=$(echo "$srv9" | jq -r '.port')
                        u9=$(echo "$srv9" | jq -r '.username')
                        pw9=$(_decrypt "$(echo "$srv9" | jq -r '.password')")
                        wp9=$(echo "$srv9" | jq -r '.web_path // ""')
                        pr9=$(echo "$srv9" | jq -r '.protocol // "https"')
                        
                        local ck9
                        ck9=$(mktemp)
                        spin_start "Авторизация..."
                        api_login "$a9" "$p9" "$u9" "$pw9" "$wp9" "$pr9" "$ck9"
                        local rc9=$?
                        if [[ $rc9 -ne 0 ]]; then
                            local alt9
                            [[ "$pr9" == "https" ]] && alt9="http" || alt9="https"
                            api_login "$a9" "$p9" "$u9" "$pw9" "$wp9" "$alt9" "$ck9"
                            rc9=$?
                            [[ $rc9 -eq 0 ]] && pr9="$alt9"
                        fi
                        spin_stop
                        
                        if [[ $rc9 -ne 0 ]]; then
                            msg_err "Не удалось подключиться"
                            rm -f "$ck9"
                        else
                            spin_start "Загрузка инбаундов..."
                            local ibs9
                            ibs9=$(api_get_inbounds "$a9" "$p9" "$wp9" "$pr9" "$ck9")
                            spin_stop
                            rm -f "$ck9" 2>/dev/null
                            
                            local ic9
                            ic9=$(echo "$ibs9" | jq 'length' 2>/dev/null || echo "0")
                            
                            if [[ "$ic9" -eq 0 ]]; then
                                msg_warn "Инбаунды не найдены"
                            else
                                echo ""
                                echo -e "  ${WHITE}Клиенты на сервере:${NC}"
                                echo ""
                                local all_emails=()
                                local all_client_keys=()
                                for ((ii=0; ii<ic9; ii++)); do
                                    local ib_proto ib_remark ib_sraw ib_settings ib_id9
                                    ib_proto=$(echo "$ibs9" | jq -r ".[$ii].protocol" 2>/dev/null)
                                    ib_remark=$(echo "$ibs9" | jq -r ".[$ii].remark" 2>/dev/null)
                                    ib_id9=$(echo "$ibs9" | jq -r ".[$ii].id" 2>/dev/null)
                                    case "$ib_proto" in
                                        vless|vmess|trojan|shadowsocks|hysteria2) ;;
                                        *) continue ;;
                                    esac
                                    if [[ "$ibf_type_cur" == "array" ]]; then
                                        local ibf_match9
                                        ibf_match9=$(echo "$cur_ibf" | jq "index(${ib_id9})" 2>/dev/null)
                                        [[ "$ibf_match9" == "null" ]] && continue
                                    fi
                                    ib_sraw=$(echo "$ibs9" | jq -r ".[$ii].settings" 2>/dev/null)
                                    if echo "$ib_sraw" | jq -e '.' >/dev/null 2>&1; then
                                        ib_settings="$ib_sraw"
                                    else
                                        ib_settings=$(echo "$ib_sraw" | jq -r '.' 2>/dev/null || echo '{"clients":[]}')
                                    fi
                                    local cc9
                                    cc9=$(echo "$ib_settings" | jq '.clients | length // 0' 2>/dev/null)
                                    echo -e "  ${GRAY}[Инбаунд ${ib_id9}] ${ib_remark} [${ib_proto}]${NC}"
                                    for ((jj=0; jj<cc9; jj++)); do
                                        local em9
                                        em9=$(echo "$ib_settings" | jq -r ".clients[$jj].email // \"client${jj}\"" 2>/dev/null)
                                        echo -e "  ${WHITE}  ${#all_emails[@]})${NC} ${CYAN}${em9}${NC}"
                                        all_emails+=("$em9")
                                        all_client_keys+=("${ib_id9}|${em9}")
                                    done
                                    echo ""
                                done
                                
                                if [[ ${#all_emails[@]} -gt 0 ]]; then
                                    echo ""
                                    echo -e "  ${WHITE}  a) Все клиенты${NC}"
                                    echo -e "  ${WHITE}  Или номера через пробел${NC}"
                                    echo ""
                                    echo -ne "  ${GREEN}➜${NC}  ${WHITE}Выбор [a]: ${NC}"
                                    read -r sel_clients
                                    
                                    if [[ -z "$sel_clients" || "$sel_clients" =~ ^[Aa]$ ]]; then
                                        server_update_field $index "clients_filter" '"all"'
                                        msg_ok "Все клиенты включены"
                                    else
                                        local sel_arr=()
                                        for n in $sel_clients; do
                                            if [[ "$n" =~ ^[0-9]+$ ]] && [[ $n -ge 0 ]] && [[ $n -lt ${#all_client_keys[@]} ]]; then
                                                sel_arr+=("${all_client_keys[$n]}")
                                            fi
                                        done
                                        if [[ ${#sel_arr[@]} -gt 0 ]]; then
                                            local cf_json
                                            cf_json=$(printf '%s\n' "${sel_arr[@]}" | jq -R '.' | jq -s '.')
                                            echo ""
                                            echo -e "  ${WHITE}Как применить выбор?${NC}"
                                            echo -e "  ${WHITE}  1) Добавить к уже выбранным${NC}"
                                            echo -e "  ${WHITE}  2) Использовать только новый выбор${NC}"
                                            echo -ne "  ${GREEN}➜${NC}  ${WHITE}Выбор [2]: ${NC}"
                                            read -r apply_clients_mode
                                            if [[ "$apply_clients_mode" == "1" ]]; then
                                                local current_clients_filter
                                                current_clients_filter=$(echo "$srv9" | jq '.clients_filter // "all"' 2>/dev/null)
                                                local current_clients_type
                                                current_clients_type=$(echo "$current_clients_filter" | jq -r 'if type == "string" then . else "array" end' 2>/dev/null)
                                                if [[ "$current_clients_type" == "all" ]]; then
                                                    server_update_field $index "clients_filter" '"all"'
                                                    msg_ok "Уже выбраны все клиенты — добавление не требуется"
                                                else
                                                    local merged_clients_json
                                                    merged_clients_json=$(jq -nc --argjson a "$current_clients_filter" --argjson b "$cf_json" '$a + $b | unique')
                                                    server_update_field $index "clients_filter" "$merged_clients_json"
                                                    msg_ok "Клиенты добавлены к текущему выбору"
                                                fi
                                            else
                                                server_update_field $index "clients_filter" "$cf_json"
                                                msg_ok "Выбрано клиентов: ${#sel_arr[@]}"
                                            fi
                                        fi
                                    fi
                                fi
                            fi
                        fi
                        msg_info "Пересборка подписки..."
                        collect_keys "true"
                        ;;
                    2)
                        if [[ "$cf_type_cur" == "array" ]]; then
                            echo ""
                            echo -e "  ${WHITE}Выберите клиента для удаления из задания:${NC}"
                            local cur_i=0
                            local cur_clients_arr=()
                            while IFS= read -r ckey; do
                                local cemail
                                cemail="${ckey#*|}"
                                echo -e "  ${WHITE}  ${cur_i})${NC} ${CYAN}${cemail}${NC}"
                                cur_clients_arr+=("$ckey")
                                cur_i=$((cur_i + 1))
                            done < <(echo "$cur_cf" | jq -r '.[]')
                            echo ""
                            echo -ne "  ${GREEN}➜${NC}  ${WHITE}Номера через пробел: ${NC}"
                            read -r del_clients
                            local remaining
                            remaining=$(echo "$cur_cf" | jq -c '.')
                            for n in $del_clients; do
                                if [[ "$n" =~ ^[0-9]+$ ]]; then
                                    remaining=$(echo "$remaining" | jq "del(.[$n])" 2>/dev/null)
                                fi
                            done
                            if [[ -n "$remaining" && "$remaining" != "[]" ]]; then
                                server_update_field $index "clients_filter" "$remaining"
                                msg_ok "Выбранные клиенты удалены из задания"
                            else
                                server_update_field $index "clients_filter" '"all"'
                                msg_ok "Фильтр клиентов очищен — теперь все"
                            fi
                            msg_info "Пересборка подписки..."
                            collect_keys "true"
                        else
                            msg_warn "Сейчас выбраны все клиенты — удалять по одному нечего"
                        fi
                        ;;
                    3)
                        if [[ "$ibf_type_cur" == "array" ]]; then
                            echo ""
                            echo -e "  ${WHITE}Выберите инбаунды для удаления из задания:${NC}"
                            local inb_i=0
                            echo "$cur_ibf" | jq -r '.[]' | while IFS= read -r ibid; do
                                echo -e "  ${WHITE}  ${inb_i})${NC} ID ${CYAN}${ibid}${NC}"
                                inb_i=$((inb_i + 1))
                            done
                            echo ""
                            echo -ne "  ${GREEN}➜${NC}  ${WHITE}Номера через пробел: ${NC}"
                            read -r del_inb
                            local rem_inb
                            rem_inb=$(echo "$cur_ibf" | jq -c '.')
                            for n in $del_inb; do
                                if [[ "$n" =~ ^[0-9]+$ ]]; then
                                    rem_inb=$(echo "$rem_inb" | jq "del(.[$n])" 2>/dev/null)
                                fi
                            done
                            if [[ -n "$rem_inb" && "$rem_inb" != "[]" ]]; then
                                server_update_field $index "inbounds_filter" "$rem_inb"
                                msg_ok "Выбранные инбаунды удалены из задания"
                            else
                                server_update_field $index "inbounds_filter" '"all"'
                                msg_ok "Фильтр инбаундов очищен — теперь все"
                            fi
                            msg_info "Пересборка подписки..."
                            collect_keys "true"
                        else
                            msg_warn "Сейчас выбраны все инбаунды — удалять по одному нечего"
                        fi
                        ;;
                    4)
                        server_update_field $index "clients_filter" '"all"'
                        msg_ok "Фильтр клиентов сброшен — все клиенты включены"
                        msg_info "Пересборка подписки..."
                        collect_keys "true"
                        ;;
                    5)
                        server_update_field $index "inbounds_filter" '"all"'
                        msg_ok "Фильтр инбаундов сброшен — все инбаунды включены"
                        msg_info "Пересборка подписки..."
                        collect_keys "true"
                        ;;
                esac
                pause_key
                ;;
            10)
                if [[ "$enabled" == "true" ]]; then
                    server_update_field $index "enabled" "false"
                    msg_ok "Сервер отключён"
                else
                    server_update_field $index "enabled" "true"
                    msg_ok "Сервер включён"
                fi
                sleep 1
                ;;
            11)
                local srv_data
                srv_data=$(server_get $index)
                local t_addr t_port t_user t_pass t_wp t_proto
                t_addr=$(echo "$srv_data" | jq -r '.address')
                t_port=$(echo "$srv_data" | jq -r '.port')
                t_user=$(echo "$srv_data" | jq -r '.username')
                t_pass=$(_decrypt "$(echo "$srv_data" | jq -r '.password')")
                t_wp=$(echo "$srv_data" | jq -r '.web_path // ""')
                t_proto=$(echo "$srv_data" | jq -r '.protocol // "https"')

                api_test_connection "$t_addr" "$t_port" "$t_user" "$t_pass" "$t_wp" "$t_proto"
                pause_key
                ;;
            12)
                echo -ne "\n  ${RED}Удалить сервер \"$name\"? (yes/no): ${NC}"
                read -r confirm
                if [[ "$confirm" == "yes" ]]; then
                    server_delete $index
                    msg_ok "Сервер \"$name\" удалён"
                    pause_key
                    return
                else
                    msg_info "Удаление отменено"
                    sleep 1
                fi
                ;;
            *)
                msg_err "Неверный выбор"
                sleep 1
                ;;
        esac
    done
}

menu_select_inbounds() {
    local index=$1

    print_header
    print_section_header "ВЫБОР ИНБАУНДОВ"

    local srv
    srv=$(server_get $index)
    local t_addr t_port t_user t_pass t_wp t_proto
    t_addr=$(echo "$srv" | jq -r '.address')
    t_port=$(echo "$srv" | jq -r '.port')
    t_user=$(echo "$srv" | jq -r '.username')
    t_pass=$(_decrypt "$(echo "$srv" | jq -r '.password')")
    t_wp=$(echo "$srv" | jq -r '.web_path // ""')
    t_proto=$(echo "$srv" | jq -r '.protocol // "https"')

    spin_start "Подключение к панели..."
    local cookie_f
    cookie_f=$(mktemp)
    api_login "$t_addr" "$t_port" "$t_user" "$t_pass" "$t_wp" "$t_proto" "$cookie_f"
    local rc=$?

    if [[ $rc -ne 0 ]]; then
        local alt_proto
        [[ "$t_proto" == "https" ]] && alt_proto="http" || alt_proto="https"
        api_login "$t_addr" "$t_port" "$t_user" "$t_pass" "$t_wp" "$alt_proto" "$cookie_f"
        rc=$?
        [[ $rc -eq 0 ]] && t_proto="$alt_proto"
    fi
    spin_stop

    if [[ $rc -ne 0 ]]; then
        msg_err "Не удалось подключиться к панели"
        rm -f "$cookie_f"
        pause_key
        return
    fi

    spin_start "Загрузка инбаундов..."
    local inbounds
    inbounds=$(api_get_inbounds "$t_addr" "$t_port" "$t_wp" "$t_proto" "$cookie_f")
    spin_stop
    rm -f "$cookie_f" 2>/dev/null

    local inb_count
    inb_count=$(echo "$inbounds" | jq 'length' 2>/dev/null || echo "0")

    if [[ "$inb_count" -eq 0 ]]; then
        msg_warn "Инбаунды не найдены"
        pause_key
        return
    fi

    echo -e "  ${WHITE}Доступные инбаунды:${NC}"
    echo ""

    local vless_ids=()
    local idx=0
    for ((i=0; i<inb_count; i++)); do
        local inb_protocol inb_id inb_remark inb_port inb_enable
        inb_protocol=$(echo "$inbounds" | jq -r ".[$i].protocol" 2>/dev/null)
        inb_id=$(echo "$inbounds" | jq -r ".[$i].id" 2>/dev/null)
        inb_remark=$(echo "$inbounds" | jq -r ".[$i].remark" 2>/dev/null)
        inb_port=$(echo "$inbounds" | jq -r ".[$i].port" 2>/dev/null)
        inb_enable=$(echo "$inbounds" | jq -r ".[$i].enable" 2>/dev/null)

        case "$inb_protocol" in
            vless|vmess|trojan|shadowsocks|hysteria2)
            local en_icon="${GREEN}●${NC}"
            [[ "$inb_enable" == "false" ]] && en_icon="${RED}○${NC}"

            local clients_count stmp
            stmp=$(echo "$inbounds" | jq -r ".[$i].settings" 2>/dev/null)
            clients_count=$(echo "$stmp" | jq '.clients | length' 2>/dev/null || echo "?")

            echo -e "  ${WHITE}  ${idx}) ${en_icon} [${inb_protocol}] ${inb_remark} │ :${inb_port} │ ${clients_count} кл.${NC}"
            vless_ids+=("$inb_id")
            idx=$((idx + 1))
            ;;
        esac
    done

    if [[ ${#vless_ids[@]} -eq 0 ]]; then
        msg_warn "Поддерживаемые инбаунды не найдены"
        pause_key
        return
    fi

    echo ""
    echo -e "  ${WHITE}  a) Выбрать ВСЕ${NC}"
    echo -e "  ${WHITE}  0) ← Назад${NC}"
    echo ""
    echo -e "  ${WHITE}Номера через пробел (например: 1 2)${NC}"
    echo -ne "  ${WHITE}> ${NC}"
    read -r selected

    if [[ "$selected" == "0" ]]; then
        return
    elif [[ -z "$selected" || "$selected" =~ ^[Aa]$ ]]; then
        server_update_field $index "inbounds_filter" '"all"'
        msg_ok "Установлено: все инбаунды"
    elif [[ -n "$selected" ]]; then
        local sel_ids=()
        for num in $selected; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [[ $num -ge 0 ]] && [[ $num -lt ${#vless_ids[@]} ]]; then
                sel_ids+=("${vless_ids[$num]}")
            fi
        done
        if [[ ${#sel_ids[@]} -gt 0 ]]; then
            local filter_json
            filter_json=$(printf '%s\n' "${sel_ids[@]}" | jq -R 'tonumber' | jq -s '.')
            local current_filter
            current_filter=$(echo "$srv" | jq '.inbounds_filter // "all"' 2>/dev/null)
            echo ""
            echo -e "  ${WHITE}Как применить выбор?${NC}"
            echo -e "  ${WHITE}  1) Добавить к уже выбранным${NC}"
            echo -e "  ${WHITE}  2) Использовать только новый выбор${NC}"
            echo -ne "  ${GREEN}➜${NC}  ${WHITE}Выбор [2]: ${NC}"
            read -r apply_mode
            if [[ "$apply_mode" == "1" ]]; then
                local current_type
                current_type=$(echo "$current_filter" | jq -r 'if type == "string" then . else "array" end' 2>/dev/null)
                if [[ "$current_type" == "all" ]]; then
                    server_update_field $index "inbounds_filter" '"all"'
                    msg_ok "Уже выбраны все инбаунды — добавление не требуется"
                else
                    local merged_json
                    merged_json=$(jq -nc --argjson a "$current_filter" --argjson b "$filter_json" '$a + $b | unique')
                    server_update_field $index "inbounds_filter" "$merged_json"
                    msg_ok "Инбаунды добавлены к текущему выбору"
                fi
            else
                server_update_field $index "inbounds_filter" "$filter_json"
                msg_ok "Выбрано инбаундов: ${#sel_ids[@]}"
            fi
        fi
    fi

    msg_info "Пересборка подписки..."
    collect_keys "true"
    sleep 1
}


menu_update_interval() {
    while true; do
        print_header
        print_section_header "НАСТРОЙКА АВТООБНОВЛЕНИЯ"

        local current_interval current_unit
        current_interval=$(config_get "update_interval" "59")
        current_unit=$(config_get "update_unit" "minutes")

        if [[ "$current_unit" == "minutes" && "$current_interval" =~ ^[0-9]+$ && "$current_interval" -gt 59 ]]; then
            current_interval="59"
            config_set "update_interval" "59"
        elif [[ "$current_unit" == "hours" && "$current_interval" =~ ^[0-9]+$ && "$current_interval" -gt 23 ]]; then
            current_interval="23"
            config_set "update_interval" "23"
        elif [[ "$current_unit" == "days" && "$current_interval" =~ ^[0-9]+$ && "$current_interval" -gt 30 ]]; then
            current_interval="30"
            config_set "update_interval" "30"
        fi

        local unit_text=""
        case "$current_unit" in
            minutes) unit_text="мин." ;;
            hours) unit_text="ч." ;;
            days) unit_text="дн." ;;
        esac

        local cron_current
        cron_current=$(cron_get)
        local cron_status
        if [[ -n "$cron_current" ]]; then
            cron_status="${GREEN}● Активно${NC}"
        else
            cron_status="${RED}○ Не настроено${NC}"
        fi

        echo -e "  ${WHITE}Текущий интервал:${NC} ${CYAN}${current_interval} ${unit_text}${NC}"
        echo -e "  ${WHITE}Статус cron:${NC}      ${cron_status}"
        echo ""
        print_thin_line
        echo ""
        echo -e "  ${WHITE}  1) Интервал в минутах (1-59)${NC}"
        echo -e "  ${WHITE}  2) Интервал в часах (1-23)${NC}"
        echo -e "  ${WHITE}  3) Интервал в днях (1-30)${NC}"
        echo -e "  ${WHITE}  4) Отключить автообновление${NC}"
        echo -e "  ${WHITE}  5) Включить с текущими настройками${NC}"
        echo ""
        echo -e "  ${WHITE}  0) ← Назад${NC}"
        echo ""
        echo -ne "  ${WHITE}Выберите действие: ${NC}"
        read -r choice

        case "$choice" in
            0) return ;;
            1)
                echo -ne "  ${WHITE}Интервал в минутах (1-59): ${NC}"
                read -r val
                if [[ "$val" =~ ^[0-9]+$ ]] && [[ "$val" -ge 1 ]] && [[ "$val" -le 59 ]]; then
                    config_set "update_interval" "$val"
                    config_set "update_unit" "minutes"
                    cron_set "$val" "minutes"
                    msg_ok "Автообновление: каждые $val мин."
                else
                    msg_err "Неверное значение"
                fi
                pause_key
                ;;
            2)
                echo -ne "  ${WHITE}Интервал в часах (1-23): ${NC}"
                read -r val
                if [[ "$val" =~ ^[0-9]+$ ]] && [[ "$val" -ge 1 ]] && [[ "$val" -le 23 ]]; then
                    config_set "update_interval" "$val"
                    config_set "update_unit" "hours"
                    cron_set "$val" "hours"
                    msg_ok "Автообновление: каждые $val ч."
                else
                    msg_err "Неверное значение"
                fi
                pause_key
                ;;
            3)
                echo -ne "  ${WHITE}Интервал в днях (1-30): ${NC}"
                read -r val
                if [[ "$val" =~ ^[0-9]+$ ]] && [[ "$val" -ge 1 ]] && [[ "$val" -le 30 ]]; then
                    config_set "update_interval" "$val"
                    config_set "update_unit" "days"
                    cron_set "$val" "days"
                    msg_ok "Автообновление: каждые $val дн."
                else
                    msg_err "Неверное значение"
                fi
                pause_key
                ;;
            4)
                cron_remove
                msg_ok "Автообновление отключено"
                pause_key
                ;;
            5)
                cron_set "$current_interval" "$current_unit"
                msg_ok "Cron активирован: каждые $current_interval $unit_text"
                pause_key
                ;;
        esac
    done
}


menu_sub_title() {
    while true; do
        print_header
        print_section_header "НАСТРОЙКИ ПОДПИСКИ"

        local current_title
        current_title=$(config_get "sub_title" "3X-UI-CSM-SUB")
        
        local update_interval
        update_interval=$(config_get "client_update_interval" "12")
        
        local support_url
        support_url=$(config_get "support_url" "https://t.me/LarsInvilink")
        
        local sub_upload sub_download sub_total sub_expire
        sub_upload=$(config_get "sub_upload" "0")
        sub_download=$(config_get "sub_download" "0")
        sub_total=$(config_get "sub_total" "0")
        sub_expire=$(config_get "sub_expire" "1798761600")
        
        local header_profile_title
        header_profile_title=$(config_get "header_profile_title" "true")
        local header_profile_update_interval
        header_profile_update_interval=$(config_get "header_profile_update_interval" "true")
        local header_support_url
        header_support_url=$(config_get "header_support_url" "false")
        local header_profile_web_page_url
        header_profile_web_page_url=$(config_get "header_profile_web_page_url" "false")
        local header_subscription_userinfo
        header_subscription_userinfo=$(config_get "header_subscription_userinfo" "false")
        
        local total_gb=$(( sub_total / 1073741824 ))
        local status_title="${RED}выкл${NC}"
        local status_update="${RED}выкл${NC}"
        local status_support="${RED}выкл${NC}"
        local status_web="${RED}выкл${NC}"
        local status_userinfo="${RED}выкл${NC}"
        [[ "$header_profile_title" == "true" ]] && status_title="${GREEN}вкл${NC}"
        [[ "$header_profile_update_interval" == "true" ]] && status_update="${GREEN}вкл${NC}"
        [[ "$header_support_url" == "true" ]] && status_support="${GREEN}вкл${NC}"
        [[ "$header_profile_web_page_url" == "true" ]] && status_web="${GREEN}вкл${NC}"
        [[ "$header_subscription_userinfo" == "true" ]] && status_userinfo="${GREEN}вкл${NC}"

        local current_title_display="${DARK_GRAY}none${NC}"
        local update_interval_display="${DARK_GRAY}none${NC}"
        local traffic_display="${DARK_GRAY}none${NC}"
        local support_display="${DARK_GRAY}none${NC}"

        [[ "$header_profile_title" == "true" ]] && current_title_display="${CYAN}${current_title}${NC}"
        [[ "$header_profile_update_interval" == "true" ]] && update_interval_display="${CYAN}каждые ${update_interval} ч.${NC}"
        [[ "$header_subscription_userinfo" == "true" ]] && traffic_display="${CYAN}${total_gb} GB${NC}"
        if [[ ( "$header_support_url" == "true" || "$header_profile_web_page_url" == "true" ) && -n "$support_url" ]]; then
            support_display="${CYAN}${support_url}${NC}"
        fi

        echo -e "  ${WHITE}Текущие настройки:${NC}"
        echo ""
        echo -e "  ${GRAY}├─${NC} ${WHITE}Название:${NC}        ${current_title_display}"
        echo -e "  ${GRAY}├─${NC} ${WHITE}Обновление:${NC}      ${update_interval_display}"
        echo -e "  ${GRAY}├─${NC} ${WHITE}Трафик:${NC}          ${traffic_display}"
        echo -e "  ${GRAY}├─${NC} ${WHITE}Ссылка:${NC}          ${support_display}"
        echo -e "  ${GRAY}├─${NC} ${WHITE}#profile-title:${NC}            ${status_title}"
        echo -e "  ${GRAY}├─${NC} ${WHITE}#profile-update-interval:${NC}  ${status_update}"
        echo -e "  ${GRAY}├─${NC} ${WHITE}#support-url:${NC}              ${status_support}"
        echo -e "  ${GRAY}├─${NC} ${WHITE}#profile-web-page-url:${NC}     ${status_web}"
        echo -e "  ${GRAY}└─${NC} ${WHITE}#subscription-userinfo:${NC}    ${status_userinfo}"
        echo ""
        msg_hint "Название отображается в VPN-клиентах при добавлении подписки"
        msg_hint "Поддерживаются эмодзи и флаги стран: 🇷🇺 🇺🇸 🇩🇪 🇳🇱 🇫🇮 🚀 ⚡ 🔒"
        msg_warn "Некоторые клиенты не поддерживают заголовки. При проблемах может потребоваться отключить все или часть заголовков."
        echo ""
        print_thin_line
        echo ""
        echo -e "  ${WHITE}  1) Изменить название подписки${NC}"
        echo -e "  ${WHITE}  2) Добавить флаги/эмодзи к названию${NC}"
        echo -e "  ${WHITE}  3) Интервал обновления для клиента${NC}"
        echo -e "  ${WHITE}  4) Ссылка поддержки / реклама${NC}"
        echo -e "  ${WHITE}  5) Информация о трафике и сроке${NC}"
        echo -e "  ${WHITE}  6) Включить/отключить заголовки${NC}"
        echo -e "  ${WHITE}  7) Предпросмотр заголовков${NC}"
        echo ""
        echo -e "  ${WHITE}  0) ← Назад${NC}"
        echo ""
        echo -ne "  ${WHITE}Выберите действие: ${NC}"
        read -r choice

        case "$choice" in
            0) return ;;
            1)
                echo ""
                echo -e "  ${WHITE}Введите новое название подписки:${NC}"
                msg_hint "Можно использовать эмодзи и флаги: 🇷🇺 VPN Service 🚀"
                echo ""
                echo -ne "  ${GREEN}➜${NC}  ${WHITE}Название: ${NC}"
                read -r new_title
                if [[ -n "$new_title" ]]; then
                    config_set "sub_title" "$new_title"
                    msg_ok "Название обновлено: $new_title"
                    msg_info "Обновите подписку (пункт 5 главного меню)"
                fi
                pause_key
                ;;
            2)
                echo ""
                echo -e "  ${WHITE}Выберите флаг/эмодзи для добавления к названию:${NC}"
                echo ""
                echo -e "  ${WHITE}Флаги стран:${NC}"
                echo -e "    1) 🇷🇺 Россия      5) 🇫🇮 Финляндия    9) 🇬🇧 Британия"
                echo -e "    2) 🇺🇸 США         6) 🇫🇷 Франция     10) 🇯🇵 Япония"
                echo -e "    3) 🇩🇪 Германия    7) 🇳🇱 Нидерланды  11) 🇸🇬 Сингапур"
                echo -e "    4) 🇺🇦 Украина     8) 🇵🇱 Польша      12) 🇹🇷 Турция"
                echo ""
                echo -e "  ${WHITE}Эмодзи:${NC}"
                echo -e "   13) 🚀 Ракета      16) ⚡ Молния       19) 🌐 Глобус"
                echo -e "   14) 🔒 Замок       17) ✨ Искры        20) 💎 Кристалл"
                echo -e "   15) 🛡️ Щит         18) 🔥 Огонь        21) ⭐ Звезда"
                echo ""
                echo -ne "  ${WHITE}Номер (или введите свой эмодзи): ${NC}"
                read -r emoji_choice
                
                local emoji=""
                case "$emoji_choice" in
                    1) emoji="🇷🇺" ;; 2) emoji="🇺🇸" ;; 3) emoji="🇩🇪" ;;
                    4) emoji="🇺🇦" ;; 5) emoji="🇫🇮" ;; 6) emoji="🇫🇷" ;;
                    7) emoji="🇳🇱" ;; 8) emoji="🇵🇱" ;; 9) emoji="🇬🇧" ;;
                    10) emoji="🇯🇵" ;; 11) emoji="🇸🇬" ;; 12) emoji="🇹🇷" ;;
                    13) emoji="🚀" ;; 14) emoji="🔒" ;; 15) emoji="🛡️" ;;
                    16) emoji="⚡" ;; 17) emoji="✨" ;; 18) emoji="🔥" ;;
                    19) emoji="🌐" ;; 20) emoji="💎" ;; 21) emoji="⭐" ;;
                    *) emoji="$emoji_choice" ;;
                esac
                
                if [[ -n "$emoji" ]]; then
                    echo ""
                    echo -e "  ${WHITE}Куда добавить ${CYAN}${emoji}${WHITE}?${NC}"
                    echo -e "    1) В начало названия"
                    echo -e "    2) В конец названия"
                    echo -ne "  ${WHITE}Выбор [1]: ${NC}"
                    read -r position
                    
                    local new_title
                    if [[ "$position" == "2" ]]; then
                        new_title="${current_title} ${emoji}"
                    else
                        new_title="${emoji} ${current_title}"
                    fi
                    
                    config_set "sub_title" "$new_title"
                    msg_ok "Название обновлено: $new_title"
                fi
                pause_key
                ;;
            3)
                echo ""
                echo -e "  ${WHITE}Интервал автообновления подписки в клиенте:${NC}"
                echo ""
                msg_hint "Это значение указывает клиенту как часто проверять обновления"
                msg_hint "Рекомендуется: 1-24 часа"
                echo ""
                echo -e "  ${WHITE}Текущее значение:${NC} ${CYAN}${update_interval} часов${NC}"
                echo ""
                echo -ne "  ${GREEN}➜${NC}  ${WHITE}Новый интервал (в часах) [${update_interval}]: ${NC}"
                read -r new_interval
                
                if [[ -n "$new_interval" && "$new_interval" =~ ^[0-9]+$ ]]; then
                    config_set "client_update_interval" "$new_interval"
                    msg_ok "Интервал обновления: $new_interval ч."
                elif [[ -z "$new_interval" ]]; then
                    msg_info "Оставлено без изменений"
                else
                    msg_err "Введите число (например: 1, 12, 24, 48)"
                fi
                pause_key
                ;;
            4)
                echo ""
                echo -e "  ${WHITE}Ссылка поддержки / рекламная строка:${NC}"
                echo ""
                msg_hint "Эта ссылка будет отображаться в клиентах, если заголовки включены"
                msg_hint "Примеры: t.me/your_channel, example.com/support"
                echo ""
                if [[ -n "$support_url" ]]; then
                    echo -e "  ${WHITE}Текущая ссылка:${NC} ${CYAN}${support_url}${NC}"
                else
                    echo -e "  ${WHITE}Текущая ссылка:${NC} ${DARK_GRAY}не задана${NC}"
                fi
                echo ""
                echo -ne "  ${GREEN}➜${NC}  ${WHITE}Новая ссылка (пусто для удаления): ${NC}"
                read -r new_url
                
                config_set "support_url" "$new_url"
                if [[ -n "$new_url" ]]; then
                    msg_ok "Ссылка установлена: $new_url"
                else
                    msg_ok "Ссылка удалена"
                fi
                pause_key
                ;;
            5)
                echo ""
                echo -e "  ${WHITE}Информация о трафике и сроке подписки${NC}"
                echo ""
                echo -e "  ${GRAY}Эти данные отображаются в VPN-клиентах:${NC}"
                echo -e "  ${GRAY}полоса использования трафика, оставшийся объём,${NC}"
                echo -e "  ${GRAY}дата истечения подписки.${NC}"
                echo ""
                print_thin_line
                echo ""
                echo -e "  ${WHITE}upload${NC}   ${GRAY}- отправлено (байт). Показывает клиенту${NC}"
                echo -e "           ${GRAY}сколько трафика уже загружено.${NC}"
                echo -e "  ${WHITE}download${NC} ${GRAY}- скачано (байт). Показывает клиенту${NC}"
                echo -e "           ${GRAY}сколько трафика уже скачано.${NC}"
                echo -e "  ${WHITE}total${NC}    ${GRAY}- лимит трафика (байт). Общий объём.${NC}"
                echo -e "           ${GRAY}0 = безлимит, 107374182400 = 100 GB${NC}"
                echo -e "  ${WHITE}expire${NC}   ${GRAY}- дата истечения (UNIX timestamp).${NC}"
                echo -e "           ${GRAY}0 = без ограничения по времени.${NC}"
                echo ""
                print_thin_line
                echo ""
                echo -e "  ${WHITE}Текущие значения:${NC}"
                echo -e "  ${GRAY}├─${NC} upload:   ${CYAN}${sub_upload}${NC} байт"
                echo -e "  ${GRAY}├─${NC} download: ${CYAN}${sub_download}${NC} байт"
                echo -e "  ${GRAY}├─${NC} total:    ${CYAN}${sub_total}${NC} байт (${total_gb} GB)"
                if [[ "$sub_expire" == "0" ]]; then
                    echo -e "  ${GRAY}└─${NC} expire:   ${CYAN}0${NC} (бессрочно)"
                else
                    local expire_date
                    expire_date=$(date -d "@${sub_expire}" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "N/A")
                    echo -e "  ${GRAY}└─${NC} expire:   ${CYAN}${sub_expire}${NC} (${expire_date})"
                fi
                echo ""
                print_thin_line
                echo ""
                echo -e "  ${WHITE}Что изменить?${NC}"
                echo -e "  ${WHITE}  a) upload (отправлено)${NC}"
                echo -e "  ${WHITE}  b) download (скачано)${NC}"
                echo -e "  ${WHITE}  c) total (лимит трафика в GB)${NC}"
                echo -e "  ${WHITE}  d) expire (срок действия)${NC}"
                echo -e "  ${WHITE}  0) Назад${NC}"
                echo ""
                echo -ne "  ${GREEN}➜${NC}  ${WHITE}Выбор: ${NC}"
                read -r ui_choice
                
                case "$ui_choice" in
                    a)
                        echo -ne "  ${WHITE}upload (байт) [${sub_upload}]: ${NC}"
                        read -r val
                        if [[ -n "$val" && "$val" =~ ^[0-9]+$ ]]; then
                            config_set "sub_upload" "$val"
                            msg_ok "upload = $val"
                        fi
                        ;;
                    b)
                        echo -ne "  ${WHITE}download (байт) [${sub_download}]: ${NC}"
                        read -r val
                        if [[ -n "$val" && "$val" =~ ^[0-9]+$ ]]; then
                            config_set "sub_download" "$val"
                            msg_ok "download = $val"
                        fi
                        ;;
                    c)
                        echo -e "  ${GRAY}Введите лимит в гигабайтах (GB).${NC}"
                        echo -e "  ${GRAY}Примеры: 0 = безлимит, 100 = 100GB, 500 = 500GB${NC}"
                        echo ""
                        echo -ne "  ${WHITE}Лимит (GB) [${total_gb}]: ${NC}"
                        read -r val
                        if [[ -n "$val" && "$val" =~ ^[0-9]+$ ]]; then
                            local total_bytes=$(( val * 1073741824 ))
                            config_set "sub_total" "$total_bytes"
                            msg_ok "total = ${val} GB (${total_bytes} байт)"
                        fi
                        ;;
                    d)
                        echo -e "  ${GRAY}Введите дату истечения подписки.${NC}"
                        echo -e "  ${GRAY}Формат: YYYY-MM-DD (например 2027-01-01)${NC}"
                        echo -e "  ${GRAY}Или 0 для бессрочной подписки.${NC}"
                        echo ""
                        echo -ne "  ${WHITE}Дата или 0 [0]: ${NC}"
                        read -r val
                        if [[ "$val" == "0" || -z "$val" ]]; then
                            config_set "sub_expire" "0"
                            msg_ok "expire = 0 (бессрочно)"
                        elif [[ "$val" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
                            local ts
                            ts=$(date -d "$val" '+%s' 2>/dev/null)
                            if [[ -n "$ts" ]]; then
                                config_set "sub_expire" "$ts"
                                msg_ok "expire = ${ts} (${val})"
                            else
                                msg_err "Неверный формат даты"
                            fi
                        else
                            msg_err "Введите дату в формате YYYY-MM-DD или 0"
                        fi
                        ;;
                esac
                msg_info "Обновите подписку (пункт 5 главного меню) для применения"
                pause_key
                ;;
            6)
                echo ""
                echo -e "  ${WHITE}Управление заголовками подписки:${NC}"
                echo ""
                echo -e "  ${WHITE}  1) #profile-title            ${status_title}${NC}"
                echo -e "  ${WHITE}  2) #profile-update-interval  ${status_update}${NC}"
                echo -e "  ${WHITE}  3) #support-url              ${status_support}${NC}"
                echo -e "  ${WHITE}  4) #profile-web-page-url     ${status_web}${NC}"
                echo -e "  ${WHITE}  5) #subscription-userinfo    ${status_userinfo}${NC}"
                echo ""
                msg_hint "По умолчанию включены только profile-title и profile-update-interval"
                echo -ne "  ${GREEN}➜${NC}  ${WHITE}Что переключить [1-5, 0 назад]: ${NC}"
                read -r hdr_choice
                case "$hdr_choice" in
                    1)
                        [[ "$header_profile_title" == "true" ]] && config_set "header_profile_title" "false" || config_set "header_profile_title" "true"
                        ;;
                    2)
                        [[ "$header_profile_update_interval" == "true" ]] && config_set "header_profile_update_interval" "false" || config_set "header_profile_update_interval" "true"
                        ;;
                    3)
                        [[ "$header_support_url" == "true" ]] && config_set "header_support_url" "false" || config_set "header_support_url" "true"
                        ;;
                    4)
                        [[ "$header_profile_web_page_url" == "true" ]] && config_set "header_profile_web_page_url" "false" || config_set "header_profile_web_page_url" "true"
                        ;;
                    5)
                        [[ "$header_subscription_userinfo" == "true" ]] && config_set "header_subscription_userinfo" "false" || config_set "header_subscription_userinfo" "true"
                        ;;
                    0) ;;
                esac
                msg_info "Обновите подписку (пункт 5 главного меню) для применения"
                pause_key
                ;;
            7)
                echo ""
                echo -e "  ${WHITE}Предпросмотр заголовков подписки:${NC}"
                echo ""
                print_thin_line
                
                if [[ "$header_profile_title" == "true" ]]; then
                    echo -e "  ${GRAY}#profile-title: ${current_title}${NC}"
                fi
                if [[ "$header_profile_update_interval" == "true" ]]; then
                    echo -e "  ${GRAY}#profile-update-interval: ${update_interval}${NC}"
                fi
                if [[ "$header_support_url" == "true" && -n "$support_url" ]]; then
                    echo -e "  ${GRAY}#support-url: ${support_url}${NC}"
                fi
                if [[ "$header_profile_web_page_url" == "true" && -n "$support_url" ]]; then
                    echo -e "  ${GRAY}#profile-web-page-url: ${support_url}${NC}"
                fi
                if [[ "$header_subscription_userinfo" == "true" ]]; then
                    echo -e "  ${GRAY}#subscription-userinfo: upload=${sub_upload}; download=${sub_download}; total=${sub_total}; expire=${sub_expire}${NC}"
                fi
                
                print_thin_line
                echo ""
                msg_info "Отключённые заголовки не будут записаны в подписку"
                pause_key
                ;;
        esac
    done
}


menu_manual_update() {
    collect_keys "false"
}


menu_sub_info() {
    while true; do
        # Обновляем переменные файла подписки
        init_sub_vars
        
        print_header
        print_section_header "ФАЙЛ ПОДПИСКИ"

        # Получаем настройки
        local use_domain=$(config_get "use_domain" "false")
        local domain=$(config_get "domain" "")
        local use_ssl=$(config_get "use_ssl" "false")
        local web_port=$(config_get "web_port" "8443")
        local encode_url=$(config_get "encode_url" "false")
        local encoded_path=$(config_get "encoded_path" "")

        local server_ip
        server_ip=$(curl -4 -s --connect-timeout 3 ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "?.?.?.?")

        # Формируем URL
        local protocol="http"
        [[ "$use_ssl" == "true" ]] && protocol="https"
        
        local host="$server_ip"
        [[ "$use_domain" == "true" && -n "$domain" ]] && host="$domain"
        
        local path="/${SUB_FILENAME}"
        [[ "$encode_url" == "true" && -n "$encoded_path" ]] && path="/${encoded_path}"
        
        local port_str=":${web_port}"
        [[ "$web_port" == "443" || "$web_port" == "80" ]] && port_str=""
        
        local sub_url="${protocol}://${host}${port_str}${path}"

        local encode_content
        encode_content=$(config_get "encode_content" "true")
        
        if [[ -f "$SUB_FILE" ]]; then
            local file_size file_mod key_count
            file_size=$(stat -c %s "$SUB_FILE" 2>/dev/null || echo "0")
            file_mod=$(stat -c %y "$SUB_FILE" 2>/dev/null | cut -d. -f1)

            key_count=0
            if [[ -s "$SUB_FILE" ]]; then
                if [[ "$encode_content" == "true" ]]; then
                    key_count=$(base64 -d "$SUB_FILE" 2>/dev/null | grep -cE "^(vless|vmess|trojan|ss|hysteria2)://" || echo "0")
                else
                    key_count=$(grep -cE "^(vless|vmess|trojan|ss|hysteria2)://" "$SUB_FILE" || echo "0")
                fi
            fi

            local encode_content_label="${RED}Выкл (plain text)${NC}"
            [[ "$encode_content" == "true" ]] && encode_content_label="${GREEN}Вкл (base64)${NC}"
            local encode_url_label="${RED}Выкл${NC}"
            [[ "$encode_url" == "true" ]] && encode_url_label="${GREEN}Вкл${NC} ${GRAY}(/${encoded_path})${NC}"

            echo -e "  ${GRAY}├─${NC} ${WHITE}Путь:${NC}                ${CYAN}${SUB_FILE}${NC}"
            echo -e "  ${GRAY}├─${NC} ${WHITE}Размер:${NC}              ${CYAN}${file_size} байт${NC}"
            echo -e "  ${GRAY}├─${NC} ${WHITE}Обновлён:${NC}            ${CYAN}${file_mod}${NC}"
            echo -e "  ${GRAY}├─${NC} ${WHITE}Ключей:${NC}              ${CYAN}${key_count}${NC}"
            echo -e "  ${GRAY}├─${NC} ${WHITE}Кодирование URL:${NC}     ${encode_url_label}"
            echo -e "  ${GRAY}└─${NC} ${WHITE}Кодирование файла:${NC}   ${encode_content_label}"
        else
            msg_warn "Файл подписки не создан"
        fi

        echo ""
        echo -e "  ${WHITE}URL для VPN-клиентов:${NC}"
        echo -e "     ${GREEN}${sub_url}${NC}"

        echo ""
        print_thin_line
        echo ""
        echo -e "  ${WHITE}  1) Редактировать ключи${NC}"
        echo -e "  ${WHITE}  2) Показать все ключи${NC}"
        echo -e "  ${WHITE}  3) Скопировать URL${NC}"
        echo -e "  ${WHITE}  4) Настройки домена и SSL${NC}"
        if [[ "$encode_content" == "true" ]]; then
            echo -e "  ${WHITE}  5) Отключить кодирование base64${NC}"
        else
            echo -e "  ${WHITE}  5) Включить кодирование base64${NC}"
        fi
        if [[ "$encode_url" == "true" ]]; then
            echo -e "  ${WHITE}  6) Отключить кодирование URL${NC}"
        else
            echo -e "  ${WHITE}  6) Включить кодирование URL${NC}"
        fi
        echo -e "  ${WHITE}  7) Проверить доступность URL${NC}"
        echo -e "  ${WHITE}  8) Показать QR-код подписки${NC}"
        echo -e "  ${WHITE}  9) Изменить имя файла подписки${NC}"
        echo -e "  ${RED}  10) Очистить файл подписки${NC}"
        echo ""
        echo -e "  ${WHITE}  0) ← Назад${NC}"
        echo ""
        echo -ne "  ${WHITE}Выберите действие: ${NC}"
        read -r choice

        case "$choice" in
            0) return ;;
            1)
                if [[ -f "$SUB_FILE" && -s "$SUB_FILE" ]]; then
                    local temp_edit
                    temp_edit=$(mktemp)
                    
                    if [[ "$encode_content" == "true" ]]; then
                        base64 -d "$SUB_FILE" > "$temp_edit" 2>/dev/null
                    else
                        cp "$SUB_FILE" "$temp_edit"
                    fi
                    
                    nano "$temp_edit"
                    
                    echo ""
                    echo -ne "  ${WHITE}Сохранить изменения? (y/n): ${NC}"
                    read -r save_confirm
                    
                    if [[ "$save_confirm" =~ ^[Yy]$ ]]; then
                        if [[ "$encode_content" == "true" ]]; then
                            base64 -w0 "$temp_edit" > "$SUB_FILE" 2>/dev/null || base64 "$temp_edit" | tr -d '\n' > "$SUB_FILE" 2>/dev/null
                        else
                            cp "$temp_edit" "$SUB_FILE"
                        fi
                        cp "$temp_edit" "$RAW_FILE" 2>/dev/null
                        msg_ok "Изменения сохранены"
                    else
                        msg_info "Изменения отменены"
                    fi
                    
                    rm -f "$temp_edit" 2>/dev/null
                else
                    msg_err "Файл пуст. Сначала обновите подписку (пункт 5)"
                fi
                pause_key
                ;;
            2)
                echo ""
                if [[ -s "$SUB_FILE" ]]; then
                    echo -e "  ${WHITE}Ключи (первые 50):${NC}"
                    print_thin_line
                    local decoded total_lines
                    if [[ "$encode_content" == "true" ]]; then
                        decoded=$(base64 -d "$SUB_FILE" 2>/dev/null)
                    else
                        decoded=$(cat "$SUB_FILE")
                    fi
                    total_lines=$(echo "$decoded" | wc -l)

                    echo "$decoded" | head -50 | while IFS= read -r line; do
                        echo -e "  ${GRAY}$line${NC}"
                    done

                    if [[ $total_lines -gt 50 ]]; then
                        echo -e "\n  ${YELLOW}... показано 50 из $total_lines${NC}"
                    fi
                else
                    msg_warn "Файл пуст"
                fi
                pause_key
                ;;
            3)
                echo ""
                echo -e "  ${WHITE}Скопируйте URL:${NC}"
                echo ""
                echo -e "  ${GREEN}${sub_url}${NC}"
                echo ""
                pause_key
                ;;
            4)
                menu_domain_settings
                ;;
            5)
                echo ""
                if [[ "$encode_content" == "true" ]]; then
                    config_set "encode_content" "false"
                    msg_ok "Кодирование base64 отключено"
                    msg_info "Файл подписки будет в plain text"
                else
                    config_set "encode_content" "true"
                    msg_ok "Кодирование base64 включено"
                fi
                msg_info "Обновите подписку (пункт 5 главного меню) для применения"
                pause_key
                ;;
            6)
                echo ""
                if [[ "$encode_url" == "true" ]]; then
                    config_set "encode_url" "false"
                    config_set "encoded_path" ""
                    update_nginx_config
                    msg_ok "Кодирование URL отключено"
                    msg_info "URL теперь использует путь: /${SUB_FILENAME}"
                else
                    local random_string
                    local new_encoded_path
                    random_string=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 16)
                    new_encoded_path=$(echo -n "$random_string" | base64 | tr -d '=' | tr '+/' '-_')
                    config_set "encode_url" "true"
                    config_set "encoded_path" "$new_encoded_path"
                    update_nginx_config
                    msg_ok "Кодирование URL включено"
                    msg_info "Новый путь: /${new_encoded_path}"
                fi
                pause_key
                ;;
            7)
                echo ""
                msg_info "Проверка доступности URL подписки..."
                echo ""
                
                local local_code external_code tcp_ok
                tcp_ok="false"
                
                if timeout 3 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/${web_port}" 2>/dev/null; then
                    tcp_ok="true"
                    msg_ok "TCP-порт ${web_port} на localhost открыт"
                else
                    msg_err "TCP-порт ${web_port} на localhost закрыт"
                fi
                
                local_code=$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://127.0.0.1:${web_port}${path}" 2>/dev/null || echo "000")
                if [[ "$local_code" == "200" ]]; then
                    msg_ok "Локально URL доступен: HTTP ${local_code}"
                else
                    msg_err "Локально URL недоступен: HTTP ${local_code}"
                fi
                
                external_code=$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 8 "${sub_url}" 2>/dev/null || echo "000")
                if [[ "$external_code" == "200" ]]; then
                    msg_ok "Снаружи URL доступен: HTTP ${external_code}"
                else
                    msg_err "Снаружи URL недоступен: HTTP ${external_code}"
                fi
                
                echo ""
                msg_info "Диагностика:"
                local issue_detected="false"
                if [[ "$tcp_ok" != "true" ]]; then
                    issue_detected="true"
                    echo -e "  ${GRAY}• Nginx не слушает порт ${web_port}${NC}"
                    echo -e "  ${GRAY}• Проверьте: systemctl status nginx${NC}"
                    echo -e "  ${GRAY}• Проверьте: nginx -t${NC}"
                elif [[ "$local_code" != "200" ]]; then
                    issue_detected="true"
                    echo -e "  ${GRAY}• Проблема в конфигурации location / alias${NC}"
                    echo -e "  ${GRAY}• Проверьте путь: ${path}${NC}"
                    echo -e "  ${GRAY}• Проверьте файл: ${SUB_FILE}${NC}"
                elif [[ "$external_code" != "200" ]]; then
                    issue_detected="true"
                    echo -e "  ${GRAY}• Локально работает, но снаружи нет${NC}"
                    echo -e "  ${GRAY}• Причина: firewall / порт закрыт / NAT${NC}"
                    echo -e "  ${GRAY}• Проверьте открытие порта ${web_port} у провайдера/VPS${NC}"
                else
                    echo -e "  ${GRAY}• URL подписки работает корректно${NC}"
                fi
                
                echo ""
                msg_info "Текущий URL: ${sub_url}"
                
                if [[ "$issue_detected" == "true" ]]; then
                    echo ""
                    echo -ne "  ${WHITE}Попробовать авто-восстановление nginx и URL? (y/n): ${NC}"
                    read -r auto_fix
                    
                    if [[ "$auto_fix" =~ ^[Yy]$ ]]; then
                        echo ""
                        spin_start "Авто-восстановление конфигурации..."
                        update_nginx_config
                        
                        if [[ "$use_ssl" == "true" && -n "$domain" ]]; then
                            local cert_fullchain cert_privkey
                            cert_fullchain="/etc/letsencrypt/live/${domain}/fullchain.pem"
                            cert_privkey="/etc/letsencrypt/live/${domain}/privkey.pem"
                            if [[ ! -f "$cert_fullchain" || ! -f "$cert_privkey" ]]; then
                                spin_stop
                                msg_warn "SSL-сертификат не найден, пробуем получить заново..."
                                spin_start "Получение SSL-сертификата..."
                                obtain_ssl_certificate "$domain"
                            fi
                        fi
                        spin_stop
                        
                        echo ""
                        msg_info "Повторная проверка после авто-восстановления..."
                        echo ""
                        
                        local_code=$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://127.0.0.1:${web_port}${path}" 2>/dev/null || echo "000")
                        external_code=$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 8 "${sub_url}" 2>/dev/null || echo "000")
                        
                        if [[ "$local_code" == "200" ]]; then
                            msg_ok "Локально URL доступен после восстановления: HTTP ${local_code}"
                        else
                            msg_err "Локально URL всё ещё недоступен: HTTP ${local_code}"
                        fi
                        
                        if [[ "$external_code" == "200" ]]; then
                            msg_ok "Снаружи URL доступен после восстановления: HTTP ${external_code}"
                        else
                            msg_err "Снаружи URL всё ещё недоступен: HTTP ${external_code}"
                        fi
                    fi
                fi
                
                pause_key
                ;;
            8)
                echo ""
                if ! command -v qrencode &>/dev/null; then
                    msg_warn "qrencode не установлен. Устанавливаю..."
                    apt-get install -y -qq qrencode > /dev/null 2>&1
                    if ! command -v qrencode &>/dev/null; then
                        msg_err "Не удалось установить qrencode"
                        msg_info "Установите вручную: apt install qrencode"
                        pause_key
                        continue
                    fi
                    msg_ok "qrencode установлен"
                fi
                
                echo -e "  ${WHITE}QR-код для URL подписки:${NC}"
                echo -e "  ${CYAN}${sub_url}${NC}"
                echo ""
                qrencode -t ANSIUTF8 "$sub_url"
                echo ""
                msg_info "Отсканируйте QR-код камерой или VPN-клиентом"
                pause_key
                ;;
            9)
                echo ""
                echo -e "  ${WHITE}Текущее имя файла:${NC} ${CYAN}${SUB_FILENAME}${NC}"
                echo ""
                msg_hint "Введите только имя файла БЕЗ расширения .txt"
                msg_hint "Примеры: sub, mykeys, vpn-config"
                msg_hint "Пустой Enter — отменить и вернуться назад"
                echo ""
                echo -ne "  ${GREEN}➜${NC}  ${WHITE}Новое имя файла: ${NC}"
                read -r new_fname
                if [[ -z "$new_fname" ]]; then
                    msg_info "Изменение имени файла отменено"
                elif [[ "$new_fname" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                    local old_file="$SUB_FILE"
                    local normalized_name
                    normalized_name="${new_fname%.txt}"
                    config_set "sub_filename" "$normalized_name"
                    init_sub_vars
                    if [[ -f "$old_file" ]]; then
                        mv "$old_file" "$SUB_FILE" 2>/dev/null
                    fi
                    touch "$SUB_FILE"
                    chmod 644 "$SUB_FILE"
                    update_nginx_config
                    msg_ok "Имя файла изменено: ${normalized_name}.txt"
                else
                    msg_err "Некорректное имя файла"
                fi
                pause_key
                ;;
            10)
                echo ""
                msg_warn "Вы уверены, что хотите очистить файл подписки?"
                if [[ -n "$(cron_get 2>/dev/null)" ]]; then
                    msg_warn "Автообновление ВКЛЮЧЕНО — файл будет перезаписан при следующем обновлении!"
                fi
                echo ""
                echo -ne "  ${WHITE}Очистить файл? (y/n): ${NC}"
                read -r clear_confirm
                if [[ "$clear_confirm" =~ ^[Yy]$ ]]; then
                    > "$SUB_FILE"
                    > "$RAW_FILE" 2>/dev/null
                    chmod 644 "$SUB_FILE"
                    msg_ok "Файл подписки очищен"
                else
                    msg_info "Отменено"
                fi
                pause_key
                ;;
        esac
    done
}

menu_domain_settings() {
    while true; do
        init_sub_vars
        
        print_header
        print_section_header "НАСТРОЙКИ ДОСТУПА К ПОДПИСКЕ"
        
        local use_domain=$(config_get "use_domain" "false")
        local domain=$(config_get "domain" "")
        local use_ssl=$(config_get "use_ssl" "false")
        local web_port=$(config_get "web_port" "8443")
        local encode_url=$(config_get "encode_url" "false")
        local encoded_path=$(config_get "encoded_path" "")
        
        local server_ip
        server_ip=$(curl -4 -s --connect-timeout 3 ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "?.?.?.?")
        
        # Формируем текущий URL
        local protocol="http"
        [[ "$use_ssl" == "true" ]] && protocol="https"
        
        local host="$server_ip"
        [[ "$use_domain" == "true" && -n "$domain" ]] && host="$domain"
        
        local path="/${SUB_FILENAME}"
        [[ "$encode_url" == "true" && -n "$encoded_path" ]] && path="/${encoded_path}"
        
        local port_str=":${web_port}"
        [[ "$web_port" == "443" || "$web_port" == "80" ]] && port_str=""
        
        local sub_url="${protocol}://${host}${port_str}${path}"
        
        # Статусы
        local domain_status="${RED}○ Выкл (используется IP)${NC}"
        [[ "$use_domain" == "true" && -n "$domain" ]] && domain_status="${GREEN}● Вкл${NC} ${GRAY}(${domain})${NC}"
        
        local ssl_status="${RED}○ Выкл${NC}"
        [[ "$use_ssl" == "true" ]] && ssl_status="${GREEN}● Вкл (Let's Encrypt)${NC}"
        
        local encode_status="${RED}○ Выкл (стандартный путь)${NC}"
        [[ "$encode_url" == "true" ]] && encode_status="${GREEN}● Вкл${NC} ${GRAY}(/${encoded_path})${NC}"
        
        echo -e "  ${WHITE}Текущие настройки:${NC}"
        echo ""
        echo -e "  ${GRAY}├─${NC} ${WHITE}IP сервера:${NC}     ${CYAN}${server_ip}${NC}"
        echo -e "  ${GRAY}├─${NC} ${WHITE}Домен:${NC}          ${domain_status}"
        echo -e "  ${GRAY}├─${NC} ${WHITE}SSL:${NC}            ${ssl_status}"
        echo -e "  ${GRAY}├─${NC} ${WHITE}Порт:${NC}           ${CYAN}${web_port}${NC}"
        echo -e "  ${GRAY}├─${NC} ${WHITE}Кодирование:${NC}    ${encode_status}"
        echo -e "  ${GRAY}└─${NC} ${WHITE}Имя файла:${NC}      ${CYAN}${SUB_FILENAME}${NC}"
        echo ""
        echo -e "  ${WHITE}🔗 Текущий URL:${NC}"
        echo -e "     ${CYAN}${sub_url}${NC}"
        echo ""
        print_thin_line
        echo ""
        
        # Опции меню
        if [[ "$use_domain" == "true" ]]; then
            echo -e "  ${WHITE}  1) Переключить на IP-адрес${NC}"
        else
            echo -e "  ${WHITE}  1) Настроить домен${NC}"
        fi
        
        if [[ "$use_domain" == "true" && -n "$domain" ]]; then
            if [[ "$use_ssl" == "true" ]]; then
                echo -e "  ${WHITE}  2) Отключить SSL${NC}"
            else
                echo -e "  ${WHITE}  2) Включить SSL (Let's Encrypt)${NC}"
            fi
        else
            echo -e "  ${DARK_GRAY}  2) SSL (требуется домен)${NC}"
        fi
        
        echo -e "  ${WHITE}  3) Изменить порт${NC}"
        
        if [[ "$encode_url" == "true" ]]; then
            echo -e "  ${WHITE}  4) Отключить кодирование пути${NC}"
        else
            echo -e "  ${WHITE}  4) Включить кодирование пути (base64)${NC}"
        fi
        
        echo -e "  ${WHITE}  5) Изменить имя файла подписки${NC}"
        echo ""
        echo -e "  ${WHITE}  0) ← Назад${NC}"
        echo ""
        echo -ne "  ${WHITE}Выберите действие: ${NC}"
        read -r choice
        
        case "$choice" in
            0) return ;;
            1)
                if [[ "$use_domain" == "true" ]]; then
                    # Переключаем на IP
                    echo ""
                    echo -ne "  ${WHITE}Переключить на IP-адрес? (y/n): ${NC}"
                    read -r confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        config_set "use_domain" "false"
                        config_set "domain" ""
                        config_set "use_ssl" "false"
                        
                        # Запрашиваем порт
                        echo -ne "  ${WHITE}Порт для HTTP [8443]: ${NC}"
                        read -r new_port
                        [[ -z "$new_port" ]] && new_port="8443"
                        config_set "web_port" "$new_port"
                        
                        # Обновляем Nginx
                        update_nginx_config
                        msg_ok "Переключено на IP-адрес"
                    fi
                else
                    # Настраиваем домен
                    echo ""
                    echo -e "  ${WHITE}Введите домен:${NC}"
                    msg_hint "Например: sub.example.com, vpn.mydomain.ru"
                    msg_hint "Домен должен быть направлен на IP: ${server_ip}"
                    echo ""
                    echo -ne "  ${GREEN}➜${NC}  ${WHITE}Домен: ${NC}"
                    read -r new_domain
                    
                    if [[ -n "$new_domain" ]]; then
                        config_set "use_domain" "true"
                        config_set "domain" "$new_domain"
                        
                        # Спрашиваем про SSL
                        echo ""
                        echo -ne "  ${WHITE}Настроить SSL для ${new_domain}? (y/n) [y]: ${NC}"
                        read -r ssl_answer
                        
                        if [[ ! "$ssl_answer" =~ ^[Nn]$ ]]; then
                            config_set "use_ssl" "true"
                            config_set "web_port" "443"
                            
                            # Обновляем Nginx и получаем SSL
                            update_nginx_config
                            obtain_ssl_certificate "$new_domain"
                        else
                            config_set "use_ssl" "false"
                            echo -ne "  ${WHITE}Порт для HTTP [80]: ${NC}"
                            read -r new_port
                            [[ -z "$new_port" ]] && new_port="80"
                            config_set "web_port" "$new_port"
                            
                            update_nginx_config
                        fi
                        
                        msg_ok "Домен настроен: $new_domain"
                    fi
                fi
                pause_key
                ;;
            2)
                if [[ "$use_domain" != "true" || -z "$domain" ]]; then
                    msg_warn "SSL доступен только при использовании домена"
                    pause_key
                    continue
                fi
                
                if [[ "$use_ssl" == "true" ]]; then
                    # Отключаем SSL
                    echo ""
                    echo -ne "  ${WHITE}Отключить SSL? (y/n): ${NC}"
                    read -r confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        config_set "use_ssl" "false"
                        echo -ne "  ${WHITE}Порт для HTTP [80]: ${NC}"
                        read -r new_port
                        [[ -z "$new_port" ]] && new_port="80"
                        config_set "web_port" "$new_port"
                        
                        update_nginx_config
                        msg_ok "SSL отключён"
                    fi
                else
                    # Включаем SSL
                    echo ""
                    msg_info "Получение SSL-сертификата для ${domain}..."
                    config_set "use_ssl" "true"
                    config_set "web_port" "443"
                    
                    update_nginx_config
                    obtain_ssl_certificate "$domain"
                fi
                pause_key
                ;;
            3)
                echo ""
                echo -ne "  ${WHITE}Новый порт [${web_port}]: ${NC}"
                read -r new_port
                if [[ -n "$new_port" && "$new_port" =~ ^[0-9]+$ ]]; then
                    config_set "web_port" "$new_port"
                    update_nginx_config
                    msg_ok "Порт изменён на $new_port"
                fi
                pause_key
                ;;
            4)
                if [[ "$encode_url" == "true" ]]; then
                    # Отключаем кодирование
                    echo ""
                    echo -ne "  ${WHITE}Отключить кодирование пути? (y/n): ${NC}"
                    read -r confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        config_set "encode_url" "false"
                        config_set "encoded_path" ""
                        encode_url="false"
                        encoded_path=""
                        
                        update_nginx_config
                        msg_ok "Кодирование пути отключено. Новый путь: /${SUB_FILENAME}"
                    fi
                else
                    # Включаем кодирование
                    echo ""
                    local random_string
                    random_string=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 16)
                    local new_encoded_path
                    new_encoded_path=$(echo -n "$random_string" | base64 | tr -d '=' | tr '+/' '-_')
                    
                    echo -e "  ${WHITE}Сгенерирован путь:${NC} ${CYAN}/${new_encoded_path}${NC}"
                    echo ""
                    echo -ne "  ${WHITE}Применить? (y/n): ${NC}"
                    read -r confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        config_set "encode_url" "true"
                        config_set "encoded_path" "$new_encoded_path"
                        
                        update_nginx_config
                        msg_ok "Кодирование включено"
                    fi
                fi
                pause_key
                ;;
            5)
                # Изменение имени файла подписки
                echo ""
                echo -e "  ${WHITE}Текущее имя файла:${NC} ${CYAN}${SUB_FILENAME}${NC}"
                echo ""
                msg_hint "Имя файла должно содержать только буквы, цифры, точки и дефисы"
                msg_hint "Примеры: sub.txt, mykeys.txt, vpn-config.txt"
                echo ""
                echo -ne "  ${GREEN}➜${NC}  ${WHITE}Новое имя файла: ${NC}"
                read -r new_filename
                
                if [[ -n "$new_filename" ]]; then
                    # Проверяем корректность имени
                    if [[ "$new_filename" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                        local old_file="$SUB_FILE"
                        
                        # Сохраняем новое имя
                        config_set "sub_filename" "$new_filename"
                        
                        # Обновляем переменные
                        init_sub_vars
                        
                        # Переименовываем файл если он существует
                        if [[ -f "$old_file" ]]; then
                            mv "$old_file" "$SUB_FILE" 2>/dev/null
                            msg_ok "Файл переименован: ${new_filename}"
                        else
                            msg_ok "Имя файла изменено: ${new_filename}"
                        fi
                        
                        # Обновляем конфигурацию Nginx
                        update_nginx_config
                    else
                        msg_err "Некорректное имя файла"
                        msg_hint "Используйте только буквы, цифры, точки и дефисы"
                    fi
                fi
                pause_key
                ;;
        esac
    done
}

update_nginx_config() {
    init_sub_vars
    
    local use_domain=$(config_get "use_domain" "false")
    local domain=$(config_get "domain" "")
    local use_ssl=$(config_get "use_ssl" "false")
    local web_port=$(config_get "web_port" "8443")
    local encode_url=$(config_get "encode_url" "false")
    local encoded_path=$(config_get "encoded_path" "")
    local server_ip
    server_ip=$(curl -4 -s --connect-timeout 5 ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
    
    local server_name="${server_ip}"
    [[ "$use_domain" == "true" && -n "$domain" ]] && server_name="$domain"
    
    local sub_path="/${SUB_FILENAME}"
    [[ "$encode_url" == "true" && -n "$encoded_path" ]] && sub_path="/${encoded_path}"
    
    local cert_fullchain="/etc/letsencrypt/live/${domain}/fullchain.pem"
    local cert_privkey="/etc/letsencrypt/live/${domain}/privkey.pem"
    
    if [[ "$use_ssl" == "true" && -n "$domain" && -f "$cert_fullchain" && -f "$cert_privkey" ]]; then
        cat > "$NGINX_CONF" <<EONGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${server_name};

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${server_name};

    ssl_certificate ${cert_fullchain};
    ssl_certificate_key ${cert_privkey};

    access_log /var/log/nginx/3xcsm_access.log;
    error_log /var/log/nginx/3xcsm_error.log;

    location = ${sub_path} {
        default_type "text/plain; charset=utf-8";
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        alias ${SUB_FILE};
    }

    location / {
        return 404;
    }
}
EONGINX
    else
        cat > "$NGINX_CONF" <<EONGINX
server {
    listen ${web_port};
    listen [::]:${web_port};
    server_name ${server_name};

    access_log /var/log/nginx/3xcsm_access.log;
    error_log /var/log/nginx/3xcsm_error.log;

    location = ${sub_path} {
        default_type "text/plain; charset=utf-8";
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
        alias ${SUB_FILE};
    }

    location / {
        return 404;
    }
}
EONGINX
    fi
    
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null
    rm -f /etc/nginx/sites-enabled/subup 2>/dev/null
    ln -sf "$NGINX_CONF" "$NGINX_LINK" 2>/dev/null
    mkdir -p /var/log/nginx /var/www/html 2>/dev/null
    touch /var/log/nginx/access.log /var/log/nginx/error.log /var/log/nginx/3xcsm_access.log /var/log/nginx/3xcsm_error.log 2>/dev/null
    
    local nginx_error
    nginx_error=$(nginx -t 2>&1)
    if [[ $? -eq 0 ]]; then
        systemctl restart nginx > /dev/null 2>&1
        if command -v ufw &>/dev/null; then
            ufw allow "${web_port}/tcp" > /dev/null 2>&1
            [[ "$use_ssl" == "true" ]] && ufw allow "80/tcp" > /dev/null 2>&1 && ufw allow "443/tcp" > /dev/null 2>&1
        fi
        if command -v firewall-cmd &>/dev/null; then
            firewall-cmd --permanent --add-port="${web_port}/tcp" > /dev/null 2>&1
            [[ "$use_ssl" == "true" ]] && firewall-cmd --permanent --add-port="80/tcp" > /dev/null 2>&1 && firewall-cmd --permanent --add-port="443/tcp" > /dev/null 2>&1
            firewall-cmd --reload > /dev/null 2>&1
        fi
    else
        msg_err "Ошибка в конфигурации Nginx:"
        echo -e "  ${GRAY}${nginx_error}${NC}"
        msg_info "Исправьте вручную: nano ${NGINX_CONF}"
    fi
}

obtain_ssl_certificate() {
    local domain="$1"
    local encode_url=$(config_get "encode_url" "false")
    local encoded_path=$(config_get "encoded_path" "")
    
    local sub_path="/${SUB_FILENAME}"
    [[ "$encode_url" == "true" && -n "$encoded_path" ]] && sub_path="/${encoded_path}"
    
    echo ""
    spin_start "Получение SSL-сертификата для ${domain}..."
    
    # Временная конфигурация для certbot
    cat > "$NGINX_CONF" <<EOTEMP
server {
    listen 80;
    server_name ${domain};
    root ${WEB_DIR};
    location / { try_files \$uri \$uri/ =404; }
}
EOTEMP
    
    nginx -t > /dev/null 2>&1 && systemctl reload nginx > /dev/null 2>&1
    
    # Запускаем certbot
    certbot --nginx -d "$domain" --non-interactive --agree-tos --email "admin@${domain}" --redirect > /dev/null 2>&1
    local cert_rc=$?
    
    spin_stop
    
    if [[ $cert_rc -eq 0 ]]; then
        msg_ok "SSL-сертификат успешно установлен!"
        config_set "use_ssl" "true"
        config_set "web_port" "443"
        update_nginx_config
    else
        msg_err "Не удалось получить SSL-сертификат"
        msg_info "Возможные причины:"
        echo -e "    ${GRAY}• Домен не направлен на этот сервер${NC}"
        echo -e "    ${GRAY}• Порт 80 занят или заблокирован${NC}"
        echo -e "    ${GRAY}• Лимит запросов к Let's Encrypt${NC}"
        
        config_set "use_ssl" "false"
        config_set "web_port" "80"
        update_nginx_config
    fi
}


menu_reset() {
    print_header
    print_section_header "ПОЛНЫЙ СБРОС НАСТРОЕК"
    
    echo -e "  ${RED}Будут сброшены:${NC}"
    echo ""
    echo -e "  ${GRAY}├─${NC} Список серверов 3x-UI (servers.json)"
    echo -e "  ${GRAY}├─${NC} Все настройки подписки (config.json)"
    echo -e "  ${GRAY}├─${NC} Файл подписки (sub.txt)"
    echo -e "  ${GRAY}├─${NC} RAW-файл ключей"
    echo -e "  ${GRAY}├─${NC} Cron-задачи автообновления"
    echo -e "  ${GRAY}└─${NC} Конфигурация Nginx"
    echo ""
    msg_warn "Все серверы, инбаунды и клиенты будут удалены!"
    msg_warn "Скрипт останется установленным, но все данные обнулятся."
    echo ""
    echo -ne "  ${RED}Введите YES для подтверждения: ${NC}"
    read -r confirm
    
    if [[ "$confirm" != "YES" ]]; then
        msg_info "Сброс отменён"
        pause_key
        return
    fi
    
    cron_remove
    
    echo '[]' > "$SERVERS_FILE"
    
    cat > "$CONFIG_FILE" <<EOJSON
{
    "update_interval": "59",
    "update_unit": "minutes",
    "sub_title": "3X-UI-CSM-SUB",
    "client_update_interval": "12",
    "support_url": "https://t.me/LarsInvilink",
    "sub_upload": "0",
    "sub_download": "0",
    "sub_total": "0",
    "sub_expire": "0",
    "header_profile_title": "true",
    "header_profile_update_interval": "true",
    "header_support_url": "false",
    "header_profile_web_page_url": "false",
    "header_subscription_userinfo": "false",
    "web_port": "8443",
    "use_domain": "false",
    "domain": "",
    "use_ssl": "false",
    "encode_url": "false",
    "encoded_path": "",
    "encode_content": "true",
    "installed": "true"
}
EOJSON
    
    > "$RAW_FILE" 2>/dev/null
    > "$SUB_FILE" 2>/dev/null
    rm -f "${COOKIE_DIR}"/* 2>/dev/null
    
    update_nginx_config
    
    msg_ok "Все настройки сброшены!"
    msg_info "Скрипт готов к повторной настройке"
    
    pause_key
}

menu_uninstall() {
    init_sub_vars
    print_header
    echo ""
    echo -e "  ${RED}══════════════════════════════════════════════════${NC}"
    echo -e "  ${RED}  [!] ПОЛНОЕ УДАЛЕНИЕ СКРИПТА${NC}"
    echo -e "  ${RED}══════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "  ${WHITE}Будут удалены следующие компоненты:${NC}"
    echo ""
    print_thin_line
    msg_warn "Конфигурация скрипта: ${BASE_DIR}"
    msg_warn "Данные серверов: ${SERVERS_FILE}"
    msg_warn "Cookies и временные файлы: ${COOKIE_DIR}"
    msg_warn "Конфигурация Nginx: ${NGINX_CONF}"
    msg_warn "Cron-задачи автообновления"
    msg_warn "Команда 3xsub: ${SUBUP_CMD}"
    print_thin_line
    echo ""

    echo -e "  ${YELLOW}Файл подписки:${NC} ${CYAN}${SUB_FILE}${NC}"
    if [[ -f "$SUB_FILE" ]]; then
        local key_count=0
        local _enc
        _enc=$(config_get "encode_content" "true")
        if [[ -s "$SUB_FILE" ]]; then
            if [[ "$_enc" == "true" ]]; then
                key_count=$(base64 -d "$SUB_FILE" 2>/dev/null | grep -cE "^(vless|vmess|trojan|ss|hysteria2)://" || echo "0")
            else
                key_count=$(grep -cE "^(vless|vmess|trojan|ss|hysteria2)://" "$SUB_FILE" || echo "0")
            fi
        fi
        echo -e "     ${GRAY}(содержит ${key_count} ключей)${NC}"
    fi
    echo ""
    
    print_thin_line
    echo ""
    echo -ne "  ${RED}Введите 'YES' для подтверждения удаления: ${NC}"
    read -r confirm

    if [[ "$confirm" != "YES" ]]; then
        msg_info "Удаление отменено"
        pause_key
        return
    fi

    # Спрашиваем про файл подписки отдельно
    echo ""
    echo -e "  ${YELLOW}Удалить также файл подписки?${NC}"
    echo -e "  ${GRAY}Файл: ${SUB_FILE}${NC}"
    echo ""
    echo -ne "  ${WHITE}Удалить файл подписки? (y/n) [n]: ${NC}"
    read -r delete_sub
    
    local delete_subscription="false"
    [[ "$delete_sub" =~ ^[Yy]$ ]] && delete_subscription="true"

    echo ""
    echo ""
    
    local total_steps=6
    [[ "$delete_subscription" == "true" ]] && total_steps=6 || total_steps=5
    local current_step=0
    
    # Шаг 1: Удаление cron
    current_step=$((current_step + 1))
    progress_bar $current_step $total_steps "Удаление cron-задач..."
    cron_remove
    sleep 0.3
    
    # Шаг 2: Удаление конфигурации Nginx
    current_step=$((current_step + 1))
    progress_bar $current_step $total_steps "Удаление конфигурации Nginx..."
    rm -f "$NGINX_LINK" "$NGINX_CONF" 2>/dev/null
    nginx -t > /dev/null 2>&1 && systemctl reload nginx > /dev/null 2>&1
    sleep 0.3
    
    # Шаг 3: Удаление файла подписки (опционально)
    if [[ "$delete_subscription" == "true" ]]; then
        current_step=$((current_step + 1))
        progress_bar $current_step $total_steps "Удаление файла подписки..."
        rm -rf "$WEB_DIR" 2>/dev/null
        sleep 0.3
    fi
    
    # Шаг 4: Удаление конфигурации
    current_step=$((current_step + 1))
    progress_bar $current_step $total_steps "Удаление конфигурации и данных..."
    rm -rf "$BASE_DIR" 2>/dev/null
    sleep 0.3
    
    # Шаг 5: Удаление команды 3xsub
    current_step=$((current_step + 1))
    progress_bar $current_step $total_steps "Удаление команды 3xsub..."
    rm -f "$SUBUP_CMD" 2>/dev/null
    sleep 0.3
    
    # Финал
    current_step=$((current_step + 1))
    progress_done "Удаление завершено"

    echo ""
    echo ""
    msg_ok "3X-UI CSM полностью удалён!"
    echo ""
    
    if [[ "$delete_subscription" == "true" ]]; then
        msg_ok "Файл подписки удалён"
    else
        msg_info "Файл подписки сохранён: ${SUB_FILE}"
        echo -e "     ${GRAY}Вы можете удалить его вручную: rm -rf ${WEB_DIR}${NC}"
    fi
    
    echo ""
    echo -ne "  ${WHITE}Удалить установленные зависимости (qrencode, certbot)? (y/n) [n]: ${NC}"
    read -r del_deps
    if [[ "$del_deps" =~ ^[Yy]$ ]]; then
        apt-get remove -y -qq qrencode certbot python3-certbot-nginx > /dev/null 2>&1
        msg_ok "Зависимости удалены"
    fi
    echo ""
    msg_info "Nginx, jq, cron остались как системные пакеты"
    msg_info "Для их удаления: apt remove --purge nginx jq cron"
    echo ""

    pause_key
    exit 0
}

main_menu() {
    while true; do
        # Обновляем переменные файла подписки
        init_sub_vars
        
        print_header

        # Статус-бар
        local total_servers
        total_servers=$(servers_count)

        local key_count=0
        local _enc
        _enc=$(config_get "encode_content" "true")
        if [[ -f "$SUB_FILE" && -s "$SUB_FILE" ]]; then
            if [[ "$_enc" == "true" ]]; then
                key_count=$(base64 -d "$SUB_FILE" 2>/dev/null | grep -cE "^(vless|vmess|trojan|ss|hysteria2)://" 2>/dev/null || echo "0")
            else
                key_count=$(grep -cE "^(vless|vmess|trojan|ss|hysteria2)://" "$SUB_FILE" 2>/dev/null || echo "0")
            fi
        fi

        local cron_status
        if [[ -n "$(cron_get 2>/dev/null)" ]]; then
            local ci cu ut
            ci=$(config_get "update_interval" "?")
            cu=$(config_get "update_unit" "?")
            case "$cu" in
                minutes) ut="мин" ;;
                hours) ut="ч" ;;
                days) ut="дн" ;;
                *) ut="?" ;;
            esac
            cron_status="${GREEN}●${NC} ${WHITE}${ci}${ut}${NC}"
        else
            cron_status="${RED}ВЫКЛ${NC}"
        fi

        # Формируем URL подписки
        local use_domain=$(config_get "use_domain" "false")
        local domain=$(config_get "domain" "")
        local use_ssl=$(config_get "use_ssl" "false")
        local web_port=$(config_get "web_port" "8443")
        local encode_url=$(config_get "encode_url" "false")
        local encoded_path=$(config_get "encoded_path" "")
        
        local server_ip
        server_ip=$(curl -4 -s --connect-timeout 3 ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "?.?.?.?")
        
        local protocol="http"
        [[ "$use_ssl" == "true" ]] && protocol="https"
        
        local host="$server_ip"
        [[ "$use_domain" == "true" && -n "$domain" ]] && host="$domain"
        
        local path="/${SUB_FILENAME}"
        [[ "$encode_url" == "true" && -n "$encoded_path" ]] && path="/${encoded_path}"
        
        local port_str=":${web_port}"
        [[ "$web_port" == "443" || "$web_port" == "80" ]] && port_str=""
        
        local sub_url="${protocol}://${host}${port_str}${path}"

        local last_mod="--"
        if [[ -f "$SUB_FILE" && -s "$SUB_FILE" ]]; then
            last_mod=$(stat -c %y "$SUB_FILE" 2>/dev/null | cut -d. -f1 || echo "--")
        fi
        
        printf "  ${DARK_GRAY}Серверов:${NC} ${WHITE}%s${NC} ${DARK_GRAY}|${NC} ${DARK_GRAY}Ключей:${NC} ${WHITE}%s${NC} ${DARK_GRAY}|${NC} ${DARK_GRAY}Автообновление:${NC} %b\n" "$total_servers" "$key_count" "$cron_status"
        printf "  ${DARK_GRAY}Обновлено:${NC} ${WHITE}%s${NC} ${DARK_GRAY}(часовой пояс сервера)${NC}\n" "$last_mod"
        echo ""
        echo -e "  ${WHITE}  1)${NC}  ${CYAN}➕${NC}  Добавить сервер с 3x-UI"
        echo -e "  ${WHITE}  2)${NC}  ${CYAN}📋${NC}  Список серверов / Редактирование / Выбор ключей"
        echo -e "  ${WHITE}  3)${NC}  ${CYAN}⏰${NC}  Настройка автообновления подписки"
        echo -e "  ${WHITE}  4)${NC}  ${CYAN}📝${NC}  Редактирование заголовков / Настройка отображения"
        echo -e "  ${WHITE}  5)${NC}  ${CYAN}📄${NC}  Файл подписки / Редактирование"
        echo -e "  ${WHITE}  6)${NC}  ${GREEN}🔄${NC}  Обновить подписку сейчас"
        print_thin_line
        echo -e "  ${WHITE}  7)${NC}  ${WHITE}📊${NC}  Обзор состояния текущей подписки"
        echo -e "  ${WHITE}  8)${NC}  ${CYAN}ℹ${NC}   Информация и обновление"
        print_thin_line
        echo -e "  ${RED}  9)${NC}  ${RED}Полный сброс настроек (с осторожностью)${NC}"
        echo -e "  ${RED}  10)${NC} ${RED}Полное удаление скрипта${NC}"
        echo -e "  ${WHITE}  11)${NC} ${GRAY}↻${NC}   Обновить страницу"
        echo -e "  ${WHITE}  0)${NC}  ${DARK_GRAY}🚪${NC}  Выход"
        print_thin_line
        echo -e "  ${DARK_GRAY}Ваша ссылка на подписку: ${CYAN}${sub_url}${NC}"
        print_thin_line
        echo -ne "  ${WHITE}Выберите пункт: ${NC}"
        read -r choice

        case "$choice" in
            1) menu_add_server ;;
            2) menu_servers_list ;;
            3) menu_update_interval ;;
            4) menu_sub_title ;;
            5) menu_sub_info ;;
            6) menu_manual_update ;;
            7) menu_sub_overview ;;
            8) menu_about ;;
            9) menu_reset ;;
            10) menu_uninstall ;;
            11) continue ;;
            0)
                clear_screen
                echo ""
                echo -e "  ${GREEN}До встречи! Используйте: ${WHITE}3xsub${NC}"
                echo ""
                exit 0
                ;;
            *)
                msg_err "Неверный выбор"
                sleep 1
                ;;
        esac
    done
}

main() {
    check_root
    
    # Инициализируем переменные файла подписки
    [[ -f "$CONFIG_FILE" ]] && init_sub_vars

    case "${1:-}" in
        --menu)
            init_sub_vars
            main_menu
            ;;
        --update)
            init_sub_vars
            collect_keys "true"
            exit 0
            ;;
        --help|-h)
            echo ""
            echo -e "  ${CYAN}3X-UI CSM${NC} v${VERSION} — Менеджер подписок VLESS"
            echo -e "  ${GRAY}Автор: ${AUTHOR} │ ${TELEGRAM}${NC}"
            echo ""
            echo -e "  ${WHITE}Использование:${NC}"
            echo -e "    ${CYAN}bash $0${NC}           — Установка + меню"
            echo -e "    ${CYAN}bash $0 --menu${NC}    — Только меню"
            echo -e "    ${CYAN}bash $0 --update${NC}  — Тихое обновление"
            echo -e "    ${CYAN}3xsub${NC}             — Быстрая команда"
            echo ""
            echo -e "  ${WHITE}Требования 3x-UI:${NC} ${MIN_3XUI_VERSION}+ (рекомендуется ${RECOMMENDED_3XUI_VERSION}+)"
            echo ""
            exit 0
            ;;
        *)
            if [[ -f "$CONFIG_FILE" ]] && check_dependencies; then
                init_sub_vars
                main_menu
            else
                install_dependencies
                init_sub_vars
                main_menu
            fi
            ;;
    esac
}

main "$@"
