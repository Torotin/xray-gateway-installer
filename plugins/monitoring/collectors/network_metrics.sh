#!/usr/bin/env bash

# =============================================================================
# Network Metrics Collector
# =============================================================================
# Сборщик сетевых метрик для мониторинга Xray Gateway
# =============================================================================

# === СБОР СЕТЕВЫХ МЕТРИК ===
collect_network_metrics() {
    local metrics="{}"
    
    # Статистика iptables правил
    local iptables_rules_count
    iptables_rules_count=$(get_iptables_rules_count)
    metrics=$(echo "$metrics" | jq --arg rules "$iptables_rules_count" '.iptables_rules_count = ($rules | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Статистика заблокированных пакетов
    local blocked_packets_count
    blocked_packets_count=$(get_blocked_packets_count)
    metrics=$(echo "$metrics" | jq --arg blocked "$blocked_packets_count" '.blocked_packets_count = ($blocked | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Статистика заблокированных байт
    local blocked_bytes_count
    blocked_bytes_count=$(get_blocked_bytes_count)
    metrics=$(echo "$metrics" | jq --arg blocked_bytes "$blocked_bytes_count" '.blocked_bytes_count = ($blocked_bytes | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Статистика разрешенных пакетов
    local accepted_packets_count
    accepted_packets_count=$(get_accepted_packets_count)
    metrics=$(echo "$metrics" | jq --arg accepted "$accepted_packets_count" '.accepted_packets_count = ($accepted | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Сетевой трафик (MB/s)
    local traffic_rx_mbps traffic_tx_mbps
    traffic_rx_mbps=$(get_network_traffic_rx_mbps)
    traffic_tx_mbps=$(get_network_traffic_tx_mbps)
    metrics=$(echo "$metrics" | jq --arg rx "$traffic_rx_mbps" '.traffic_rx_mbps = ($rx | tonumber)' 2>/dev/null || echo "$metrics")
    metrics=$(echo "$metrics" | jq --arg tx "$traffic_tx_mbps" '.traffic_tx_mbps = ($tx | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Количество активных соединений
    local active_connections
    active_connections=$(get_active_connections_count)
    metrics=$(echo "$metrics" | jq --arg conns "$active_connections" '.active_connections = ($conns | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Статус сетевых интерфейсов
    local interfaces_status
    interfaces_status=$(get_interfaces_status)
    metrics=$(echo "$metrics" | jq --argjson ifaces "$interfaces_status" '.interfaces = $ifaces' 2>/dev/null || echo "$metrics")
    
    # Маршрутизация
    local routing_rules_count
    routing_rules_count=$(get_routing_rules_count)
    metrics=$(echo "$metrics" | jq --arg routes "$routing_rules_count" '.routing_rules_count = ($routes | tonumber)' 2>/dev/null || echo "$metrics")
    
    # TProxy соединения
    local tproxy_connections
    tproxy_connections=$(get_tproxy_connections_count)
    metrics=$(echo "$metrics" | jq --arg tproxy "$tproxy_connections" '.tproxy_connections = ($tproxy | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Redirect соединения
    local redirect_connections
    redirect_connections=$(get_redirect_connections_count)
    metrics=$(echo "$metrics" | jq --arg redirect "$redirect_connections" '.redirect_connections = ($redirect | tonumber)' 2>/dev/null || echo "$metrics")
    
    echo "$metrics"
}

# === КОЛИЧЕСТВО IPTABLES ПРАВИЛ ===
get_iptables_rules_count() {
    local total_rules=0
    
    # Подсчет правил в основных таблицах
    for table in mangle nat filter; do
        local table_rules
        table_rules=$(iptables -t "$table" -L -n 2>/dev/null | grep -c "^[A-Z]" || echo "0")
        total_rules=$((total_rules + table_rules))
    done
    
    echo "$total_rules"
}

# === КОЛИЧЕСТВО ЗАБЛОКИРОВАННЫХ ПАКЕТОВ ===
get_blocked_packets_count() {
    local blocked_packets=0
    
    # Подсчет DROP пакетов в цепочке XRAY_DISABLED
    if iptables -t mangle -L XRAY_DISABLED -n -v 2>/dev/null | grep -q "DROP"; then
        blocked_packets=$(iptables -t mangle -L XRAY_DISABLED -n -v 2>/dev/null | grep "DROP" | awk '{sum += $1} END {print sum+0}')
    fi
    
    echo "${blocked_packets:-0}"
}

# === КОЛИЧЕСТВО ЗАБЛОКИРОВАННЫХ БАЙТ ===
get_blocked_bytes_count() {
    local blocked_bytes=0
    
    # Подсчет DROP байт в цепочке XRAY_DISABLED
    if iptables -t mangle -L XRAY_DISABLED -n -v 2>/dev/null | grep -q "DROP"; then
        blocked_bytes=$(iptables -t mangle -L XRAY_DISABLED -n -v 2>/dev/null | grep "DROP" | awk '{sum += $2} END {print sum+0}')
    fi
    
    echo "${blocked_bytes:-0}"
}

# === КОЛИЧЕСТВО РАЗРЕШЕННЫХ ПАКЕТОВ ===
get_accepted_packets_count() {
    local accepted_packets=0
    
    # Подсчет ACCEPT пакетов в основных цепочках
    for table in mangle nat filter; do
        local table_accepts
        table_accepts=$(iptables -t "$table" -L -n -v 2>/dev/null | grep "ACCEPT" | awk '{sum += $1} END {print sum+0}')
        accepted_packets=$((accepted_packets + table_accepts))
    done
    
    echo "$accepted_packets"
}

# === СЕТЕВОЙ ТРАФИК RX (MB/s) ===
get_network_traffic_rx_mbps() {
    local interfaces=("eth0" "eth1" "ens18" "ens19")
    local total_rx=0
    
    for iface in "${interfaces[@]}"; do
        if [[ -f "/sys/class/net/$iface/statistics/rx_bytes" ]]; then
            local rx_bytes
            rx_bytes=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo "0")
            total_rx=$((total_rx + rx_bytes))
        fi
    done
    
    # Конвертация из байт в MB
    echo $((total_rx / 1024 / 1024))
}

# === СЕТЕВОЙ ТРАФИК TX (MB/s) ===
get_network_traffic_tx_mbps() {
    local interfaces=("eth0" "eth1" "ens18" "ens19")
    local total_tx=0
    
    for iface in "${interfaces[@]}"; do
        if [[ -f "/sys/class/net/$iface/statistics/tx_bytes" ]]; then
            local tx_bytes
            tx_bytes=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo "0")
            total_tx=$((total_tx + tx_bytes))
        fi
    done
    
    # Конвертация из байт в MB
    echo $((total_tx / 1024 / 1024))
}

# === КОЛИЧЕСТВО АКТИВНЫХ СОЕДИНЕНИЙ ===
get_active_connections_count() {
    local connections
    connections=$(ss -tuln 2>/dev/null | wc -l || echo "0")
    # Вычитаем заголовок
    echo $((connections - 1))
}

# === СТАТУС СЕТЕВЫХ ИНТЕРФЕЙСОВ ===
get_interfaces_status() {
    local interfaces_json="{}"
    local interfaces=("eth0" "eth1" "ens18" "ens19")
    
    for iface in "${interfaces[@]}"; do
        if [[ -d "/sys/class/net/$iface" ]]; then
            local status="down"
            local speed="unknown"
            local mtu="unknown"
            
            # Проверка статуса интерфейса
            if [[ "$(cat /sys/class/net/$iface/operstate 2>/dev/null)" == "up" ]]; then
                status="up"
            fi
            
            # Получение скорости
            if [[ -f "/sys/class/net/$iface/speed" ]]; then
                speed=$(cat "/sys/class/net/$iface/speed" 2>/dev/null || echo "unknown")
            fi
            
            # Получение MTU
            if [[ -f "/sys/class/net/$iface/mtu" ]]; then
                mtu=$(cat "/sys/class/net/$iface/mtu" 2>/dev/null || echo "unknown")
            fi
            
            # Добавление в JSON
            local iface_json="{\"status\":\"$status\",\"speed\":\"$speed\",\"mtu\":\"$mtu\"}"
            interfaces_json=$(echo "$interfaces_json" | jq --arg iface "$iface" --argjson data "$iface_json" '.[$iface] = $data' 2>/dev/null || echo "$interfaces_json")
        fi
    done
    
    echo "$interfaces_json"
}

# === КОЛИЧЕСТВО ПРАВИЛ МАРШРУТИЗАЦИИ ===
get_routing_rules_count() {
    local rules_count
    rules_count=$(ip rule list 2>/dev/null | wc -l || echo "0")
    echo "$rules_count"
}

# === КОЛИЧЕСТВО TPROXY СОЕДИНЕНИЙ ===
get_tproxy_connections_count() {
    local tproxy_count=0
    
    # Подсчет TPROXY соединений через ss
    if command -v ss >/dev/null 2>&1; then
        tproxy_count=$(ss -tuln | grep -c "tproxy" 2>/dev/null || echo "0")
    fi
    
    echo "$tproxy_count"
}

# === КОЛИЧЕСТВО REDIRECT СОЕДИНЕНИЙ ===
get_redirect_connections_count() {
    local redirect_count=0
    
    # Подсчет REDIRECT соединений через ss
    if command -v ss >/dev/null 2>&1; then
        redirect_count=$(ss -tuln | grep -c "redirect" 2>/dev/null || echo "0")
    fi
    
    echo "$redirect_count"
}

# === ДОПОЛНИТЕЛЬНЫЕ СЕТЕВЫЕ МЕТРИКИ ===

# Получение статистики ошибок сети
get_network_errors_count() {
    local total_errors=0
    local interfaces=("eth0" "eth1" "ens18" "ens19")
    
    for iface in "${interfaces[@]}"; do
        if [[ -f "/sys/class/net/$iface/statistics/rx_errors" && -f "/sys/class/net/$iface/statistics/tx_errors" ]]; then
            local rx_errors tx_errors
            rx_errors=$(cat "/sys/class/net/$iface/statistics/rx_errors" 2>/dev/null || echo "0")
            tx_errors=$(cat "/sys/class/net/$iface/statistics/tx_errors" 2>/dev/null || echo "0")
            total_errors=$((total_errors + rx_errors + tx_errors))
        fi
    done
    
    echo "$total_errors"
}

# Получение статистики отброшенных пакетов
get_dropped_packets_count() {
    local total_dropped=0
    local interfaces=("eth0" "eth1" "ens18" "ens19")
    
    for iface in "${interfaces[@]}"; do
        if [[ -f "/sys/class/net/$iface/statistics/rx_dropped" && -f "/sys/class/net/$iface/statistics/tx_dropped" ]]; then
            local rx_dropped tx_dropped
            rx_dropped=$(cat "/sys/class/net/$iface/statistics/rx_dropped" 2>/dev/null || echo "0")
            tx_dropped=$(cat "/sys/class/net/$iface/statistics/tx_dropped" 2>/dev/null || echo "0")
            total_dropped=$((total_dropped + rx_dropped + tx_dropped))
        fi
    done
    
    echo "$total_dropped"
}

# === ЭКСПОРТ ФУНКЦИЙ ===
export -f collect_network_metrics
export -f get_iptables_rules_count get_blocked_packets_count get_blocked_bytes_count
export -f get_accepted_packets_count get_network_traffic_rx_mbps get_network_traffic_tx_mbps
export -f get_active_connections_count get_interfaces_status get_routing_rules_count
export -f get_tproxy_connections_count get_redirect_connections_count
export -f get_network_errors_count get_dropped_packets_count
