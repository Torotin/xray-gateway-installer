#!/usr/bin/env bash

# =============================================================================
# Xray Gateway Installer - Monitoring Plugin
# =============================================================================
# Плагин мониторинга для отслеживания состояния Xray Gateway
# Включает: статус сервисов, сеть, kill-switch, базовые метрики
# =============================================================================

# Загрузка зависимостей
MONITORING_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Инициализация логгера
if [[ -f "$MONITORING_SCRIPT_DIR/core/02_logger.sh" ]]; then
    source "$MONITORING_SCRIPT_DIR/core/02_logger.sh"
    # НЕ инициализируем основной логгер, только загружаем функции
fi

# Инициализация конфигурации
if [[ -f "$MONITORING_SCRIPT_DIR/core/01_config_manager.sh" ]]; then
    source "$MONITORING_SCRIPT_DIR/core/01_config_manager.sh"
    config_init "$MONITORING_SCRIPT_DIR"
fi

# Инициализация утилит
if [[ -f "$MONITORING_SCRIPT_DIR/core/03_utils.sh" ]]; then
    source "$MONITORING_SCRIPT_DIR/core/03_utils.sh"
fi

# === КОНСТАНТЫ ===
declare -g MONITORING_PLUGIN_NAME="monitoring"
declare -g PLUGIN_VERSION="1.0.0"
declare -g PLUGIN_DESCRIPTION="Мониторинг состояния Xray Gateway"

# Пути к компонентам (динамическое определение)
declare -g PLUGIN_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
declare -g COLLECTORS_DIR="${PLUGIN_DIR}/collectors"
declare -g EXPORTERS_DIR="${PLUGIN_DIR}/exporters"
declare -g DASHBOARDS_DIR="${PLUGIN_DIR}/dashboards"

# Конфигурация мониторинга (динамическое определение)
declare -g XRAY_INSTALL_PATH="$(config_get_constant "xray_install_path" "/opt/xray")"
declare -g MONITORING_CONFIG_DIR="${XRAY_INSTALL_PATH}/monitoring"
declare -g METRICS_CACHE_FILE="${MONITORING_CONFIG_DIR}/metrics.cache"
declare -g ALERTS_LOG_FILE="${MONITORING_CONFIG_DIR}/alerts.log"

# === ИНИЦИАЛИЗАЦИЯ ПЛАГИНА ===
plugin_monitoring_init() {
    # Инициализация логирования для плагина
    plugin_logger_init "monitoring" "_logs" "append"
    
    log INFO "Инициализация плагина мониторинга"
    
    # Создание директорий
    mkdir -p "$MONITORING_CONFIG_DIR"
    mkdir -p "$(dirname "$METRICS_CACHE_FILE")"
    
    # Загрузка коллекторов
    load_collectors
    
    # Инициализация кэша метрик
    init_metrics_cache
    
    log OK "Плагин мониторинга инициализирован"
}

# === ЗАГРУЗКА КОЛЛЕКТОРОВ ===
load_collectors() {
    local collectors=(
        "system_metrics.sh"
        "xray_metrics.sh"
        "network_metrics.sh"
        "killswitch_metrics.sh"
    )
    
    for collector in "${collectors[@]}"; do
        local collector_path="${COLLECTORS_DIR}/${collector}"
        if [[ -f "$collector_path" ]]; then
            source "$collector_path"
            log DEBUG "Загружен коллектор: $collector"
        else
            log WARN "Коллектор не найден: $collector"
        fi
    done
}

# === ИНИЦИАЛИЗАЦИЯ КЭША МЕТРИК ===
init_metrics_cache() {
    if [[ ! -f "$METRICS_CACHE_FILE" ]]; then
        cat > "$METRICS_CACHE_FILE" << 'EOF'
{
    "timestamp": null,
    "system": {},
    "xray": {},
    "network": {},
    "killswitch": {}
}
EOF
    fi
}

# === ОСНОВНАЯ ФУНКЦИЯ ВЫПОЛНЕНИЯ ===
plugin_monitoring_execute() {
    local action="${1:-status}"
    shift
    
    case "$action" in
        "status")
            monitoring_status "$@"
            ;;
        "collect")
            monitoring_collect "$@"
            ;;
        "dashboard")
            monitoring_dashboard "$@"
            ;;
        "export")
            monitoring_export "$@"
            ;;
        "alerts")
            monitoring_alerts "$@"
            ;;
        "install")
            monitoring_install "$@"
            ;;
        "uninstall")
            monitoring_uninstall "$@"
            ;;
        *)
            log ERROR "Неизвестное действие: $action"
            return 1
            ;;
    esac
}

# === СТАТУС МОНИТОРИНГА ===
monitoring_status() {
    log INFO "Проверка статуса мониторинга"
    
    # Проверка компонентов
    local components=(
        "Коллекторы метрик"
        "Экспортеры данных"
        "Дашборды"
        "Кэш метрик"
    )
    
    local status_ok=true
    
    # Проверка коллекторов
    if [[ -d "$COLLECTORS_DIR" && $(ls "$COLLECTORS_DIR"/*.sh 2>/dev/null | wc -l) -gt 0 ]]; then
        log OK "Коллекторы метрик: $(ls "$COLLECTORS_DIR"/*.sh 2>/dev/null | wc -l) файлов"
    else
        log WARN "Коллекторы метрик: не найдены"
        status_ok=false
    fi
    
    # Проверка экспортеров
    if [[ -d "$EXPORTERS_DIR" && $(ls "$EXPORTERS_DIR"/*.sh 2>/dev/null | wc -l) -gt 0 ]]; then
        log OK "Экспортеры данных: $(ls "$EXPORTERS_DIR"/*.sh 2>/dev/null | wc -l) файлов"
    else
        log WARN "Экспортеры данных: не найдены"
        status_ok=false
    fi
    
    # Проверка дашбордов
    if [[ -d "$DASHBOARDS_DIR" && $(ls "$DASHBOARDS_DIR"/*.sh 2>/dev/null | wc -l) -gt 0 ]]; then
        log OK "Дашборды: $(ls "$DASHBOARDS_DIR"/*.sh 2>/dev/null | wc -l) файлов"
    else
        log WARN "Дашборды: не найдены"
        status_ok=false
    fi
    
    # Проверка кэша метрик
    if [[ -f "$METRICS_CACHE_FILE" ]]; then
        local cache_size=$(stat -c%s "$METRICS_CACHE_FILE" 2>/dev/null || echo "0")
        log OK "Кэш метрик: ${cache_size} байт"
    else
        log WARN "Кэш метрик: не найден"
        status_ok=false
    fi
    
    if [[ "$status_ok" == "true" ]]; then
        log OK "Мониторинг: готов к работе"
    else
        log WARN "Мониторинг: требует настройки"
    fi
}

# === СБОР МЕТРИК ===
monitoring_collect() {
    # Инициализация плагина если не была выполнена
    if [[ -z "${PLUGIN_LOG_FILE:-}" ]]; then
        plugin_monitoring_init
    fi
    
    log INFO "Сбор метрик мониторинга"
    
    local metrics_data="{}"
    
    # Сбор системных метрик
    if command -v collect_system_metrics >/dev/null 2>&1; then
        local system_metrics
        system_metrics=$(collect_system_metrics 2>/dev/null || echo "{}")
        metrics_data=$(echo "$metrics_data" | jq --argjson sys "$system_metrics" '.system = $sys' 2>/dev/null || echo "$metrics_data")
    fi
    
    # Сбор метрик Xray
    if command -v collect_xray_metrics >/dev/null 2>&1; then
        local xray_metrics
        xray_metrics=$(collect_xray_metrics 2>/dev/null || echo "{}")
        metrics_data=$(echo "$metrics_data" | jq --argjson xray "$xray_metrics" '.xray = $xray' 2>/dev/null || echo "$metrics_data")
    fi
    
    # Сбор сетевых метрик
    if command -v collect_network_metrics >/dev/null 2>&1; then
        local network_metrics
        network_metrics=$(collect_network_metrics 2>/dev/null || echo "{}")
        metrics_data=$(echo "$metrics_data" | jq --argjson net "$network_metrics" '.network = $net' 2>/dev/null || echo "$metrics_data")
    fi
    
    # Сбор метрик Kill-Switch
    if command -v collect_killswitch_metrics >/dev/null 2>&1; then
        local killswitch_metrics
        killswitch_metrics=$(collect_killswitch_metrics 2>/dev/null || echo "{}")
        metrics_data=$(echo "$metrics_data" | jq --argjson ks "$killswitch_metrics" '.killswitch = $ks' 2>/dev/null || echo "$metrics_data")
    fi
    
    # Добавление временной метки
    metrics_data=$(echo "$metrics_data" | jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.timestamp = $ts' 2>/dev/null || echo "$metrics_data")
    
    # Сохранение в кэш
    echo "$metrics_data" > "$METRICS_CACHE_FILE"
    
    log OK "Метрики собраны и сохранены"
}

# === ДАШБОРД ===
monitoring_dashboard() {
    local format="${1:-text}"
    
    case "$format" in
        "text"|"simple")
            show_text_dashboard
            ;;
        "json")
            show_json_dashboard
            ;;
        *)
            log ERROR "Неизвестный формат дашборда: $format"
            return 1
            ;;
    esac
}

# === ТЕКСТОВЫЙ ДАШБОРД ===
show_text_dashboard() {
    # Сбор актуальных метрик
    monitoring_collect >/dev/null 2>&1
    
    if [[ ! -f "$METRICS_CACHE_FILE" ]]; then
        log ERROR "Кэш метрик не найден"
        return 1
    fi
    
    local metrics
    metrics=$(cat "$METRICS_CACHE_FILE" 2>/dev/null || echo "{}")
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                           XRAY GATEWAY MONITORING                            ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Системные метрики
    local cpu_usage=$(echo "$metrics" | jq -r '.system.cpu_usage // "N/A"' 2>/dev/null)
    local memory_usage=$(echo "$metrics" | jq -r '.system.memory_usage_mb // "N/A"' 2>/dev/null)
    local disk_usage=$(echo "$metrics" | jq -r '.system.disk_usage_percent // "N/A"' 2>/dev/null)
    
    local system_info="CPU: ${cpu_usage}%, RAM: ${memory_usage}MB, Disk: ${disk_usage}%"
    local system_icon=$(get_status_icon "$cpu_usage" "$memory_usage")
    printf "System Status:     %s %s\n" "$system_icon" "$system_info"
    
    # Xray метрики
    local xray_status=$(echo "$metrics" | jq -r '.xray.status // "unknown"' 2>/dev/null)
    local xray_uptime=$(echo "$metrics" | jq -r '.xray.uptime_seconds // 0' 2>/dev/null)
    local xray_restarts=$(echo "$metrics" | jq -r '.xray.restart_count // 0' 2>/dev/null)
    
    local uptime_str=$(format_uptime "$xray_uptime")
    local status_icon=$(get_xray_status_icon "$xray_status")
    local xray_info="$xray_status (uptime: $uptime_str, restarts: $xray_restarts)"
    printf "Xray Service:      %s %s\n" "$status_icon" "$xray_info"
    
    # Kill-Switch метрики
    local ks_mode=$(echo "$metrics" | jq -r '.killswitch.mode // "unknown"' 2>/dev/null)
    local ks_switches=$(echo "$metrics" | jq -r '.killswitch.auto_switches_count // 0' 2>/dev/null)
    local ks_icon=$(get_killswitch_icon "$ks_mode")
    local ks_info="$ks_mode (auto-switches: $ks_switches)"
    printf "Kill-Switch:       %s %s\n" "$ks_icon" "$ks_info"
    
    # Сетевые метрики
    local rules_count=$(echo "$metrics" | jq -r '.network.iptables_rules_count // 0' 2>/dev/null)
    local blocked_packets=$(echo "$metrics" | jq -r '.network.blocked_packets_count // 0' 2>/dev/null)
    local traffic_rx=$(echo "$metrics" | jq -r '.network.traffic_rx_mbps // "N/A"' 2>/dev/null)
    local traffic_tx=$(echo "$metrics" | jq -r '.network.traffic_tx_mbps // "N/A"' 2>/dev/null)
    
    local traffic_info="RX: ${traffic_rx}MB/s, TX: ${traffic_tx}MB/s"
    printf "Network Traffic:   📊 %s\n" "$traffic_info"
    
    local blocked_info="$blocked_packets packets"
    printf "Blocked Traffic:   🚫 %s\n" "$blocked_info"
    
    local rules_info="$rules_count rules active"
    printf "iptables Rules:    📋 %s\n" "$rules_info"
    
    # Время последнего обновления
    local last_update=$(echo "$metrics" | jq -r '.timestamp // "N/A"' 2>/dev/null)
    local update_str=$(date -d "$last_update" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$last_update")
    printf "Last Update:       ⏰ %s\n" "$update_str"
    
    echo ""
}

# === JSON ДАШБОРД ===
show_json_dashboard() {
    if [[ ! -f "$METRICS_CACHE_FILE" ]]; then
        log ERROR "Кэш метрик не найден"
        return 1
    fi
    
    cat "$METRICS_CACHE_FILE"
}

# === ЭКСПОРТ ДАННЫХ ===
monitoring_export() {
    local format="${1:-json}"
    local output_file="${2:-}"
    
    # Сбор актуальных метрик
    monitoring_collect >/dev/null 2>&1
    
    case "$format" in
        "json")
            if [[ -n "$output_file" ]]; then
                cp "$METRICS_CACHE_FILE" "$output_file"
                log OK "Метрики экспортированы в $output_file"
            else
                cat "$METRICS_CACHE_FILE"
            fi
            ;;
        "prometheus")
            export_prometheus_metrics
            ;;
        *)
            log ERROR "Неподдерживаемый формат экспорта: $format"
            return 1
            ;;
    esac
}

# === ЭКСПОРТ PROMETHEUS МЕТРИК ===
export_prometheus_metrics() {
    if [[ ! -f "$METRICS_CACHE_FILE" ]]; then
        return 1
    fi
    
    local metrics
    metrics=$(cat "$METRICS_CACHE_FILE" 2>/dev/null || echo "{}")
    
    echo "# HELP xray_gateway_status Xray Gateway service status"
    echo "# TYPE xray_gateway_status gauge"
    local xray_status=$(echo "$metrics" | jq -r '.xray.status // "unknown"' 2>/dev/null)
    local status_value=0
    [[ "$xray_status" == "running" ]] && status_value=1
    echo "xray_gateway_status{service=\"xray\"} $status_value"
    
    echo "# HELP killswitch_mode Kill-Switch mode status"
    echo "# TYPE killswitch_mode gauge"
    local ks_mode=$(echo "$metrics" | jq -r '.killswitch.mode // "unknown"' 2>/dev/null)
    local ks_value=0
    [[ "$ks_mode" == "enabled" ]] && ks_value=1
    echo "killswitch_mode{mode=\"$ks_mode\"} $ks_value"
    
    echo "# HELP iptables_rules_count Total iptables rules count"
    echo "# TYPE iptables_rules_count gauge"
    local rules_count=$(echo "$metrics" | jq -r '.network.iptables_rules_count // 0' 2>/dev/null)
    echo "iptables_rules_count $rules_count"
    
    echo "# HELP blocked_packets_total Total blocked packets"
    echo "# TYPE blocked_packets_total counter"
    local blocked_packets=$(echo "$metrics" | jq -r '.network.blocked_packets_count // 0' 2>/dev/null)
    echo "blocked_packets_total{chain=\"XRAY_DISABLED\"} $blocked_packets"
}

# === АЛЕРТЫ ===
monitoring_alerts() {
    local action="${1:-check}"
    
    case "$action" in
        "check")
            check_alerts
            ;;
        "list")
            list_alerts
            ;;
        "clear")
            clear_alerts
            ;;
        *)
            log ERROR "Неизвестное действие алертов: $action"
            return 1
            ;;
    esac
}

# === ПРОВЕРКА АЛЕРТОВ ===
check_alerts() {
    log INFO "Проверка алертов мониторинга"
    
    local alerts=()
    
    # Проверка статуса Xray
    if ! systemctl is-active --quiet xray; then
        alerts+=("CRITICAL: Xray сервис неактивен")
    fi
    
    # Проверка Kill-Switch
    if ! iptables -t mangle -L XRAY_DISABLED >/dev/null 2>&1; then
        alerts+=("WARNING: Kill-Switch не настроен")
    fi
    
    # Проверка использования диска
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ "$disk_usage" -gt 90 ]]; then
        alerts+=("WARNING: Критическое использование диска: ${disk_usage}%")
    fi
    
    # Вывод алертов
    if [[ ${#alerts[@]} -eq 0 ]]; then
        log OK "Алерты не найдены"
    else
        for alert in "${alerts[@]}"; do
            log WARN "$alert"
        done
    fi
}

# === СПИСОК АЛЕРТОВ ===
list_alerts() {
    if [[ -f "$ALERTS_LOG_FILE" ]]; then
        tail -20 "$ALERTS_LOG_FILE"
    else
        echo "Файл алертов не найден"
    fi
}

# === ОЧИСТКА АЛЕРТОВ ===
clear_alerts() {
    if [[ -f "$ALERTS_LOG_FILE" ]]; then
        > "$ALERTS_LOG_FILE"
        log OK "Алерты очищены"
    else
        log INFO "Файл алертов не найден"
    fi
}

# === УСТАНОВКА ПЛАГИНА ===
monitoring_install() {
    # Инициализация плагина если не была выполнена
    # Проверяем PLUGIN_LOG_FILE вместо MONITORING_CONFIG_DIR
    if [[ -z "${PLUGIN_LOG_FILE:-}" ]]; then
        plugin_monitoring_init
    fi
    
    log INFO "Установка плагина мониторинга"
    
    # Очистка legacy cron-хвостов перед новой установкой
    setup_monitoring_cron

    # Создание systemd юнитов
    create_monitoring_units
    
    log OK "Плагин мониторинга установлен"
}

# === УДАЛЕНИЕ ПЛАГИНА ===
monitoring_uninstall() {
    log INFO "Удаление плагина мониторинга"
    
    # Остановка и удаление systemd юнитов
    systemctl stop xray-monitoring-collector 2>/dev/null || true
    systemctl disable xray-monitoring-collector 2>/dev/null || true
    systemctl stop xray-monitoring-collector.timer 2>/dev/null || true
    systemctl disable xray-monitoring-collector.timer 2>/dev/null || true
    rm -f /etc/systemd/system/xray-monitoring-collector.service
    rm -f /etc/systemd/system/xray-monitoring-collector.timer
    systemctl daemon-reload
    systemctl reset-failed xray-monitoring-collector.service xray-monitoring-collector.timer 2>/dev/null || true
    
    # Удаление cron задач
    remove_monitoring_cron_entries
    
    # Очистка конфигурации
    rm -rf "$MONITORING_CONFIG_DIR"
    
    log OK "Плагин мониторинга удален"
}

# === СОЗДАНИЕ SYSTEMD ЮНИТОВ ===
create_monitoring_units() {
    local installer_path
    installer_path="${MONITORING_SCRIPT_DIR:-${SCRIPT_DIR:-$(pwd)}}"

    # Юнит для сбора метрик
    cat > /etc/systemd/system/xray-monitoring-collector.service << EOF
[Unit]
Description=Xray Gateway Monitoring Collector
After=network.target xray.service

[Service]
Type=oneshot
ExecStart=${installer_path}/plugins/monitoring/monitoring.sh collect
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Таймер для периодического сбора
    cat > /etc/systemd/system/xray-monitoring-collector.timer << 'EOF'
[Unit]
Description=Run Xray Gateway Monitoring Collector every 30 seconds
Requires=xray-monitoring-collector.service

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable xray-monitoring-collector.timer
    systemctl start xray-monitoring-collector.timer
}

# === НАСТРОЙКА CRON ===
setup_monitoring_cron() {
    if ! command -v crontab >/dev/null 2>&1; then
        log WARN "crontab не найден, используется только systemd timer для мониторинга"
        return 0
    fi

    # Systemd timer является canonical-планировщиком мониторинга.
    # На install/uninstall здесь выполняется только cleanup legacy cron-записей.
    remove_monitoring_cron_entries
    log INFO "Legacy cron-записи мониторинга очищены; используется systemd timer"
}

remove_monitoring_cron_entries() {
    command -v crontab >/dev/null 2>&1 || return 0

    local current_crontab=""
    current_crontab="$(crontab -l 2>/dev/null || true)"

    local filtered_crontab=""
    filtered_crontab="$(printf '%s\n' "$current_crontab" | grep -v -E 'monitoring\.sh collect|xray-monitoring-collector' || true)"

    if [[ -z "${filtered_crontab//[[:space:]]/}" ]]; then
        crontab -r 2>/dev/null || true
    else
        printf '%s\n' "$filtered_crontab" | crontab -
    fi
}

# === ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ===

# Получение иконки статуса системы
get_status_icon() {
    local cpu="$1"
    local memory="$2"
    
    if [[ "$cpu" != "N/A" && "$memory" != "N/A" ]]; then
        if (( $(echo "$cpu" | cut -d. -f1) < 80 && $(echo "$memory" | cut -d. -f1) < 80 )); then
            echo "✅"
        else
            echo "⚠️"
        fi
    else
        echo "❓"
    fi
}

# Получение иконки статуса Xray
get_xray_status_icon() {
    local status="$1"
    case "$status" in
        "running") echo "✅" ;;
        "stopped") echo "❌" ;;
        "failed") echo "💥" ;;
        *) echo "❓" ;;
    esac
}

# Получение иконки Kill-Switch
get_killswitch_icon() {
    local mode="$1"
    case "$mode" in
        "enabled") echo "🔒" ;;
        "disabled") echo "🔓" ;;
        *) echo "❓" ;;
    esac
}

# Форматирование времени работы
format_uptime() {
    local seconds="$1"
    if [[ "$seconds" -gt 0 ]]; then
        local hours=$((seconds / 3600))
        local minutes=$(((seconds % 3600) / 60))
        local secs=$((seconds % 60))
        printf "%dh %dm %ds" "$hours" "$minutes" "$secs"
    else
        echo "0s"
    fi
}

# === ИНФОРМАЦИЯ О ПЛАГИНЕ ===
plugin_monitoring_info() {
    cat << EOF
Plugin: $PLUGIN_NAME
Version: $PLUGIN_VERSION
Description: $PLUGIN_DESCRIPTION

Actions:
  status     - Показать статус мониторинга
  collect    - Собрать метрики
  dashboard  - Показать дашборд (text|json)
  export     - Экспортировать данные (json|prometheus)
  alerts     - Проверить алерты
  install    - Установить плагин
  uninstall  - Удалить плагин

Examples:
  ./installer.sh monitoring status
  ./installer.sh monitoring dashboard
  ./installer.sh monitoring export json
  ./installer.sh monitoring alerts check
EOF
}

# === ЗАВИСИМОСТИ ===
plugin_monitoring_dependencies() {
    echo "jq systemctl iptables"
}

# === ЭКСПОРТ ФУНКЦИЙ ===
export -f plugin_monitoring_init plugin_monitoring_execute plugin_monitoring_info plugin_monitoring_dependencies
export -f monitoring_status monitoring_collect monitoring_dashboard monitoring_export monitoring_alerts
export -f monitoring_install monitoring_uninstall
export -f show_text_dashboard show_json_dashboard export_prometheus_metrics
export -f check_alerts list_alerts clear_alerts
export -f create_monitoring_units setup_monitoring_cron
export -f get_status_icon get_xray_status_icon get_killswitch_icon format_uptime

# === ОСНОВНАЯ ЛОГИКА ВЫПОЛНЕНИЯ ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Инициализация плагина
    plugin_monitoring_init
    
    # Выполнение команды
    plugin_monitoring_execute "$@"
fi
