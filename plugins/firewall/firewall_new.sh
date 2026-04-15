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
            log ERROR "Неизвестное действие: $action"
            return 1
            ;;
    esac
}

# === Зависимости плагина ===
plugin_firewall_dependencies() {
    echo "network system xray"
}

# === Информация о плагине ===
plugin_firewall_info() {
    echo "Плагин управления файрволом и kill-switch функциональностью"
}

# === Установка плагина ===
firewall_install() {
    log INFO "Установка плагина файрвола"
    
    # Принудительное использование iptables-legacy
    firewall_force_legacy
    
    # Создание скрипта управления iptables
    firewall_create_script
    
    # Создание systemd юнитов
    firewall_create_systemd_units
    
    log OK "Плагин файрвола установлен"
}

# === Удаление плагина ===
firewall_uninstall() {
    log INFO "Удаление плагина файрвола"
    
    # Остановка и удаление systemd юнитов
    systemctl stop "$FIREWALL_UNIT_NAME" 2>/dev/null || true
    systemctl disable "$FIREWALL_UNIT_NAME" 2>/dev/null || true
    rm -f "/etc/systemd/system/$FIREWALL_UNIT_NAME"
    rm -f "/etc/systemd/system/$FIREWALL_RESTART_UNIT_NAME"
    systemctl daemon-reload
    
    # Удаление скрипта
    rm -f "$FIREWALL_SCRIPT_PATH"
    
    log OK "Плагин файрвола удален"
}

# === Статус плагина ===
firewall_status() {
    log INFO "Статус плагина файрвола"
    
    if [[ -f "$FIREWALL_SCRIPT_PATH" ]]; then
        log OK "Скрипт файрвола: $FIREWALL_SCRIPT_PATH"
    else
        log WARN "Скрипт файрвола не найден: $FIREWALL_SCRIPT_PATH"
    fi
    
    if systemctl is-active "$FIREWALL_UNIT_NAME" >/dev/null 2>&1; then
        log OK "Сервис файрвола активен"
    else
        log WARN "Сервис файрвола неактивен"
    fi
}

# === Запуск файрвола ===
firewall_start() {
    log INFO "Запуск файрвола"
    
    if [[ -f "$FIREWALL_SCRIPT_PATH" ]]; then
        "$FIREWALL_SCRIPT_PATH" start
        systemctl start "$FIREWALL_UNIT_NAME"
        log OK "Файрвол запущен"
    else
        log ERROR "Скрипт файрвола не найден: $FIREWALL_SCRIPT_PATH"
        return 1
    fi
}

# === Остановка файрвола ===
firewall_stop() {
    log INFO "Остановка файрвола"
    
    if [[ -f "$FIREWALL_SCRIPT_PATH" ]]; then
        "$FIREWALL_SCRIPT_PATH" stop
        systemctl stop "$FIREWALL_UNIT_NAME"
        log OK "Файрвол остановлен"
    else
        log WARN "Скрипт файрвола не найден: $FIREWALL_SCRIPT_PATH"
    fi
}

# === Перезапуск файрвола ===
firewall_restart() {
    log INFO "Перезапуск файрвола"
    
    firewall_stop
    sleep 1
    firewall_start
}

# === Принудительное использование iptables-legacy ===
firewall_force_legacy() {
    log INFO "Переключение на iptables-legacy"
    
    # Обновление альтернатив
    update-alternatives --install /usr/sbin/iptables iptables /usr/sbin/iptables-legacy 1
    update-alternatives --install /usr/sbin/ip6tables ip6tables /usr/sbin/ip6tables-legacy 1
    
    # Установка iptables-legacy как активной версии
    update-alternatives --set iptables /usr/sbin/iptables-legacy
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
    
    log OK "Переключение на iptables-legacy завершено"
}

# === Создание скрипта управления iptables ===
firewall_create_script() {
    log INFO "Создание скрипта управления iptables"
    
    # Создание директории для скрипта
    local script_dir="$(dirname "$FIREWALL_SCRIPT_PATH")"
    create_directory "$script_dir" "root" "root" "755"
    
    # Создание скрипта с правильной структурой
    cat > "$FIREWALL_SCRIPT_PATH" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

# === Скрипт управления iptables для Xray Gateway ===
# Этот скрипт генерируется плагином firewall

# Константы (будут заменены при генерации)
MARK_ID="__MARK_ID__"
ROUTE_TABLE_ID="__ROUTE_TABLE_ID__"
TPROXY_PORT="__TPROXY_PORT__"
REDIRECT_PORT="__REDIRECT_PORT__"
LAN_IF="__LAN_IF__"
WAN_IF="__WAN_IF__"
LOCAL_CIDRS="__LOCAL_CIDRS__"
XRAY_GID="__XRAY_GID__"
XRAY_CONFIG_DIR="__XRAY_CONFIG_DIR__"

# Имена цепочек
XRAY_CHAIN="XRAY"
XRAY_SELF_CHAIN="XRAY_SELF"
XRAY_ENABLED_CHAIN="XRAY_ENABLED"
XRAY_DISABLED_CHAIN="XRAY_DISABLED"

# Массивы для исключений
CUSTOM_BYPASS_CIDRS=()
CUSTOM_BYPASS_IPS=()
CUSTOM_BYPASS_PORTS=()

# === Функция логирования ===
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [$level] [firewall] $message"
}

# === Определение интерфейсов ===
detect_interfaces() {
    log INFO "Определение сетевых интерфейсов"
    
    # Получение интерфейсов из конфигурации
    if [[ -n "$LAN_IF" && -n "$WAN_IF" ]]; then
        log OK "Интерфейсы определены: LAN=$LAN_IF, WAN=$WAN_IF"
        return 0
    fi
    
    # Автоопределение интерфейсов
    local interfaces
    interfaces="$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)"
    
    local if_count
    if_count="$(echo "$interfaces" | wc -l)"
    
    if [[ $if_count -lt 2 ]]; then
        log ERROR "Недостаточно сетевых интерфейсов для работы шлюза"
        exit 1
    fi
    
    # Простое назначение: первый интерфейс = LAN, второй = WAN
    LAN_IF="$(echo "$interfaces" | head -n1)"
    WAN_IF="$(echo "$interfaces" | head -n2 | tail -n1)"
    
    log OK "Автоопределение интерфейсов: LAN=$LAN_IF, WAN=$WAN_IF"
}

# === Загрузка исключений ===
load_exclusions() {
    log INFO "Загрузка исключений из конфигурационных файлов"
    
    local base_dir="$XRAY_CONFIG_DIR"
    
    # Создание файлов исключений если их нет
    [[ -f "$base_dir/exclude_cidrs.txt" ]] || cat > "$base_dir/exclude_cidrs.txt" <<'EXCLUDE_EOF'
# CIDR-сети, исключаемые из обработки
# Пример:
# 10.0.0.0/8
# 192.168.0.0/16
EXCLUDE_EOF
    
    [[ -f "$base_dir/exclude_ips.txt" ]] || cat > "$base_dir/exclude_ips.txt" <<'EXCLUDE_EOF'
# IP-адреса, исключаемые из обработки
# Пример:
# 8.8.8.8
# 1.1.1.1
EXCLUDE_EOF
    
    [[ -f "$base_dir/exclude_ports.txt" ]] || cat > "$base_dir/exclude_ports.txt" <<'EXCLUDE_EOF'
# TCP-порты, исключаемые из обработки
# Пример:
# 22     # SSH
# 443    # HTTPS
# 8080   # Локальный UI
EXCLUDE_EOF
    
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
    iptables -t mangle -D OUTPUT -m owner ! --gid-owner $XRAY_GID -j $XRAY_SELF_CHAIN 2>/dev/null || true
    
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
    if [[ -n "$TPROXY_PORT" ]]; then
        iptables -t mangle -A $XRAY_CHAIN -p udp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark $MARK_ID/0xffffffff
        log OK "Применено TPROXY для UDP на порт $TPROXY_PORT"
    fi
    
    if [[ -n "$REDIRECT_PORT" ]]; then
        iptables -t nat -A $XRAY_CHAIN -p tcp -j REDIRECT --to-ports $REDIRECT_PORT
        log OK "Применено REDIRECT для TCP на порт $REDIRECT_PORT"
    fi
    
    # Исключение трафика Xray
    iptables -t mangle -A OUTPUT -m owner ! --gid-owner $XRAY_GID -j $XRAY_SELF_CHAIN
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
Description=Xray Gateway Firewall
After=network.target
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$FIREWALL_SCRIPT_PATH start
ExecStop=$FIREWALL_SCRIPT_PATH stop
ExecReload=$FIREWALL_SCRIPT_PATH restart

[Install]
WantedBy=multi-user.target
EOF

    # Юнит для перезапуска при изменении конфигурации
    cat > "/etc/systemd/system/$FIREWALL_RESTART_UNIT_NAME" <<EOF
[Unit]
Description=Xray Gateway Firewall Restart
After=xray.service
Wants=xray.service

[Service]
Type=oneshot
ExecStart=$FIREWALL_SCRIPT_PATH restart

[Install]
WantedBy=multi-user.target
EOF

    # Перезагрузка systemd
    systemctl daemon-reload
    
    # Включение автозапуска
    systemctl enable "$FIREWALL_UNIT_NAME"
    
    log OK "Systemd юниты созданы и включены"
}

# === Экспорт функций ===
export -f plugin_firewall_init plugin_firewall_execute plugin_firewall_dependencies plugin_firewall_info
export -f firewall_install firewall_uninstall firewall_status firewall_start firewall_stop firewall_restart
export -f firewall_force_legacy firewall_create_script firewall_create_systemd_units
export -f firewall_apply_rules firewall_clear_rules

# При загрузке как плагин НЕ вызываем plugin_firewall_init автоматически
# Инициализация будет вызвана вручную из installer.sh
