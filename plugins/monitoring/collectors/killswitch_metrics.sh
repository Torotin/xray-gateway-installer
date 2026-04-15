#!/usr/bin/env bash

# =============================================================================
# Kill-Switch Metrics Collector
# =============================================================================
# Сборщик метрик Kill-Switch для мониторинга Xray Gateway
# =============================================================================

# === СБОР МЕТРИК KILL-SWITCH ===
collect_killswitch_metrics() {
    local metrics="{}"
    
    # Режим Kill-Switch
    local mode
    mode=$(get_killswitch_mode)
    metrics=$(echo "$metrics" | jq --arg mode "$mode" '.mode = $mode' 2>/dev/null || echo "$metrics")
    
    # Статус автоматического переключения
    local auto_switching
    auto_switching=$(is_killswitch_auto_switching)
    metrics=$(echo "$metrics" | jq --arg auto "$auto_switching" '.auto_switching = ($auto | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Количество автоматических переключений
    local auto_switches_count
    auto_switches_count=$(get_killswitch_auto_switches_count)
    metrics=$(echo "$metrics" | jq --arg switches "$auto_switches_count" '.auto_switches_count = ($switches | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Время последнего переключения
    local last_switch_timestamp
    last_switch_timestamp=$(get_killswitch_last_switch_timestamp)
    metrics=$(echo "$metrics" | jq --arg timestamp "$last_switch_timestamp" '.last_switch_timestamp = $timestamp' 2>/dev/null || echo "$metrics")
    
    # Статус цепочек iptables
    local chains_status
    chains_status=$(get_killswitch_chains_status)
    metrics=$(echo "$metrics" | jq --argjson chains "$chains_status" '.chains = $chains' 2>/dev/null || echo "$metrics")
    
    # Статистика блокировки
    local blocking_stats
    blocking_stats=$(get_killswitch_blocking_stats)
    metrics=$(echo "$metrics" | jq --argjson stats "$blocking_stats" '.blocking_stats = $stats' 2>/dev/null || echo "$metrics")
    
    # Статус watchdog
    local watchdog_status
    watchdog_status=$(get_killswitch_watchdog_status)
    metrics=$(echo "$metrics" | jq --argjson watchdog "$watchdog_status" '.watchdog = $watchdog' 2>/dev/null || echo "$metrics")
    
    # Время работы в текущем режиме
    local current_mode_uptime
    current_mode_uptime=$(get_killswitch_current_mode_uptime)
    metrics=$(echo "$metrics" | jq --arg uptime "$current_mode_uptime" '.current_mode_uptime = ($uptime | tonumber)' 2>/dev/null || echo "$metrics")
    
    echo "$metrics"
}

# === РЕЖИМ KILL-SWITCH ===
get_killswitch_mode() {
    # Проверка, какая цепочка активна в PREROUTING
    if iptables -t mangle -L PREROUTING -n 2>/dev/null | grep -q "XRAY_ENABLED"; then
        echo "disabled"  # Kill-Switch отключен, Xray работает
    elif iptables -t mangle -L PREROUTING -n 2>/dev/null | grep -q "XRAY_DISABLED"; then
        echo "enabled"   # Kill-Switch активен, Xray остановлен
    else
        echo "unknown"   # Неизвестное состояние
    fi
}

# === СТАТУС АВТОМАТИЧЕСКОГО ПЕРЕКЛЮЧЕНИЯ ===
is_killswitch_auto_switching() {
    # Проверка, работает ли watchdog
    if systemctl is-active --quiet xray-killswitch-watchdog 2>/dev/null; then
        echo "1"
    else
        echo "0"
    fi
}

# === КОЛИЧЕСТВО АВТОМАТИЧЕСКИХ ПЕРЕКЛЮЧЕНИЙ ===
get_killswitch_auto_switches_count() {
    # Подсчет переключений из логов watchdog
    local switches_count
    switches_count=$(journalctl -u xray-killswitch-watchdog --since "24 hours ago" --no-pager | grep -c "Переключение в" 2>/dev/null || echo "0")
    echo "$switches_count"
}

# === ВРЕМЯ ПОСЛЕДНЕГО ПЕРЕКЛЮЧЕНИЯ ===
get_killswitch_last_switch_timestamp() {
    # Получение времени последнего переключения из логов
    local last_switch
    last_switch=$(journalctl -u xray-killswitch-watchdog --since "24 hours ago" --no-pager | grep "Переключение в" | tail -1 | awk '{print $1" "$2" "$3}' 2>/dev/null || echo "")
    
    if [[ -n "$last_switch" ]]; then
        # Конвертация в ISO формат
        date -d "$last_switch" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "$last_switch"
    else
        echo "never"
    fi
}

# === СТАТУС ЦЕПОЧЕК IPTABLES ===
get_killswitch_chains_status() {
    local chains_json="{}"
    local chains=("XRAY" "XRAY_ENABLED" "XRAY_DISABLED" "XRAY_SELF")
    
    for chain in "${chains[@]}"; do
        local exists="false"
        local rules_count=0
        local references=0
        
        # Проверка существования цепочки
        if iptables -t mangle -L "$chain" >/dev/null 2>&1; then
            exists="true"
            rules_count=$(iptables -t mangle -L "$chain" -n 2>/dev/null | grep -c "^[A-Z]" || echo "0")
            references=$(iptables -t mangle -L -n 2>/dev/null | grep -c "$chain" || echo "0")
        fi
        
        # Добавление в JSON
        local chain_json="{\"exists\":$exists,\"rules_count\":$rules_count,\"references\":$references}"
        chains_json=$(echo "$chains_json" | jq --arg chain "$chain" --argjson data "$chain_json" '.[$chain] = $data' 2>/dev/null || echo "$chains_json")
    done
    
    echo "$chains_json"
}

# === СТАТИСТИКА БЛОКИРОВКИ ===
get_killswitch_blocking_stats() {
    local stats_json="{}"
    
    # Статистика DROP правил
    local drop_packets=0
    local drop_bytes=0
    
    if iptables -t mangle -L XRAY_DISABLED -n -v 2>/dev/null | grep -q "DROP"; then
        drop_packets=$(iptables -t mangle -L XRAY_DISABLED -n -v 2>/dev/null | grep "DROP" | awk '{sum += $1} END {print sum+0}')
        drop_bytes=$(iptables -t mangle -L XRAY_DISABLED -n -v 2>/dev/null | grep "DROP" | awk '{sum += $2} END {print sum+0}')
    fi
    
    # Статистика RETURN правил (разрешенный трафик)
    local return_packets=0
    local return_bytes=0
    
    if iptables -t mangle -L XRAY_DISABLED -n -v 2>/dev/null | grep -q "RETURN"; then
        return_packets=$(iptables -t mangle -L XRAY_DISABLED -n -v 2>/dev/null | grep "RETURN" | awk '{sum += $1} END {print sum+0}')
        return_bytes=$(iptables -t mangle -L XRAY_DISABLED -n -v 2>/dev/null | grep "RETURN" | awk '{sum += $2} END {print sum+0}')
    fi
    
    # Создание JSON
    stats_json="{\"blocked_packets\":$drop_packets,\"blocked_bytes\":$drop_bytes,\"allowed_packets\":$return_packets,\"allowed_bytes\":$return_bytes}"
    
    echo "$stats_json"
}

# === СТАТУС WATCHDOG ===
get_killswitch_watchdog_status() {
    local watchdog_json="{}"
    
    # Статус сервиса
    local service_status="unknown"
    if systemctl is-active --quiet xray-killswitch-watchdog 2>/dev/null; then
        service_status="active"
    elif systemctl is-failed --quiet xray-killswitch-watchdog 2>/dev/null; then
        service_status="failed"
    else
        service_status="inactive"
    fi
    
    # Время работы
    local uptime_seconds=0
    if [[ "$service_status" == "active" ]]; then
        uptime_seconds=$(systemctl show xray-killswitch-watchdog --property=ActiveEnterTimestamp --value 2>/dev/null | xargs -I {} date -d {} +%s 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        uptime_seconds=$((current_time - uptime_seconds))
    fi
    
    # Количество ошибок за последний час
    local error_count=0
    error_count=$(journalctl -u xray-killswitch-watchdog --since "1 hour ago" --no-pager | grep -i "error\|failed" | wc -l 2>/dev/null || echo "0")
    
    # Создание JSON
    watchdog_json="{\"service_status\":\"$service_status\",\"uptime_seconds\":$uptime_seconds,\"error_count\":$error_count}"
    
    echo "$watchdog_json"
}

# === ВРЕМЯ РАБОТЫ В ТЕКУЩЕМ РЕЖИМЕ ===
get_killswitch_current_mode_uptime() {
    local current_mode
    current_mode=$(get_killswitch_mode)
    
    if [[ "$current_mode" == "unknown" ]]; then
        echo "0"
        return
    fi
    
    # Получение времени последнего переключения
    local last_switch
    last_switch=$(get_killswitch_last_switch_timestamp)
    
    if [[ "$last_switch" == "never" ]]; then
        # Если переключений не было, считаем время с запуска системы
        local boot_time
        boot_time=$(uptime -s 2>/dev/null || echo "")
        if [[ -n "$boot_time" ]]; then
            local boot_timestamp
            boot_timestamp=$(date -d "$boot_time" +%s 2>/dev/null || echo "0")
            local current_timestamp
            current_timestamp=$(date +%s)
            echo $((current_timestamp - boot_timestamp))
        else
            echo "0"
        fi
    else
        # Время с последнего переключения
        local switch_timestamp
        switch_timestamp=$(date -d "$last_switch" +%s 2>/dev/null || echo "0")
        local current_timestamp
        current_timestamp=$(date +%s)
        echo $((current_timestamp - switch_timestamp))
    fi
}

# === ДОПОЛНИТЕЛЬНЫЕ МЕТРИКИ KILL-SWITCH ===

# Получение статистики исключений
get_killswitch_exceptions_stats() {
    local exceptions_json="{}"
    
    # Подсчет правил исключений в XRAY_DISABLED
    local cidr_exceptions=0
    local ip_exceptions=0
    local port_exceptions=0
    
    if iptables -t mangle -L XRAY_DISABLED -n 2>/dev/null | grep -q "RETURN"; then
        cidr_exceptions=$(iptables -t mangle -L XRAY_DISABLED -n 2>/dev/null | grep "RETURN" | grep -c "/" || echo "0")
        ip_exceptions=$(iptables -t mangle -L XRAY_DISABLED -n 2>/dev/null | grep "RETURN" | grep -c -v "/" || echo "0")
        port_exceptions=$(iptables -t mangle -L XRAY_DISABLED -n 2>/dev/null | grep "RETURN" | grep -c "dpt:" || echo "0")
    fi
    
    exceptions_json="{\"cidr_exceptions\":$cidr_exceptions,\"ip_exceptions\":$ip_exceptions,\"port_exceptions\":$port_exceptions}"
    
    echo "$exceptions_json"
}

# Получение статистики производительности
get_killswitch_performance_stats() {
    local perf_json="{}"
    
    # Время переключения (примерное)
    local switch_time_ms=0
    # Это можно измерить, запустив переключение и замерив время
    # Пока возвращаем 0
    switch_time_ms=0
    
    # Частота переключений в час
    local switches_per_hour=0
    local switches_24h
    switches_24h=$(get_killswitch_auto_switches_count)
    switches_per_hour=$((switches_24h / 24))
    
    perf_json="{\"switch_time_ms\":$switch_time_ms,\"switches_per_hour\":$switches_per_hour}"
    
    echo "$perf_json"
}

# === ЭКСПОРТ ФУНКЦИЙ ===
export -f collect_killswitch_metrics
export -f get_killswitch_mode is_killswitch_auto_switching get_killswitch_auto_switches_count
export -f get_killswitch_last_switch_timestamp get_killswitch_chains_status
export -f get_killswitch_blocking_stats get_killswitch_watchdog_status
export -f get_killswitch_current_mode_uptime get_killswitch_exceptions_stats
export -f get_killswitch_performance_stats
