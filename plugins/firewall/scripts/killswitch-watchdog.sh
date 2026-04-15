#!/usr/bin/env bash

# === Xray Kill-Switch Watchdog ===
# Версия: 2.0.0
# Автор: Xray Gateway Installer Team
# Описание: Автоматический мониторинг статуса Xray и переключение kill-switch

# Глобальные переменные
declare -g SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -g FIREWALL_SCRIPT_PATH=""
declare -g LAN_IF=""
declare -g WAN_IF=""
declare -g LOG_FILE="/var/log/xray-killswitch-watchdog.log"
declare -g CHECK_INTERVAL=5
declare -g LAST_XRAY_STATUS=""
declare -g LAST_FIREWALL_MODE=""

# === Инициализация ===
watchdog_init() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Инициализация Kill-Switch Watchdog"
    
    # Загрузка конфигурации
    local xray_install_path
    xray_install_path="$(config_get_constant "xray_install_path" 2>/dev/null || echo "/opt/xray")"
    FIREWALL_SCRIPT_PATH="${xray_install_path}/iptables/xray-iptables.sh"
    
    # Определение интерфейсов
    LAN_IF="$(config_get_constant "network.lan_interface" 2>/dev/null || echo "eth0")"
    WAN_IF="$(config_get_constant "network.wan_interface" 2>/dev/null || echo "eth1")"
    
    # Проверка наличия скрипта файрвола
    if [[ ! -f "$FIREWALL_SCRIPT_PATH" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Скрипт файрвола не найден: $FIREWALL_SCRIPT_PATH"
        exit 1
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') [OK] Watchdog инициализирован"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] LAN интерфейс: $LAN_IF"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] WAN интерфейс: $WAN_IF"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Интервал проверки: ${CHECK_INTERVAL}с"
}

# === Проверка статуса Xray ===
check_xray_status() {
    if systemctl is-active --quiet xray; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

# === Проверка текущего режима файрвола ===
check_firewall_mode() {
    if iptables -t mangle -L PREROUTING -n | grep -q "XRAY_ENABLED"; then
        echo "enabled"
    elif iptables -t mangle -L PREROUTING -n | grep -q "XRAY_DISABLED"; then
        echo "disabled"
    else
        echo "unknown"
    fi
}

# === Переключение в активный режим ===
switch_to_enabled() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Переключение в активный режим"
    
    if [[ -f "$FIREWALL_SCRIPT_PATH" ]]; then
        "$FIREWALL_SCRIPT_PATH" enable
        if [[ $? -eq 0 ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') [OK] Переключение в активный режим завершено"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Ошибка переключения в активный режим"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Скрипт файрвола не найден"
    fi
}

# === Переключение в kill-switch режим ===
switch_to_disabled() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Переключение в kill-switch режим"
    
    if [[ -f "$FIREWALL_SCRIPT_PATH" ]]; then
        "$FIREWALL_SCRIPT_PATH" disable
        if [[ $? -eq 0 ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') [OK] Переключение в kill-switch режим завершено"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Ошибка переключения в kill-switch режим"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Скрипт файрвола не найден"
    fi
}

# === Логирование статуса ===
log_status() {
    local xray_status="$1"
    local firewall_mode="$2"
    
    if [[ "$xray_status" != "$LAST_XRAY_STATUS" ]] || [[ "$firewall_mode" != "$LAST_FIREWALL_MODE" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [STATUS] Xray: $xray_status, Firewall: $firewall_mode"
        LAST_XRAY_STATUS="$xray_status"
        LAST_FIREWALL_MODE="$firewall_mode"
    fi
}

# === Основной цикл мониторинга ===
watchdog_loop() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Запуск основного цикла мониторинга"
    
    while true; do
        local xray_status
        local firewall_mode
        
        xray_status=$(check_xray_status)
        firewall_mode=$(check_firewall_mode)
        
        # Логирование изменений статуса
        log_status "$xray_status" "$firewall_mode"
        
        # Принятие решений о переключении
        case "$xray_status" in
            "enabled")
                if [[ "$firewall_mode" != "enabled" ]]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') [ACTION] Xray активен, переключение в активный режим"
                    switch_to_enabled
                fi
                ;;
            "disabled")
                if [[ "$firewall_mode" != "disabled" ]]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') [ACTION] Xray остановлен, переключение в kill-switch режим"
                    switch_to_disabled
                fi
                ;;
            *)
                echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] Неизвестный статус Xray: $xray_status"
                ;;
        esac
        
        # Ожидание следующей проверки
        sleep "$CHECK_INTERVAL"
    done
}

# === Обработка сигналов ===
signal_handler() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Получен сигнал завершения, остановка watchdog"
    exit 0
}

# === Основная функция ===
main() {
    # Обработка сигналов
    trap signal_handler SIGTERM SIGINT
    
    # Инициализация
    watchdog_init
    
    # Запуск основного цикла
    watchdog_loop
}

# === Запуск ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
