#!/usr/bin/env bash

# === Детектор сетевых интерфейсов ===
# Версия: 2.0.0
# Автор: Xray Gateway Installer Team
# Описание: Автоматическое определение LAN и WAN интерфейсов

# === Определение WAN интерфейса ===
detect_wan_interface() {
    # Поиск интерфейса с default route
    local wan_if
    wan_if=$(ip route | awk '/default/ {print $5}' | head -n1)
    
    if [[ -n "$wan_if" ]]; then
        echo "$wan_if"
        return 0
    else
        echo "ERROR: Не удалось определить WAN интерфейс"
        return 1
    fi
}

# === Определение LAN интерфейса ===
detect_lan_interface() {
    local wan_if="$1"
    local lan_if
    
    # Поиск второго интерфейса (не WAN и не lo)
    lan_if=$(ip -o link show | awk -F': ' '{print $2}' | grep -Ev "^lo$|^$wan_if$" | head -n1)
    
    if [[ -n "$lan_if" ]]; then
        echo "$lan_if"
        return 0
    else
        # Если второй интерфейс не найден, используем WAN
        echo "$wan_if"
        return 0
    fi
}

# === Получение CIDR для интерфейса ===
get_interface_cidrs() {
    local interface="$1"
    local cidrs
    
    cidrs=$(ip -o -f inet addr show "$interface" 2>/dev/null | awk '{print $4}')
    
    if [[ -n "$cidrs" ]]; then
        echo "$cidrs"
        return 0
    else
        echo "ERROR: Не удалось получить CIDR для интерфейса $interface"
        return 1
    fi
}

# === Получение всех локальных CIDR ===
get_all_local_cidrs() {
    local lan_if="$1"
    local wan_if="$2"
    local lan_cidrs wan_cidrs all_cidrs
    
    # Получение CIDR для LAN
    if lan_cidrs=$(get_interface_cidrs "$lan_if"); then
        echo "LAN CIDRs: $lan_cidrs"
    fi
    
    # Получение CIDR для WAN
    if wan_cidrs=$(get_interface_cidrs "$wan_if"); then
        echo "WAN CIDRs: $wan_cidrs"
    fi
    
    # Объединение всех CIDR
    all_cidrs=$(echo "$lan_cidrs $wan_cidrs" | xargs)
    echo "$all_cidrs"
}

# === Проверка интерфейса ===
check_interface() {
    local interface="$1"
    
    if ip link show "$interface" >/dev/null 2>&1; then
        echo "OK: Интерфейс $interface существует"
        return 0
    else
        echo "ERROR: Интерфейс $interface не найден"
        return 1
    fi
}

# === Получение информации об интерфейсе ===
get_interface_info() {
    local interface="$1"
    
    echo "=== Информация об интерфейсе $interface ==="
    
    # Статус
    if ip link show "$interface" | grep -q "state UP"; then
        echo "Статус: UP"
    else
        echo "Статус: DOWN"
    fi
    
    # IP адреса
    echo "IP адреса:"
    ip -o -f inet addr show "$interface" 2>/dev/null | awk '{print "  " $4}'
    
    # Маршруты
    echo "Маршруты:"
    ip route show dev "$interface" 2>/dev/null | head -5
}

# === Основная функция ===
main() {
    local action="${1:-detect}"
    
    case "$action" in
        "detect")
            echo "=== Автоматическое определение интерфейсов ==="
            
            local wan_if lan_if
            if wan_if=$(detect_wan_interface); then
                echo "WAN интерфейс: $wan_if"
                if lan_if=$(detect_lan_interface "$wan_if"); then
                    echo "LAN интерфейс: $lan_if"
                    
                    # Получение CIDR
                    local cidrs
                    if cidrs=$(get_all_local_cidrs "$lan_if" "$wan_if"); then
                        echo "Локальные CIDR: $cidrs"
                    fi
                fi
            fi
            ;;
        "check")
            local interface="$2"
            if [[ -n "$interface" ]]; then
                check_interface "$interface"
                get_interface_info "$interface"
            else
                echo "ERROR: Укажите интерфейс для проверки"
                exit 1
            fi
            ;;
        "info")
            local interface="$2"
            if [[ -n "$interface" ]]; then
                get_interface_info "$interface"
            else
                echo "ERROR: Укажите интерфейс для получения информации"
                exit 1
            fi
            ;;
        *)
            echo "Usage: $0 {detect|check|info} [interface]"
            exit 1
            ;;
    esac
}

# === Запуск ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
