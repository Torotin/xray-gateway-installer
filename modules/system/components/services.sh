#!/usr/bin/env bash

# === Компонент управления сервисами ===
# Версия: 2.2.0 (Рефакторинг)
# Автор: Xray Gateway Installer Team

# === Глобальные переменные компонента ===
declare -g CONFLICTING_SERVICES=(
    "NetworkManager"
    "systemd-networkd"
    "wicd"
    "connman"
    "ifplugd"
    "dhcpcd"
    "dhclient"
)

declare -g RESTORE_SERVICES=(
    "NetworkManager"
    "systemd-networkd"
    "systemd-resolved"
)

declare -g SERVICES_DISABLED=false

# === Инициализация компонента ===
services_init() {
    log INFO "Инициализация компонента управления сервисами"
    
    # Проверка доступности systemctl
    if ! command -v systemctl >/dev/null 2>&1; then
        log ERROR "systemctl не найден, управление сервисами недоступно"
        return 1
    fi
    
    # Проверка прав доступа
    if ! systemctl list-units >/dev/null 2>&1; then
        log WARN "Недостаточно прав для управления сервисами"
    fi
    
    log OK "Компонент управления сервисами инициализирован"
    return 0
}

# === Проверка наличия конфигурации сети ===
services_has_replacement_network_config() {
    # Проверка /etc/network/interfaces
    if [[ -f /etc/network/interfaces ]] && grep -Eq '^\s*(iface|auto)\s+' /etc/network/interfaces; then
        log DEBUG "Найдена конфигурация в /etc/network/interfaces"
        return 0
    fi
    
    # Проверка /etc/network/interfaces.d/
    if compgen -G "/etc/network/interfaces.d/*" >/dev/null 2>&1; then
        log DEBUG "Найдена конфигурация в /etc/network/interfaces.d/"
        return 0
    fi
    
    # Проверка Netplan
    if compgen -G "/etc/netplan/*.yaml" >/dev/null 2>&1; then
        log DEBUG "Найдена конфигурация Netplan"
        return 0
    fi
    
    # Проверка NetworkManager конфигураций
    if [[ -d /etc/NetworkManager/system-connections ]] && [[ -n "$(ls -A /etc/NetworkManager/system-connections 2>/dev/null)" ]]; then
        log DEBUG "Найдены конфигурации NetworkManager"
        return 0
    fi
    
    return 1
}

# === Проверка критичности сервиса ===
services_is_critical() {
    local service="$1"
    
    # Критичные сервисы, которые нельзя отключать
    local critical_services=(
        "systemd-resolved"
        "systemd-timesyncd"
        "systemd-logind"
        "dbus"
        "systemd-journald"
    )
    
    for critical in "${critical_services[@]}"; do
        if [[ "$service" == "$critical" ]]; then
            return 0
        fi
    done
    
    return 1
}

# === Отключение конфликтующих сервисов ===
services_disable_conflicting() {
    log INFO "Отключение конфликтующих системных сервисов"
    
    local disabled=()
    local skipped=()
    local errors=()
    
    for svc in "${CONFLICTING_SERVICES[@]}"; do
        # Проверка критичности сервиса
        if services_is_critical "$svc"; then
            log DEBUG "Пропуск критичного сервиса: $svc"
            continue
        fi
        
        # Проверка существования сервиса
        if ! systemctl list-unit-files | grep -q "^$svc.service"; then
            log DEBUG "Сервис $svc не установлен"
            continue
        fi
        
        # Проверка состояния сервиса
        if ! systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            log DEBUG "Сервис $svc уже отключен"
            continue
        fi
        
        # Специальная проверка для сетевых сервисов
        if [[ "$svc" == "NetworkManager" || "$svc" == "systemd-networkd" ]]; then
            if ! services_has_replacement_network_config; then
                log WARN "Пропуск отключения $svc: отсутствует альтернативная конфигурация сети"
                skipped+=("$svc")
                continue
            fi

            if [[ "$svc" == "systemd-networkd" ]] && compgen -G "/etc/netplan/*.yaml" >/dev/null 2>&1; then
                log WARN "Пропуск отключения $svc: netplan использует systemd-networkd на этом хосте"
                skipped+=("$svc")
                continue
            fi
        fi
        
        # Отключение сервиса
        if services_disable_service "$svc"; then
            log OK "Сервис $svc отключен"
            disabled+=("$svc")
        else
            log WARN "Ошибка отключения сервиса $svc"
            errors+=("$svc")
        fi
    done
    
    # Результаты
    if [[ ${#disabled[@]} -gt 0 ]]; then
        log OK "Отключены сервисы: ${disabled[*]}"
        SERVICES_DISABLED=true
    fi
    
    if [[ ${#skipped[@]} -gt 0 ]]; then
        log INFO "Пропущены сервисы: ${skipped[*]}"
    fi
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        log WARN "Ошибки при отключении: ${errors[*]}"
        return 1
    fi
    
    if [[ ${#disabled[@]} -eq 0 && ${#skipped[@]} -eq 0 ]]; then
        log INFO "Ни один сервис не нуждался в отключении"
    fi
    
    return 0
}

# === Отключение отдельного сервиса ===
services_disable_service() {
    local service="$1"
    
    # Остановка сервиса
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        if ! systemctl stop "$service" >/dev/null 2>&1; then
            log WARN "Ошибка остановки сервиса $service"
        fi
    fi
    
    # Отключение автозапуска
    if ! systemctl disable "$service" >/dev/null 2>&1; then
        log WARN "Ошибка отключения автозапуска сервиса $service"
        return 1
    fi
    
    return 0
}

# === Восстановление сервисов ===
services_restore() {
    log INFO "Восстановление сервисов"
    
    local restored=()
    local failed=()
    local skipped=()
    
    for service in "${RESTORE_SERVICES[@]}"; do
        # Проверка доступности сервиса
        if ! systemctl list-unit-files | grep -q "^$service.service"; then
            log DEBUG "Сервис $service не установлен"
            skipped+=("$service")
            continue
        fi
        
        # Восстановление сервиса
        if services_restore_service "$service"; then
            log OK "Сервис $service восстановлен"
            restored+=("$service")
        else
            log WARN "Ошибка восстановления сервиса $service"
            failed+=("$service")
        fi
    done
    
    # Результаты
    if [[ ${#restored[@]} -gt 0 ]]; then
        log OK "Восстановлены сервисы: ${restored[*]}"
    fi
    
    if [[ ${#skipped[@]} -gt 0 ]]; then
        log INFO "Пропущены сервисы: ${skipped[*]}"
    fi
    
    if [[ ${#failed[@]} -gt 0 ]]; then
        log WARN "Ошибки восстановления: ${failed[*]}"
    fi
    
    SERVICES_DISABLED=false
    return 0
}

# === Восстановление отдельного сервиса ===
services_restore_service() {
    local service="$1"
    
    # Включение автозапуска
    if ! systemctl enable "$service" >/dev/null 2>&1; then
        log WARN "Ошибка включения автозапуска сервиса $service"
        return 1
    fi
    
    # Запуск сервиса
    if ! systemctl start "$service" >/dev/null 2>&1; then
        log WARN "Ошибка запуска сервиса $service"
        return 1
    fi
    
    return 0
}

# === Статус сервисов ===
services_status() {
    echo "=== Статус сервисов ==="
    echo "Конфликтующие сервисы:"
    
    for service in "${CONFLICTING_SERVICES[@]}"; do
        if systemctl list-unit-files | grep -q "^$service.service"; then
            local status
            if systemctl is-enabled "$service" >/dev/null 2>&1; then
                status="включен"
            else
                status="отключен"
            fi
            
            local active
            if systemctl is-active "$service" >/dev/null 2>&1; then
                active="(активен)"
            else
                active="(неактивен)"
            fi
            
            echo "  $service: $status $active"
        else
            echo "  $service: не установлен"
        fi
    done
    
    echo
    echo "Сервисы для восстановления:"
    for service in "${RESTORE_SERVICES[@]}"; do
        if systemctl list-unit-files | grep -q "^$service.service"; then
            local status
            if systemctl is-enabled "$service" >/dev/null 2>&1; then
                status="включен"
            else
                status="отключен"
            fi
            echo "  $service: $status"
        else
            echo "  $service: не установлен"
        fi
    done
}

# === Валидация сервисов ===
services_validate() {
    log INFO "Валидация управления сервисами"
    
    local errors=0
    local warnings=0
    
    # Проверка systemctl
    if ! command -v systemctl >/dev/null 2>&1; then
        log ERROR "systemctl не найден"
        ((errors++))
    fi
    
    # Проверка прав доступа
    if ! systemctl list-units >/dev/null 2>&1; then
        log WARN "Недостаточно прав для управления сервисами"
        ((warnings++))
    fi
    
    # Проверка критичных сервисов
    local critical_services=("systemd-resolved" "dbus")
    for service in "${critical_services[@]}"; do
        if systemctl list-unit-files | grep -q "^$service.service"; then
            if ! systemctl is-enabled "$service" >/dev/null 2>&1; then
                log WARN "Критичный сервис $service отключен"
                ((warnings++))
            fi
        fi
    done
    
    if [[ $errors -gt 0 ]]; then
        log ERROR "Валидация завершена с $errors ошибками и $warnings предупреждениями"
        return 1
    elif [[ $warnings -gt 0 ]]; then
        log WARN "Валидация завершена с $warnings предупреждениями"
        return 0
    else
        log OK "Валидация завершена успешно"
        return 0
    fi
}

# === Получение информации о сервисах ===
services_info() {
    echo "=== Информация о сервисах ==="
    echo "Конфликтующие сервисы: ${CONFLICTING_SERVICES[*]}"
    echo "Сервисы для восстановления: ${RESTORE_SERVICES[*]}"
    echo "Сервисы отключены: $SERVICES_DISABLED"
    
    echo
    echo "Активные сетевые сервисы:"
    systemctl list-units --type=service --state=active | grep -E "(network|Network)" || echo "  не найдены"
}

# === Экспорт функций ===
export -f services_init services_has_replacement_network_config services_disable_conflicting
export -f services_restore services_status services_validate services_info
export -f services_is_critical services_disable_service services_restore_service

# Автоматическая инициализация при загрузке компонента
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Если скрипт запущен напрямую
    services_init "$@"
else
    # Если скрипт загружен как компонент
    services_init
fi
