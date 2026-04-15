#!/usr/bin/env bash

# === Шаблон скрипта управления iptables для Xray Gateway ===
# Этот файл используется как шаблон для генерации рабочего скрипта

set -euo pipefail

# === Конфигурация ===
MARK_ID="__MARK_ID__"
TPROXY_GID="__XRAY_GID__"
ROUTE_TABLE_ID="__ROUTE_TABLE_ID__"

XRAY_CHAIN="__XRAY_CHAIN__"
XRAY_SELF_CHAIN="__XRAY_SELF_CHAIN__"
XRAY_ENABLED_CHAIN="__XRAY_ENABLED_CHAIN__"
XRAY_DISABLED_CHAIN="__XRAY_DISABLED_CHAIN__"

XRAY_CONFIG_DIR="__XRAY_CONFIG_DIR__"
XRAY_TPROXY_PORT="__TPROXY_PORT__"
XRAY_REDIRECT_PORT="__REDIRECT_PORT__"
LAN_IF="__LAN_IF__"
WAN_IF="__WAN_IF__"
LOCAL_CIDRS="__LOCAL_CIDRS__"

SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

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
