#!/usr/bin/env bash

# === Плагин управления файрволом Xray Gateway Installer ===
# Версия: 2.0.0
# Автор: Xray Gateway Installer Team

# Глобальные переменные плагина
declare -g FIREWALL_SCRIPT_PATH=""
declare -g FIREWALL_UNIT_NAME="xray-iptables.service"
declare -g FIREWALL_RESTART_UNIT_NAME="xray-iptables-restart.service"
declare -g MARK_ID
declare -g ROUTE_TABLE_ID
declare -g TPROXY_PORT
declare -g REDIRECT_PORT

# === Инициализация плагина ===
plugin_firewall_init() {
    log INFO "Инициализация плагина управления файрволом"
    
    # Загрузка конфигурации
    FIREWALL_SCRIPT_PATH="${XRAY_INSTALL_PATH}/iptables/xray-iptables.sh"
    MARK_ID="$(config_get_constant "firewall.mark_id")"
    ROUTE_TABLE_ID="$(config_get_constant "firewall.route_table_id")"
    TPROXY_PORT="$(config_get_constant "firewall.tproxy_port")"
    REDIRECT_PORT="$(config_get_constant "firewall.redirect_port")"
    
    log OK "Плагин управления файрволом инициализирован"
}

# === Выполнение плагина ===
plugin_firewall_execute() {
    local action="$1"
    shift
    local args=("$@")
    
    case "$action" in
        "install")
            firewall_install "${args[@]}"
            ;;
        "uninstall")
            firewall_uninstall "${args[@]}"
            ;;
        "status")
            firewall_status "${args[@]}"
            ;;
        "start")
            firewall_start "${args[@]}"
            ;;
        "stop")
            firewall_stop "${args[@]}"
            ;;
        "restart")
            firewall_restart "${args[@]}"
            ;;
        *)
            log ERROR "Неизвестное действие для плагина firewall: $action"
            return 1
            ;;
    esac
}

# === Зависимости плагина ===
plugin_firewall_dependencies() {
    echo "network system"
}

# === Информация о плагине ===
plugin_firewall_info() {
    echo "Плагин управления файрволом"
    echo "  - Управление iptables правилами"
    echo "  - Настройка TProxy и Redirect"
    echo "  - Реализация kill-switch"
    echo "  - Управление исключениями"
    echo "  - Интеграция с systemd"
}

# === Установка плагина файрвола ===
firewall_install() {
    log SEP
    log TITLE "Установка плагина файрвола"
    
    # Переключение на iptables-legacy
    firewall_force_legacy
    
    # Создание скрипта управления iptables
    firewall_create_script
    
    # Создание systemd юнитов
    firewall_create_systemd_units
    
    # Применение правил
    firewall_apply_rules
    
    log OK "Плагин файрвола установлен"
}

# === Удаление плагина файрвола ===
firewall_uninstall() {
    log SEP
    log TITLE "Удаление плагина файрвола"
    
    # Остановка и отключение сервисов
    systemctl stop "$FIREWALL_UNIT_NAME" 2>/dev/null || true
    systemctl disable "$FIREWALL_UNIT_NAME" 2>/dev/null || true
    systemctl stop "$FIREWALL_RESTART_UNIT_NAME" 2>/dev/null || true
    systemctl disable "$FIREWALL_RESTART_UNIT_NAME" 2>/dev/null || true
    
    # Очистка правил
    firewall_clear_rules
    
    # Удаление файлов
    rm -f "/etc/systemd/system/$FIREWALL_UNIT_NAME"
    rm -f "/etc/systemd/system/$FIREWALL_RESTART_UNIT_NAME"
    rm -f "$FIREWALL_SCRIPT_PATH"
    
    # Перезагрузка systemd
    systemctl daemon-reload
    
    log OK "Плагин файрвола удалён"
}

# === Статус плагина файрвола ===
firewall_status() {
    log SEP
    log TITLE "Статус плагина файрвола"
    
    echo "Скрипт файрвола: ${FIREWALL_SCRIPT_PATH:-не создан}"
    echo "Systemd юнит: $FIREWALL_UNIT_NAME"
    echo "Статус сервиса: $(systemctl is-active --quiet "$FIREWALL_UNIT_NAME" && echo "активен" || echo "неактивен")"
    echo "Mark ID: $MARK_ID"
    echo "Route Table ID: $ROUTE_TABLE_ID"
    echo "TPROXY порт: $TPROXY_PORT"
    echo "REDIRECT порт: $REDIRECT_PORT"
    echo
    echo "Правила iptables:"
    iptables -t mangle -L XRAY -n -v 2>/dev/null || echo "  Цепочка XRAY не найдена"
    iptables -t nat -L XRAY -n -v 2>/dev/null || echo "  Цепочка XRAY (nat) не найдена"
}

# === Запуск файрвола ===
firewall_start() {
    log INFO "Запуск файрвола"
    firewall_apply_rules
    systemctl start "$FIREWALL_UNIT_NAME" 2>/dev/null || true
    log OK "Файрвол запущен"
}

# === Остановка файрвола ===
firewall_stop() {
    log INFO "Остановка файрвола"
    firewall_clear_rules
    systemctl stop "$FIREWALL_UNIT_NAME" 2>/dev/null || true
    log OK "Файрвол остановлен"
}

# === Перезапуск файрвола ===
firewall_restart() {
    log INFO "Перезапуск файрвола"
    firewall_stop
    sleep 1
    firewall_start
    log OK "Файрвол перезапущен"
}

# === Переключение на iptables-legacy ===
firewall_force_legacy() {
    log INFO "Переключение iptables на legacy-бэкенд"
    
    for tool in iptables ip6tables arptables ebtables; do
        local legacy_path="/usr/sbin/${tool}-legacy"
        if [[ -x "$legacy_path" ]]; then
            update-alternatives --install "/usr/sbin/$tool" "$tool" "$legacy_path" 100 2>/dev/null || true
            update-alternatives --set "$tool" "$legacy_path" 2>/dev/null || true
            log OK "$tool переключён на legacy-бэкенд"
        else
            log INFO "Пропуск $tool: legacy-бэкенд отсутствует"
        fi
    done
    
    # Проверка переключения
    local backend
    backend="$(update-alternatives --query iptables | awk '/Value: / {print $2}' 2>/dev/null || echo "unknown")"
    if [[ "$backend" == "/usr/sbin/iptables-legacy" ]]; then
        log OK "iptables работает в режиме legacy"
    else
        log WARN "iptables не использует legacy-бэкенд: $backend"
    fi
}

# === Создание скрипта управления iptables ===
firewall_create_script() {
    log INFO "Создание скрипта управления iptables"
    
    local script_dir
    script_dir="$(dirname "$FIREWALL_SCRIPT_PATH")"
    create_directory "$script_dir" "root" "root" "755"
    
    # Создание скрипта
    cat > "$FIREWALL_SCRIPT_PATH" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

# === Скрипт управления iptables для Xray Gateway ===
# Автоматически сгенерирован Xray Gateway Installer

MARK_ID="__MARK_ID__"
TPROXY_GID="__XRAY_GID__"
ROUTE_TABLE_ID="__ROUTE_TABLE_ID__"

XRAY_CHAIN="XRAY"
XRAY_SELF_CHAIN="XRAY_SELF"
XRAY_ENABLED_CHAIN="XRAY_ENABLED"
XRAY_DISABLED_CHAIN="XRAY_DISABLED"

XRAY_CONFIG_DIR="__XRAY_CONFIG_DIR__"
XRAY_TPROXY_PORT="__TPROXY_PORT__"
XRAY_REDIRECT_PORT="__REDIRECT_PORT__"
LAN_IF="__LAN_IF__"
WAN_IF="__WAN_IF__"
LOCAL_CIDRS="__LOCAL_CIDRS__"

SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
UNIT_NAME="__FIREWALL_UNIT_NAME__"
UNIT_PATH="__FIREWALL_UNIT_PATH__"
FIREWALL_RESTART_UNIT_NAME="__FIREWALL_RESTART_UNIT_NAME__"
FIREWALL_RESTART_UNIT_PATH="__FIREWALL_RESTART_UNIT_PATH__"

# Исключения
CUSTOM_BYPASS_CIDRS=()
CUSTOM_BYPASS_IPS=()
CUSTOM_BYPASS_PORTS=()

# === Обнаружение интерфейсов ===
detect_interfaces() {
    if [[ -z "$WAN_IF" ]]; then
        WAN_IF="$(ip route | awk '/default/ {print $5}' | head -n1)"
        if [[ -z "$WAN_IF" ]]; then
            log ERROR "Не удалось определить WAN интерфейс"
            exit 1
        fi
    fi
    
    if [[ -z "$LAN_IF" ]]; then
        LAN_IF="$(ip -o link show | awk -F': ' '{print $2}' | grep -Ev "^lo$|^$WAN_IF$" | head -n1)"
        if [[ -z "$LAN_IF" ]]; then
            LAN_IF="$WAN_IF"
            log WARN "Второй интерфейс не найден, используется WAN интерфейс"
        fi
    fi
    
    if [[ -z "$LOCAL_CIDRS" ]]; then
        LOCAL_CIDRS="$(ip -o -f inet addr show "$LAN_IF" | awk '{print $4}' | xargs)"
        if [[ -z "$LOCAL_CIDRS" ]]; then
            log ERROR "Не удалось получить локальные CIDR"
            exit 1
        fi
    fi
    
    log INFO "Интерфейсы: LAN=$LAN_IF, WAN=$WAN_IF"
    log INFO "Локальные CIDR: $LOCAL_CIDRS"
}

# === Загрузка исключений ===
load_exclusions() {
    local base_dir="$SCRIPT_DIR"
    
    # Создание файлов исключений, если не существуют
    [[ -f "$base_dir/exclude_cidrs.txt" ]] || cat > "$base_dir/exclude_cidrs.txt" <<EOF
# CIDR-сети, исключаемые из обработки
# Пример:
# 10.0.0.0/8
# 192.168.0.0/16
EOF
    
    [[ -f "$base_dir/exclude_ips.txt" ]] || cat > "$base_dir/exclude_ips.txt" <<EOF
# IP-адреса, исключаемые из обработки
# Пример:
# 8.8.8.8
# 1.1.1.1
EOF
    
    [[ -f "$base_dir/exclude_ports.txt" ]] || cat > "$base_dir/exclude_ports.txt" <<EOF
# TCP-порты, исключаемые из обработки
# Пример:
# 22     # SSH
# 443    # HTTPS
# 8080   # Локальный UI
EOF
    
    # Загрузка исключений из файлов
    [[ -f "$base_dir/exclude_cidrs.txt" ]] && \
        mapfile -t CUSTOM_BYPASS_CIDRS < <(grep -vE '^\s*#|^\s*$' "$base_dir/exclude_cidrs.txt" 2>/dev/null || true)
    
    [[ -f "$base_dir/exclude_ips.txt" ]] && \
        mapfile -t CUSTOM_BYPASS_IPS < <(grep -vE '^\s*#|^\s*$' "$base_dir/exclude_ips.txt" 2>/dev/null || true)
    
    [[ -f "$base_dir/exclude_ports.txt" ]] && \
        mapfile -t CUSTOM_BYPASS_PORTS < <(grep -vE '^\s*#|^\s*$' "$base_dir/exclude_ports.txt" 2>/dev/null || true)
    
    log INFO "Загружено исключений: CIDRs=${#CUSTOM_BYPASS_CIDRS[@]}, IPs=${#CUSTOM_BYPASS_IPS[@]}, Ports=${#CUSTOM_BYPASS_PORTS[@]}"
}

# === Очистка правил ===
clear_rules() {
    log INFO "Очистка правил iptables"
    
    # Удаление ip rule и маршрутов
    ip rule del fwmark $MARK_ID table $ROUTE_TABLE_ID 2>/dev/null || true
    ip route flush table $ROUTE_TABLE_ID 2>/dev/null || true
    
    # Удаление цепочек из PREROUTING и OUTPUT
    iptables -t mangle -D PREROUTING -i "$LAN_IF" -j XRAY_ENABLED 2>/dev/null || true
    iptables -t mangle -D PREROUTING -i "$LAN_IF" -j $XRAY_CHAIN 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "$LAN_IF" -j $XRAY_CHAIN 2>/dev/null || true
    iptables -t mangle -D OUTPUT -m owner ! --gid-owner $TPROXY_GID -j $XRAY_SELF_CHAIN 2>/dev/null || true
    
    # NAT и FORWARD правила для шлюза
    if [[ "$WAN_IF" != "$LAN_IF" ]]; then
        iptables -t nat -D POSTROUTING -o "$WAN_IF" -j MASQUERADE 2>/dev/null || true
        iptables -D FORWARD -i "$LAN_IF" -o "$WAN_IF" -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -i "$WAN_IF" -o "$LAN_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    fi
    
    # Очистка содержимого цепочек
    iptables -t mangle -F $XRAY_CHAIN 2>/dev/null || true
    iptables -t nat -F $XRAY_CHAIN 2>/dev/null || true
    iptables -t mangle -F $XRAY_SELF_CHAIN 2>/dev/null || true
    iptables -t mangle -F XRAY_ENABLED 2>/dev/null || true
    iptables -t mangle -F XRAY_DISABLED 2>/dev/null || true
    
    # Удаление цепочек
    iptables -t mangle -X $XRAY_CHAIN 2>/dev/null || true
    iptables -t nat -X $XRAY_CHAIN 2>/dev/null || true
    iptables -t mangle -X $XRAY_SELF_CHAIN 2>/dev/null || true
    iptables -t mangle -X XRAY_ENABLED 2>/dev/null || true
    iptables -t mangle -X XRAY_DISABLED 2>/dev/null || true
    
    log OK "Правила очищены"
}

# === Применение правил ===
apply_rules() {
    log INFO "Применение правил iptables"
    
    # Очистка предыдущих правил
    clear_rules
    
    # Установка ip rule и таблицы маршрутов
    ip rule add fwmark $MARK_ID table $ROUTE_TABLE_ID || {
        log ERROR "Не удалось добавить ip rule"
        exit 1
    }
    
    ip route add local 0.0.0.0/0 dev lo table $ROUTE_TABLE_ID || {
        log ERROR "Не удалось добавить маршрут в таблицу $ROUTE_TABLE_ID"
        exit 1
    }
    
    # Создание цепочек
    iptables -t mangle -N $XRAY_CHAIN 2>/dev/null || true
    iptables -t nat -N $XRAY_CHAIN 2>/dev/null || true
    iptables -t mangle -N $XRAY_SELF_CHAIN 2>/dev/null || true
    iptables -t mangle -N XRAY_ENABLED 2>/dev/null || true
    iptables -t mangle -N XRAY_DISABLED 2>/dev/null || true
    
    # Подключение к PREROUTING
    iptables -t mangle -A PREROUTING -i "$LAN_IF" -j XRAY_ENABLED
    iptables -t mangle -A XRAY_ENABLED -j $XRAY_CHAIN
    iptables -t nat -A PREROUTING -i "$LAN_IF" -j $XRAY_CHAIN
    
    # NAT и FORWARD правила для шлюза
    if [[ "$WAN_IF" != "$LAN_IF" ]]; then
        iptables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE
        iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -j ACCEPT
        iptables -A FORWARD -i "$WAN_IF" -o "$LAN_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT
        log OK "Настроен NAT $LAN_IF ↔ $WAN_IF"
    fi
    
    # Системные исключения
    for cidr in $LOCAL_CIDRS 127.0.0.0/8; do
        iptables -t mangle -A $XRAY_CHAIN -d "$cidr" -j RETURN
        iptables -t nat -A $XRAY_CHAIN -d "$cidr" -j RETURN
    done
    
    iptables -t mangle -A $XRAY_CHAIN -i lo -j RETURN
    iptables -t nat -A $XRAY_CHAIN -i lo -j RETURN
    
    # Кастомные исключения
    for cidr in "${CUSTOM_BYPASS_CIDRS[@]}"; do
        iptables -t mangle -A $XRAY_CHAIN -d "$cidr" -j RETURN
        iptables -t nat -A $XRAY_CHAIN -d "$cidr" -j RETURN
    done
    
    for ip in "${CUSTOM_BYPASS_IPS[@]}"; do
        iptables -t mangle -A $XRAY_CHAIN -d "$ip" -j RETURN
        iptables -t nat -A $XRAY_CHAIN -d "$ip" -j RETURN
    done
    
    for port in "${CUSTOM_BYPASS_PORTS[@]}"; do
        iptables -t mangle -A $XRAY_CHAIN -p tcp --dport "$port" -j RETURN
        iptables -t nat -A $XRAY_CHAIN -p tcp --dport "$port" -j RETURN
    done
    
    # TPROXY и REDIRECT правила
    if [[ -n "$XRAY_TPROXY_PORT" ]]; then
        iptables -t mangle -A $XRAY_CHAIN -p udp -j TPROXY --on-port $XRAY_TPROXY_PORT --tproxy-mark $MARK_ID/0xffffffff
        log OK "Применено TPROXY для UDP на порт $XRAY_TPROXY_PORT"
    fi
    
    if [[ -n "$XRAY_REDIRECT_PORT" ]]; then
        iptables -t nat -A $XRAY_CHAIN -p tcp -j REDIRECT --to-ports $XRAY_REDIRECT_PORT
        log OK "Применено REDIRECT для TCP на порт $XRAY_REDIRECT_PORT"
    fi
    
    # Исключение трафика Xray
    iptables -t mangle -A OUTPUT -m owner ! --gid-owner $TPROXY_GID -j $XRAY_SELF_CHAIN
    iptables -t mangle -A $XRAY_SELF_CHAIN -j RETURN
    
    # Kill-switch: блокировка внешнего трафика при остановке Xray
    for cidr in $LOCAL_CIDRS 127.0.0.0/8; do
        iptables -t mangle -A XRAY_DISABLED -d "$cidr" -j RETURN
    done
    
    for ip in "${CUSTOM_BYPASS_IPS[@]}"; do
        iptables -t mangle -A XRAY_DISABLED -d "$ip" -j RETURN
    done
    
    for cidr in "${CUSTOM_BYPASS_CIDRS[@]}"; do
        iptables -t mangle -A XRAY_DISABLED -d "$cidr" -j RETURN
    done
    
    for port in "${CUSTOM_BYPASS_PORTS[@]}"; do
        iptables -t mangle -A XRAY_DISABLED -p tcp --dport "$port" -j RETURN
    done
    
    iptables -t mangle -A XRAY_DISABLED -j DROP
    
    log OK "Правила применены"
}

# === Основная функция ===
main() {
    detect_interfaces
    load_exclusions
    
    case "${1:-}" in
        start|apply)
            apply_rules
            ;;
        stop|clear)
            clear_rules
            ;;
        restart|reload)
            clear_rules
            apply_rules
            ;;
        status)
            log INFO "Статус файрвола"
            iptables -t mangle -L XRAY -n -v 2>/dev/null || echo "Цепочка XRAY не найдена"
            ;;
        *)
            echo "Usage: $0 {start|stop|restart|status}"
            exit 1
            ;;
    esac
}

main "$@"
EOF
    
    # Подстановка переменных
    sed -i \
        -e "s|__MARK_ID__|$MARK_ID|g" \
        -e "s|__XRAY_GID__|$XRAY_GID|g" \
        -e "s|__ROUTE_TABLE_ID__|$ROUTE_TABLE_ID|g" \
        -e "s|__XRAY_CONFIG_DIR__|$XRAY_CONFIG_PATH|g" \
        -e "s|__TPROXY_PORT__|$TPROXY_PORT|g" \
        -e "s|__REDIRECT_PORT__|$REDIRECT_PORT|g" \
        -e "s|__LAN_IF__|$LAN_INTERFACE|g" \
        -e "s|__WAN_IF__|$WAN_INTERFACE|g" \
        -e "s|__LOCAL_CIDRS__|$LOCAL_CIDRS|g" \
        -e "s|__FIREWALL_UNIT_NAME__|$FIREWALL_UNIT_NAME|g" \
        -e "s|__FIREWALL_UNIT_PATH__|/etc/systemd/system/$FIREWALL_UNIT_NAME|g" \
        -e "s|__FIREWALL_RESTART_UNIT_NAME__|$FIREWALL_RESTART_UNIT_NAME|g" \
        -e "s|__FIREWALL_RESTART_UNIT_PATH__|/etc/systemd/system/$FIREWALL_RESTART_UNIT_NAME|g" \
        "$FIREWALL_SCRIPT_PATH"
    
    chmod +x "$FIREWALL_SCRIPT_PATH"
    log OK "Скрипт управления iptables создан: $FIREWALL_SCRIPT_PATH"
}

# === Создание systemd юнитов ===
firewall_create_systemd_units() {
    log INFO "Создание systemd юнитов для файрвола"
    
    # Основной юнит файрвола
    cat > "/etc/systemd/system/$FIREWALL_UNIT_NAME" <<EOF
[Unit]
Description=Xray iptables manager
After=network-online.target xray.service
Wants=network-online.target
BindsTo=xray.service
PartOf=xray.service
ConditionPathExists=$FIREWALL_SCRIPT_PATH

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$FIREWALL_SCRIPT_PATH start
ExecStop=$FIREWALL_SCRIPT_PATH stop
WorkingDirectory=$(dirname "$FIREWALL_SCRIPT_PATH")
StandardOutput=journal
StandardError=journal
SuccessExitStatus=0
User=root

[Install]
WantedBy=multi-user.target
EOF
    
    # Юнит для рестарта файрвола при рестарте Xray
    cat > "/etc/systemd/system/$FIREWALL_RESTART_UNIT_NAME" <<EOF
[Unit]
Description=Restart iptables when Xray restarts
After=xray.service
PartOf=xray.service
Requires=xray.service

[Service]
Type=oneshot
ExecStart=/bin/systemctl restart $FIREWALL_UNIT_NAME

[Install]
WantedBy=xray.service
EOF
    
    # Перезагрузка systemd
    systemctl daemon-reload
    
    # Включение юнитов
    systemctl enable "$FIREWALL_UNIT_NAME"
    systemctl enable "$FIREWALL_RESTART_UNIT_NAME"
    
    log OK "Systemd юниты созданы и включены"
}

# === Применение правил ===
firewall_apply_rules() {
    log INFO "Применение правил файрвола"
    
    if [[ -x "$FIREWALL_SCRIPT_PATH" ]]; then
        "$FIREWALL_SCRIPT_PATH" start
        log OK "Правила файрвола применены"
    else
        log ERROR "Скрипт файрвола не найден или не исполняемый: $FIREWALL_SCRIPT_PATH"
        return 1
    fi
}

# === Очистка правил ===
firewall_clear_rules() {
    log INFO "Очистка правил файрвола"
    
    if [[ -x "$FIREWALL_SCRIPT_PATH" ]]; then
        "$FIREWALL_SCRIPT_PATH" stop
        log OK "Правила файрвола очищены"
    else
        log WARN "Скрипт файрвола не найден: $FIREWALL_SCRIPT_PATH"
    fi
}

# === Экспорт функций ===
export -f plugin_firewall_init plugin_firewall_execute plugin_firewall_dependencies plugin_firewall_info
export -f firewall_install firewall_uninstall firewall_status firewall_start firewall_stop firewall_restart
export -f firewall_force_legacy firewall_create_script firewall_create_systemd_units
export -f firewall_apply_rules firewall_clear_rules

# Автоматическая инициализация при загрузке плагина
# ОТКЛЮЧЕНО - плагины инициализируются вручную из installer.sh
# if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
#     # Если скрипт запущен напрямую
#     main "$@"
# fi
