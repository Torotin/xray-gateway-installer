#!/usr/bin/env bash

# =============================================================================
# System Metrics Collector
# =============================================================================
# Сборщик системных метрик для мониторинга Xray Gateway
# =============================================================================

# === СБОР СИСТЕМНЫХ МЕТРИК ===
collect_system_metrics() {
    local metrics="{}"
    
    # CPU использование
    local cpu_usage
    cpu_usage=$(get_cpu_usage)
    metrics=$(echo "$metrics" | jq --arg cpu "$cpu_usage" '.cpu_usage = ($cpu | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Использование памяти
    local memory_usage_mb
    memory_usage_mb=$(get_memory_usage_mb)
    metrics=$(echo "$metrics" | jq --arg mem "$memory_usage_mb" '.memory_usage_mb = ($mem | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Процент использования памяти
    local memory_usage_percent
    memory_usage_percent=$(get_memory_usage_percent)
    metrics=$(echo "$metrics" | jq --arg mem_pct "$memory_usage_percent" '.memory_usage_percent = ($mem_pct | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Использование диска
    local disk_usage_percent
    disk_usage_percent=$(get_disk_usage_percent)
    metrics=$(echo "$metrics" | jq --arg disk "$disk_usage_percent" '.disk_usage_percent = ($disk | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Свободное место на диске (MB)
    local disk_free_mb
    disk_free_mb=$(get_disk_free_mb)
    metrics=$(echo "$metrics" | jq --arg disk_free "$disk_free_mb" '.disk_free_mb = ($disk_free | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Загрузка системы
    local load_average
    load_average=$(get_load_average)
    metrics=$(echo "$metrics" | jq --arg load "$load_average" '.load_average = ($load | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Количество процессов
    local process_count
    process_count=$(get_process_count)
    metrics=$(echo "$metrics" | jq --arg procs "$process_count" '.process_count = ($procs | tonumber)' 2>/dev/null || echo "$metrics")
    
    # Время работы системы
    local uptime_seconds
    uptime_seconds=$(get_system_uptime_seconds)
    metrics=$(echo "$metrics" | jq --arg uptime "$uptime_seconds" '.uptime_seconds = ($uptime | tonumber)' 2>/dev/null || echo "$metrics")
    
    echo "$metrics"
}

# === CPU ИСПОЛЬЗОВАНИЕ ===
get_cpu_usage() {
    # Получение использования CPU через /proc/stat
    local cpu_data
    cpu_data=$(grep '^cpu ' /proc/stat 2>/dev/null || echo "cpu 0 0 0 0 0 0 0 0 0 0")
    
    # Парсинг данных CPU
    local user nice system idle iowait irq softirq steal guest guest_nice
    read -r cpu user nice system idle iowait irq softirq steal guest guest_nice <<< "$cpu_data"
    
    # Вычисление общего времени
    local total_time=$((user + nice + system + idle + iowait + irq + softirq + steal + guest + guest_nice))
    local idle_time=$((idle + iowait))
    
    # Вычисление процента использования
    if [[ $total_time -gt 0 ]]; then
        local usage_percent=$(( (total_time - idle_time) * 100 / total_time ))
        echo "$usage_percent"
    else
        echo "0"
    fi
}

# === ИСПОЛЬЗОВАНИЕ ПАМЯТИ (MB) ===
get_memory_usage_mb() {
    # Получение информации о памяти
    local mem_info
    mem_info=$(grep '^MemTotal:\|^MemAvailable:' /proc/meminfo 2>/dev/null || echo "MemTotal: 0 kB\nMemAvailable: 0 kB")
    
    local mem_total mem_available
    mem_total=$(echo "$mem_info" | grep '^MemTotal:' | awk '{print $2}')
    mem_available=$(echo "$mem_info" | grep '^MemAvailable:' | awk '{print $2}')
    
    # Вычисление использованной памяти в MB
    if [[ -n "$mem_total" && -n "$mem_available" ]]; then
        local mem_used=$(( (mem_total - mem_available) / 1024 ))
        echo "$mem_used"
    else
        echo "0"
    fi
}

# === ПРОЦЕНТ ИСПОЛЬЗОВАНИЯ ПАМЯТИ ===
get_memory_usage_percent() {
    local mem_info
    mem_info=$(grep '^MemTotal:\|^MemAvailable:' /proc/meminfo 2>/dev/null || echo "MemTotal: 0 kB\nMemAvailable: 0 kB")
    
    local mem_total mem_available
    mem_total=$(echo "$mem_info" | grep '^MemTotal:' | awk '{print $2}')
    mem_available=$(echo "$mem_info" | grep '^MemAvailable:' | awk '{print $2}')
    
    if [[ -n "$mem_total" && -n "$mem_available" && $mem_total -gt 0 ]]; then
        local mem_used=$((mem_total - mem_available))
        local usage_percent=$(( mem_used * 100 / mem_total ))
        echo "$usage_percent"
    else
        echo "0"
    fi
}

# === ПРОЦЕНТ ИСПОЛЬЗОВАНИЯ ДИСКА ===
get_disk_usage_percent() {
    # Получение использования диска для корневой файловой системы
    local disk_usage
    disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//' 2>/dev/null || echo "0")
    echo "$disk_usage"
}

# === СВОБОДНОЕ МЕСТО НА ДИСКЕ (MB) ===
get_disk_free_mb() {
    local disk_free
    disk_free=$(df / | awk 'NR==2 {print $4}' 2>/dev/null || echo "0")
    # Конвертация из KB в MB
    echo $((disk_free / 1024))
}

# === СРЕДНЯЯ ЗАГРУЗКА СИСТЕМЫ ===
get_load_average() {
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ' 2>/dev/null || echo "0")
    echo "$load_avg"
}

# === КОЛИЧЕСТВО ПРОЦЕССОВ ===
get_process_count() {
    local proc_count
    proc_count=$(ps aux | wc -l 2>/dev/null || echo "0")
    # Вычитаем заголовок
    echo $((proc_count - 1))
}

# === ВРЕМЯ РАБОТЫ СИСТЕМЫ (СЕКУНДЫ) ===
get_system_uptime_seconds() {
    local uptime_sec
    uptime_sec=$(cat /proc/uptime | awk '{print int($1)}' 2>/dev/null || echo "0")
    echo "$uptime_sec"
}

# === ЭКСПОРТ ФУНКЦИЙ ===
export -f collect_system_metrics
export -f get_cpu_usage get_memory_usage_mb get_memory_usage_percent
export -f get_disk_usage_percent get_disk_free_mb get_load_average
export -f get_process_count get_system_uptime_seconds
