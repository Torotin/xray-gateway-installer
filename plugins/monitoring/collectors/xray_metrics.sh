#!/usr/bin/env bash

# =============================================================================
# Xray Metrics Collector
# =============================================================================
# Сборщик метрик Xray сервиса для мониторинга
# =============================================================================

# === СБОР МЕТРИК XRAY ===
collect_xray_metrics() {
    local metrics="{}"
    
    # Статус сервиса
    local status
    status=$(get_xray_service_status)
    metrics=$(echo "$metrics" | jq --arg status "$status" '.status = $status' 2>/dev/null || echo "$metrics")
    
    # Время работы
    local uptime_seconds
    uptime_seconds=$(get_xray_uptime_seconds)
    metrics=$(echo "$metrics" | jq --arg uptime "$uptime_seconds" '.uptime_seconds = ($uptime | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Количество перезапусков
    local restart_count
    restart_count=$(get_xray_restart_count)
    metrics=$(echo "$metrics" | jq --arg restarts "$restart_count" '.restart_count = ($restarts | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Валидность конфигурации
    local config_valid
    config_valid=$(is_xray_config_valid)
    metrics=$(echo "$metrics" | jq --arg valid "$config_valid" '.config_valid = ($valid | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Использование CPU Xray процессом
    local cpu_usage
    cpu_usage=$(get_xray_cpu_usage)
    metrics=$(echo "$metrics" | jq --arg cpu "$cpu_usage" '.cpu_usage = ($cpu | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Использование памяти Xray процессом (MB)
    local memory_usage_mb
    memory_usage_mb=$(get_xray_memory_usage_mb)
    metrics=$(echo "$metrics" | jq --arg mem "$memory_usage_mb" '.memory_usage_mb = ($mem | tonumber)' 2>/dev/null || echo "$metrics")
    
    # PID процесса
    local pid
    pid=$(get_xray_pid)
    metrics=$(echo "$metrics" | jq --arg pid "$pid" '.pid = ($pid | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Версия Xray
    local version
    version=$(get_xray_version)
    metrics=$(echo "$metrics" | jq --arg version "$version" '.version = $version' 2>/dev/null || echo "$metrics")
    
    # Количество активных соединений
    local active_connections
    active_connections=$(get_xray_active_connections)
    metrics=$(echo "$metrics" | jq --arg conns "$active_connections" '.active_connections = ($conns | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Ошибки в логах за последний час
    local error_count
    error_count=$(get_xray_error_count)
    metrics=$(echo "$metrics" | jq --arg errors "$error_count" '.error_count = ($errors | tonumber)' 2>/dev/null || echo "$metrics")
    
    echo "$metrics"
}

# === СТАТУС СЕРВИСА XRAY ===
get_xray_service_status() {
    if systemctl is-active --quiet xray 2>/dev/null; then
        echo "running"
    elif systemctl is-failed --quiet xray 2>/dev/null; then
        echo "failed"
    else
        echo "stopped"
    fi
}

# === ВРЕМЯ РАБОТЫ XRAY (СЕКУНДЫ) ===
get_xray_uptime_seconds() {
    local pid
    pid=$(get_xray_pid)
    
    if [[ -n "$pid" && "$pid" != "0" ]]; then
        # Получение времени запуска процесса
        local start_time
        start_time=$(stat -c %Y /proc/"$pid" 2>/dev/null || echo "0")
        
        if [[ "$start_time" -gt 0 ]]; then
            local current_time
            current_time=$(date +%s)
            local uptime=$((current_time - start_time))
            echo "$uptime"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

# === КОЛИЧЕСТВО ПЕРЕЗАПУСКОВ XRAY ===
get_xray_restart_count() {
    # Получение количества перезапусков из systemd
    local restart_count
    restart_count=$(systemctl show xray --property=NActiveEnterTimestamp --value 2>/dev/null | wc -l)
    echo "$restart_count"
}

# === ВАЛИДНОСТЬ КОНФИГУРАЦИИ XRAY ===
is_xray_config_valid() {
    # Проверка конфигурации Xray
    local config_dir="/opt/xray/configs"
    local config_files=()
    
    # Поиск конфигурационных файлов
    if [[ -d "$config_dir" ]]; then
        while IFS= read -r -d '' file; do
            config_files+=("$file")
        done < <(find "$config_dir" -name "*.json" -print0 2>/dev/null)
    fi
    
    # Проверка каждого файла конфигурации
    for config_file in "${config_files[@]}"; do
        if ! jq empty "$config_file" 2>/dev/null; then
            echo "0"
            return
        fi
    done
    
    # Если есть хотя бы один валидный файл конфигурации
    if [[ ${#config_files[@]} -gt 0 ]]; then
        echo "1"
    else
        echo "0"
    fi
}

# === ИСПОЛЬЗОВАНИЕ CPU XRAY ПРОЦЕССОМ ===
get_xray_cpu_usage() {
    local pid
    pid=$(get_xray_pid)
    
    if [[ -n "$pid" && "$pid" != "0" ]]; then
        # Получение использования CPU через ps
        local cpu_usage
        cpu_usage=$(ps -p "$pid" -o %cpu --no-headers 2>/dev/null | tr -d ' ' || echo "0")
        echo "$cpu_usage"
    else
        echo "0"
    fi
}

# === ИСПОЛЬЗОВАНИЕ ПАМЯТИ XRAY ПРОЦЕССОМ (MB) ===
get_xray_memory_usage_mb() {
    local pid
    pid=$(get_xray_pid)
    
    if [[ -n "$pid" && "$pid" != "0" ]]; then
        # Получение использования памяти через ps
        local memory_kb
        memory_kb=$(ps -p "$pid" -o rss --no-headers 2>/dev/null | tr -d ' ' || echo "0")
        # Конвертация из KB в MB
        echo $((memory_kb / 1024))
    else
        echo "0"
    fi
}

# === PID XRAY ПРОЦЕССА ===
get_xray_pid() {
    local pid
    pid=$(pgrep -f "xray" 2>/dev/null | head -1 || echo "")
    echo "${pid:-0}"
}

# === ВЕРСИЯ XRAY ===
get_xray_version() {
    local version
    version=$(xray version 2>/dev/null | head -1 | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown")
    echo "$version"
}

# === АКТИВНЫЕ СОЕДИНЕНИЯ XRAY ===
get_xray_active_connections() {
    local pid
    pid=$(get_xray_pid)
    
    if [[ -n "$pid" && "$pid" != "0" ]]; then
        # Подсчет активных TCP соединений
        local tcp_connections
        tcp_connections=$(lsof -p "$pid" -i tcp 2>/dev/null | wc -l || echo "0")
        echo $((tcp_connections - 1))  # Вычитаем заголовок
    else
        echo "0"
    fi
}

# === КОЛИЧЕСТВО ОШИБОК В ЛОГАХ ===
get_xray_error_count() {
    # Подсчет ошибок в логах за последний час
    local error_count
    error_count=$(journalctl -u xray --since "1 hour ago" --no-pager | grep -i "error\|failed\|fatal" | wc -l 2>/dev/null || echo "0")
    echo "$error_count"
}

# === ДОПОЛНИТЕЛЬНЫЕ МЕТРИКИ ===

# Получение статистики сетевых интерфейсов Xray
get_xray_network_stats() {
    local pid
    pid=$(get_xray_pid)
    
    if [[ -n "$pid" && "$pid" != "0" ]]; then
        # Получение статистики сетевых соединений
        local net_stats
        net_stats=$(cat /proc/"$pid"/net/dev 2>/dev/null | grep -E "eth[01]|ens[0-9]+" | awk '{print $2, $10}' | head -2)
        echo "$net_stats"
    else
        echo "0 0"
    fi
}

# Получение информации о портах, которые слушает Xray
get_xray_listening_ports() {
    local pid
    pid=$(get_xray_pid)
    
    if [[ -n "$pid" && "$pid" != "0" ]]; then
        local ports
        ports=$(lsof -p "$pid" -i -P 2>/dev/null | grep LISTEN | awk '{print $9}' | cut -d: -f2 | sort -u | tr '\n' ',' | sed 's/,$//')
        echo "${ports:-none}"
    else
        echo "none"
    fi
}

# === ЭКСПОРТ ФУНКЦИЙ ===
export -f collect_xray_metrics
export -f get_xray_service_status get_xray_uptime_seconds get_xray_restart_count
export -f is_xray_config_valid get_xray_cpu_usage get_xray_memory_usage_mb
export -f get_xray_pid get_xray_version get_xray_active_connections
export -f get_xray_error_count get_xray_network_stats get_xray_listening_ports
