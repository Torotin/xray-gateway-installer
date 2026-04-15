#!/usr/bin/env bash

# === Компонент управления сетевыми интерфейсами ===
# Версия: 2.0.0
# Автор: Xray Gateway Installer Team

# === Инициализация компонента ===
interfaces_init() {
    log INFO "Инициализация компонента управления сетевыми интерфейсами"
    log OK "Компонент управления сетевыми интерфейсами инициализирован"
    return 0
}

# === Обнаружение интерфейсов ===
interfaces_detect() {
    log INFO "Обнаружение сетевых интерфейсов"

    local wan_interface
    wan_interface="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"

    local interfaces=()
    while IFS= read -r iface; do
        [[ -n "$iface" ]] && interfaces+=("$iface")
    done < <(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|ens|enp|eno)')

    if [[ ${#interfaces[@]} -eq 0 ]]; then
        log ERROR "Не найдены подходящие сетевые интерфейсы"
        return 1
    fi

    if [[ -z "$wan_interface" ]]; then
        wan_interface="${interfaces[0]}"
        log WARN "Default route не найден, WAN принят по первому интерфейсу: $wan_interface"
    fi

    local lan_interface=""
    local iface
    for iface in "${interfaces[@]}"; do
        if [[ "$iface" != "$wan_interface" ]]; then
            lan_interface="$iface"
            break
        fi
    done

    if [[ -z "$lan_interface" ]]; then
        lan_interface="$wan_interface"
        log WARN "Отдельный LAN интерфейс не найден, используется $lan_interface"
    fi

    log OK "LAN интерфейс: $lan_interface"
    log OK "WAN интерфейс: $wan_interface"
    
    # Сохранение в глобальные переменные
    declare -g LAN_INTERFACE="$lan_interface"
    declare -g WAN_INTERFACE="$wan_interface"
}

# === Переименование интерфейсов ===
interfaces_rename() {
    log INFO "Переименование сетевых интерфейсов"
    
    # Проверка настройки из конфигурации или интерактивный запрос
    ask_and_execute "network" "rename_interfaces" "Переименовать интерфейсы в eth0/eth1 (рекомендуется)?" "true" "interfaces_rename_impl"
}

# === Реализация переименования интерфейсов ===
interfaces_rename_impl() {
    if compgen -G "/etc/netplan/*.yaml" >/dev/null 2>&1 || systemctl is-active --quiet systemd-networkd 2>/dev/null; then
        log WARN "Переименование интерфейсов пропущено: хост использует netplan/systemd-networkd"
        return 0
    fi

    if [[ "$LAN_INTERFACE" == "eth0" && "$WAN_INTERFACE" == "eth1" ]]; then
        log INFO "Интерфейсы уже имеют ожидаемые имена, переименование не требуется"
        return 0
    fi

    # Переименование интерфейсов
    if [[ -n "$LAN_INTERFACE" && "$LAN_INTERFACE" != "eth0" ]]; then
        ip link set "$LAN_INTERFACE" down
        ip link set "$LAN_INTERFACE" name eth0
        ip link set eth0 up
        log OK "Интерфейс $LAN_INTERFACE переименован в eth0"
    fi
    
    if [[ -n "$WAN_INTERFACE" && "$WAN_INTERFACE" != "eth1" && "$WAN_INTERFACE" != "$LAN_INTERFACE" ]]; then
        ip link set "$WAN_INTERFACE" down
        ip link set "$WAN_INTERFACE" name eth1
        ip link set eth1 up
        log OK "Интерфейс $WAN_INTERFACE переименован в eth1"
    fi
    
    # Обновление переменных только если переименование реально выполнено
    [[ -n "${LAN_INTERFACE:-}" ]] && LAN_INTERFACE="eth0"
    [[ -n "${WAN_INTERFACE:-}" ]] && WAN_INTERFACE="eth1"
    
    log OK "Переименование интерфейсов завершено"
}

# === Создание дампа конфигурации ===
interfaces_create_dump() {
    log INFO "Создание дампа сетевой конфигурации"
    
    local dump_file="${SCRIPT_DIR}/network_dump.txt"
    
    cat > "$dump_file" << EOF
=== Сетевой дамп ===
Дата: $(date)
LAN интерфейс: ${LAN_INTERFACE:-не определен}
WAN интерфейс: ${WAN_INTERFACE:-не определен}

=== Интерфейсы ===
$(ip -o link show)

=== Маршруты ===
$(ip route show)

=== ARP таблица ===
$(ip neigh show)
EOF
    
    log OK "Дамп сетевой конфигурации создан: $dump_file"
}

# === Переключение на iptables-legacy ===
interfaces_force_legacy() {
    log INFO "Переключение iptables и родственных утилит на legacy-бэкенд"
    
    for tool in iptables ip6tables arptables ebtables; do
        local legacy_path="/usr/sbin/${tool}-legacy"
        if [[ -x "$legacy_path" ]]; then
            update-alternatives --install "/usr/sbin/$tool" "$tool" "$legacy_path" 100
            update-alternatives --set "$tool" "$legacy_path"
            log OK "$tool переключён на legacy-бэкенд"
        else
            log INFO "Пропуск $tool: legacy-бэкенд отсутствует"
        fi
    done
    
    local backend
    backend=$(update-alternatives --query iptables | awk '/Value: / {print $2}')
    if [[ "$backend" != "/usr/sbin/iptables-legacy" ]]; then
        log ERROR "iptables не использует legacy-бэкенд: $backend"
        return 1
    else
        log OK "iptables работает в режиме legacy"
    fi
}

# === Статус интерфейсов ===
interfaces_status() {
    echo "LAN интерфейс: ${LAN_INTERFACE:-не определен}"
    echo "WAN интерфейс: ${WAN_INTERFACE:-не определен}"
    echo "Активные интерфейсы:"
    ip -o link show | grep -E '^(eth|ens|enp|eno)' | while read -r line; do
        echo "  $line"
    done
}

# === Экспорт функций ===
export -f interfaces_init interfaces_detect interfaces_rename interfaces_rename_impl interfaces_create_dump interfaces_status interfaces_force_legacy

# Автоматическая инициализация при загрузке компонента
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Если скрипт запущен напрямую
    interfaces_init "$@"
else
    # Если скрипт загружен как компонент
    interfaces_init
fi
