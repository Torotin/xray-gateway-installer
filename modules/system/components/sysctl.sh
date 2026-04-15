#!/usr/bin/env bash

# === Компонент настроек sysctl ===
# Версия: 2.2.0 (Рефакторинг)
# Автор: Xray Gateway Installer Team

# === Глобальные переменные компонента ===
declare -g SYSCTL_FILE="/etc/sysctl.d/99-xray-gateway.conf"
declare -g SYSCTL_OPTIMIZATION_ENABLED=false
declare -g IPV6_DISABLED=false

# === Инициализация компонента ===
sysctl_init() {
    log INFO "Инициализация компонента настроек sysctl"
    
    # Проверка доступности sysctl
    if ! command -v sysctl >/dev/null 2>&1; then
        log ERROR "sysctl не найден, управление параметрами ядра недоступно"
        return 1
    fi
    
    # Проверка прав доступа
    if ! sysctl -a >/dev/null 2>&1; then
        log WARN "Недостаточно прав для управления параметрами ядра"
    fi
    
    # Проверка текущего состояния оптимизации
    if sysctl_is_optimized; then
        SYSCTL_OPTIMIZATION_ENABLED=true
        log DEBUG "Sysctl уже оптимизирован"
    fi
    
    # Проверка состояния IPv6
    if sysctl_is_ipv6_disabled; then
        IPV6_DISABLED=true
        log DEBUG "IPv6 уже отключен"
    fi
    
    log OK "Компонент настроек sysctl инициализирован"
    return 0
}

# === Настройка sysctl ===
sysctl_configure() {
    log INFO "Настройка параметров sysctl для оптимизации сети"
    
    # Проверка существования директории
    if [[ ! -d "/etc/sysctl.d" ]]; then
        log ERROR "Директория /etc/sysctl.d не найдена"
        return 1
    fi
    
    # Создание резервной копии
    if ! sysctl_create_backup; then
        log ERROR "Ошибка создания резервной копии sysctl"
        return 1
    fi
    
    # Создание конфигурации
    if ! sysctl_create_config; then
        log ERROR "Ошибка создания конфигурации sysctl"
        return 1
    fi
    
    # Применение параметров
    if ! sysctl_apply_parameters; then
        log WARN "Ошибка применения некоторых параметров sysctl"
    fi
    
    # Принудительное отключение IPv6
    if ! sysctl_force_disable_ipv6; then
        log WARN "Ошибка отключения IPv6"
    fi
    
    SYSCTL_OPTIMIZATION_ENABLED=true
    IPV6_DISABLED=true
    log OK "Настройка sysctl завершена"
    return 0
}

# === Создание резервной копии sysctl ===
sysctl_create_backup() {
    local sysctl_backup="${SYSCTL_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$SYSCTL_FILE" ]]; then
        if cp -a "$SYSCTL_FILE" "$sysctl_backup"; then
            log OK "Создана резервная копия sysctl: $sysctl_backup"
            return 0
        else
            log ERROR "Ошибка создания резервной копии sysctl"
            return 1
        fi
    fi
    
    return 0
}

# === Создание конфигурации sysctl ===
sysctl_create_config() {
    log INFO "Создание конфигурации sysctl"
    
    # Создание файла конфигурации из template
    local template_file="${SCRIPT_DIR}/templates/sysctl.conf.template"
    if [[ -f "$template_file" ]]; then
        # Замена плейсхолдеров в template
        sed -e "s/{{CREATION_DATE}}/$(date)/g" \
            -e "s|{{SYSCTL_FILE_PATH}}|$SYSCTL_FILE|g" \
            "$template_file" > "$SYSCTL_FILE"
        log OK "Создан файл конфигурации sysctl из template: $SYSCTL_FILE"
    else
        log ERROR "Template файл не найден: $template_file"
        return 1
    fi
    
    if [[ -f "$SYSCTL_FILE" ]]; then
        log OK "Создан файл конфигурации sysctl: $SYSCTL_FILE"
        return 0
    else
        log ERROR "Ошибка создания файла конфигурации sysctl"
        return 1
    fi
}

# === Применение параметров sysctl ===
sysctl_apply_parameters() {
    log INFO "Применение параметров sysctl"
    
    # Проверка валидности конфигурации
    if ! sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1; then
        log WARN "Валидация sysctl показала предупреждения"
    fi
    
    # Применение всех параметров
    if sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1; then
        log OK "Все параметры sysctl применены"
        return 0
    else
        # Применение параметров по одному
        log INFO "Применение параметров sysctl по одному"
        sysctl_apply_parameters_individually
        return $?
    fi
}

# === Применение параметров по одному ===
sysctl_apply_parameters_individually() {
    local applied_count=0
    local failed_count=0
    local failed_params=()
    
    while IFS='=' read -r param value; do
        # Пропускаем комментарии и пустые строки
        [[ "$param" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$param" ]] && continue
        
        # Убираем пробелы
        param="$(echo "$param" | xargs)"
        value="$(echo "$value" | xargs)"
        
        if [[ -n "$param" && -n "$value" ]]; then
            if sysctl -w "$param=$value" >/dev/null 2>&1; then
                log DEBUG "Применён параметр: $param=$value"
                ((applied_count++))
            else
                log DEBUG "Не удалось применить параметр: $param=$value"
                failed_params+=("$param")
                ((failed_count++))
            fi
        fi
    done < "$SYSCTL_FILE"
    
    if [[ ${#failed_params[@]} -eq 0 ]]; then
        log OK "Все параметры sysctl применены успешно ($applied_count параметров)"
        return 0
    else
        log WARN "Не удалось применить некоторые параметры sysctl: ${failed_params[*]}"
        log INFO "Применено параметров: $applied_count, ошибок: $failed_count"
        return 1
    fi
}

# === Принудительное отключение IPv6 ===
sysctl_force_disable_ipv6() {
    log INFO "Принудительное отключение IPv6"
    
    # Отключение IPv6 модулей ядра
    local ipv6_modules=("ipv6" "ip6_tables" "ip6table_filter" "ip6table_mangle" "ip6table_raw" "ip6table_security")
    local disabled_modules=0
    
    local kernel_module
    for kernel_module in "${ipv6_modules[@]}"; do
        if lsmod | grep -q "^$kernel_module "; then
            if modprobe -r "$kernel_module" 2>/dev/null; then
                log OK "Модуль $kernel_module отключён"
                ((disabled_modules++))
            else
                log WARN "Не удалось отключить модуль $kernel_module"
            fi
        else
            log DEBUG "Модуль $kernel_module уже отключён"
        fi
    done
    
    # Принудительное отключение IPv6 через sysctl
    local ipv6_params=(
        "net.ipv6.conf.all.disable_ipv6=1"
        "net.ipv6.conf.default.disable_ipv6=1"
        "net.ipv6.conf.lo.disable_ipv6=1"
        "net.ipv6.conf.all.autoconf=0"
        "net.ipv6.conf.default.autoconf=0"
        "net.ipv6.conf.all.accept_ra=0"
        "net.ipv6.conf.default.accept_ra=0"
    )
    
    local applied_params=0
    for param in "${ipv6_params[@]}"; do
        if sysctl -w "$param" >/dev/null 2>&1; then
            log DEBUG "Применён IPv6 параметр: $param"
            ((applied_params++))
        else
            log DEBUG "IPv6 параметр недоступен: $param"
        fi
    done
    
    # Проверка результата
    if sysctl_is_ipv6_disabled; then
        log OK "IPv6 успешно отключён (модулей: $disabled_modules, параметров: $applied_params)"
        return 0
    else
        log WARN "IPv6 может быть не полностью отключён (требуется перезагрузка)"
        return 1
    fi
}

# === Проверка оптимизации sysctl ===
sysctl_is_optimized() {
    if [[ ! -f "$SYSCTL_FILE" ]]; then
        return 1
    fi
    
    # Проверяем наличие ключевых параметров оптимизации
    local optimization_params=(
        "net.core.default_qdisc = fq"
        "net.ipv4.tcp_congestion_control = bbr"
        "net.ipv4.ip_forward = 1"
    )
    
    for param in "${optimization_params[@]}"; do
        if ! grep -q "$param" "$SYSCTL_FILE"; then
            return 1
        fi
    done
    
    return 0
}

# === Проверка отключения IPv6 ===
sysctl_is_ipv6_disabled() {
    if [[ -f "/proc/sys/net/ipv6/conf/all/disable_ipv6" ]]; then
        if [[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo "0")" == "1" ]]; then
            return 0
        fi
    fi
    
    return 1
}

# === Восстановление sysctl ===
sysctl_restore() {
    log INFO "Восстановление настроек sysctl"
    
    # Удаление конфигурации sysctl
    if [[ -f "$SYSCTL_FILE" ]]; then
        if rm -f "$SYSCTL_FILE"; then
            log OK "Удален файл sysctl: $SYSCTL_FILE"
        else
            log WARN "Ошибка удаления файла sysctl"
        fi
    fi
    
    # Восстановление из резервной копии
        local latest_sysctl_backup
    latest_sysctl_backup="$(find /etc/sysctl.d -name "99-xray-gateway.conf.backup.*" -type f 2>/dev/null | sort | tail -n1)"
    
    if [[ -n "$latest_sysctl_backup" && -f "$latest_sysctl_backup" ]]; then
        log INFO "Восстановление sysctl из: $latest_sysctl_backup"
        
        if cp -a "$latest_sysctl_backup" "$SYSCTL_FILE"; then
            log OK "Восстановлен sysctl из: $latest_sysctl_backup"
            
            # Применение восстановленных параметров
            if sysctl_apply_parameters; then
                log OK "Параметры sysctl восстановлены"
            else
                log WARN "Ошибка применения восстановленных параметров sysctl"
            fi
        else
            log ERROR "Ошибка восстановления sysctl"
            return 1
        fi
    else
        log INFO "Резервная копия sysctl не найдена, пропуск восстановления"
    fi
    
    SYSCTL_OPTIMIZATION_ENABLED=false
    IPV6_DISABLED=false
    log OK "Восстановление sysctl завершено"
    return 0
}

# === Статус sysctl ===
sysctl_status() {
    echo "=== Статус sysctl ==="
    echo "Оптимизация: $(sysctl_is_optimized && echo "применена" || echo "не применена")"
    echo "IPv6: $(sysctl_is_ipv6_disabled && echo "отключен" || echo "включен")"
    
    if [[ -f "$SYSCTL_FILE" ]]; then
        local param_count
        param_count="$(grep -c '^[^#]' "$SYSCTL_FILE" 2>/dev/null || echo "0")"
        echo "Параметров в конфигурации: $param_count"
    else
        echo "Файл конфигурации: не найден"
    fi
    
    # Информация о резервных копиях
    local backup_count
    backup_count="$(find /etc/sysctl.d -name "99-xray-gateway.conf.backup.*" -type f 2>/dev/null | wc -l)"
    echo "Резервных копий: $backup_count"
}

# === Валидация sysctl ===
sysctl_validate() {
    log INFO "Валидация настроек sysctl"
    
    local errors=0
    local warnings=0
    
    # Проверка доступности sysctl
    if ! command -v sysctl >/dev/null 2>&1; then
        log ERROR "sysctl не найден"
        ((errors++))
    fi
    
    # Проверка прав доступа
    if ! sysctl -a >/dev/null 2>&1; then
        log WARN "Недостаточно прав для управления параметрами ядра"
        ((warnings++))
    fi
    
    # Проверка файла конфигурации
    if [[ -f "$SYSCTL_FILE" ]]; then
        if ! sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1; then
            log WARN "Проблемы с валидностью файла конфигурации sysctl"
            ((warnings++))
        fi
    fi
    
    if [[ $errors -gt 0 ]]; then
        log ERROR "Валидация sysctl завершена с $errors ошибками и $warnings предупреждениями"
        return 1
    elif [[ $warnings -gt 0 ]]; then
        log WARN "Валидация sysctl завершена с $warnings предупреждениями"
        return 0
    else
        log OK "Валидация sysctl завершена успешно"
        return 0
    fi
}

# === Получение информации о sysctl ===
sysctl_info() {
    echo "=== Информация о sysctl ==="
    echo "Файл конфигурации: $SYSCTL_FILE"
    echo "Оптимизация: $(sysctl_is_optimized && echo "включена" || echo "отключена")"
    echo "IPv6: $(sysctl_is_ipv6_disabled && echo "отключен" || echo "включен")"
    
    if [[ -f "$SYSCTL_FILE" ]]; then
        echo "Ключевые параметры:"
        grep -E "(net\.core\.default_qdisc|net\.ipv4\.tcp_congestion_control|net\.ipv4\.ip_forward)" "$SYSCTL_FILE" | sed 's/^/  /'
    fi
}

# === Экспорт функций ===
export -f sysctl_init sysctl_configure sysctl_restore sysctl_status sysctl_validate sysctl_info
export -f sysctl_create_backup sysctl_create_config sysctl_apply_parameters
export -f sysctl_apply_parameters_individually sysctl_force_disable_ipv6
export -f sysctl_is_optimized sysctl_is_ipv6_disabled

# Автоматическая инициализация при загрузке компонента
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Если скрипт запущен напрямую
    sysctl_init "$@"
else
    # Если скрипт загружен как компонент
    sysctl_init
fi
