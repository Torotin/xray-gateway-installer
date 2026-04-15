#!/usr/bin/env bash

# === Компонент настроек GRUB ===
# Версия: 2.2.0 (Рефакторинг)
# Автор: Xray Gateway Installer Team

# === Глобальные переменные компонента ===
declare -g GRUB_FILE="/etc/default/grub"
declare -g GRUB_BACKUP_DIR="/etc/default/grub.backup"
declare -g GRUB_OPTIMIZATION_ENABLED=false

# === Инициализация компонента ===
grub_init() {
    log INFO "Инициализация компонента настроек GRUB"
    
    # Проверка существования файла GRUB
    if [[ ! -f "$GRUB_FILE" ]]; then
        log WARN "Файл GRUB не найден: $GRUB_FILE"
        return 1
    fi
    
    # Проверка доступности утилит
    if ! command -v update-grub >/dev/null 2>&1; then
        log WARN "Утилита update-grub не найдена"
    fi
    
    # Проверка текущего состояния оптимизации
    if grub_is_optimized; then
        GRUB_OPTIMIZATION_ENABLED=true
        log DEBUG "GRUB уже оптимизирован"
    fi
    
    log OK "Компонент настроек GRUB инициализирован"
    return 0
}

# === Настройка GRUB ===
grub_configure() {
    log INFO "Настройка параметров GRUB для оптимизации производительности"
    
    # Проверка существования файла
    if [[ ! -f "$GRUB_FILE" ]]; then
        log ERROR "Файл GRUB не найден: $GRUB_FILE"
        return 1
    fi
    
    # Создание резервной копии
    if ! grub_create_backup; then
        log ERROR "Ошибка создания резервной копии GRUB"
        return 1
    fi
    
    # Применение оптимизаций
    if ! grub_apply_optimizations; then
        log ERROR "Ошибка применения оптимизаций GRUB"
        return 1
    fi
    
    # Обновление GRUB
    if ! grub_update; then
        log WARN "Ошибка обновления GRUB, но настройки применены"
    fi
    
    GRUB_OPTIMIZATION_ENABLED=true
    log OK "Настройка GRUB завершена"
    return 0
}

# === Создание резервной копии GRUB ===
grub_create_backup() {
    local grub_backup="${GRUB_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if cp -a "$GRUB_FILE" "$grub_backup"; then
        log OK "Создана резервная копия GRUB: $grub_backup"
        return 0
    else
        log ERROR "Ошибка создания резервной копии GRUB"
        return 1
    fi
}

# === Применение оптимизаций GRUB ===
grub_apply_optimizations() {
    # Параметры ядра для оптимизации
    local kernel_params=(
        "net.ifnames=0"
        "biosdevname=0"
        "mitigations=off"
        "transparent_hugepage=never"
        "ipv6.disable=1"
        "net.core.default_qdisc=fq"
        "net.ipv4.tcp_congestion_control=bbr"
        "quiet"
        "splash"
    )
    
    local params_string="${kernel_params[*]}"
    
    # Проверяем, есть ли уже параметры в GRUB_CMDLINE_LINUX_DEFAULT
    if grep -q "GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_FILE"; then
        # Обновляем существующую строку
        if sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$params_string\"|" "$GRUB_FILE"; then
            log OK "Обновлены параметры GRUB_CMDLINE_LINUX_DEFAULT"
        else
            log ERROR "Ошибка обновления параметров GRUB"
            return 1
        fi
    else
        # Добавляем новую строку
        if echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$params_string\"" >> "$GRUB_FILE"; then
            log OK "Добавлены параметры GRUB_CMDLINE_LINUX_DEFAULT"
        else
            log ERROR "Ошибка добавления параметров GRUB"
            return 1
        fi
    fi
    
    # Дополнительные настройки GRUB
    grub_apply_additional_settings
    
    return 0
}

# === Применение дополнительных настроек GRUB ===
grub_apply_additional_settings() {
    # Установка таймаута загрузки
    if ! grep -q "GRUB_TIMEOUT=" "$GRUB_FILE"; then
        echo "GRUB_TIMEOUT=5" >> "$GRUB_FILE"
        log DEBUG "Добавлен таймаут GRUB: 5 секунд"
    fi
    
    # Отключение графического меню если не установлено
    if ! grep -q "GRUB_TERMINAL=" "$GRUB_FILE"; then
        echo "GRUB_TERMINAL=console" >> "$GRUB_FILE"
        log DEBUG "Установлен текстовый режим GRUB"
    fi
    
    # Включение сохранения выбора по умолчанию
    if ! grep -q "GRUB_DEFAULT=" "$GRUB_FILE"; then
        echo "GRUB_DEFAULT=saved" >> "$GRUB_FILE"
        echo "GRUB_SAVEDEFAULT=true" >> "$GRUB_FILE"
        log DEBUG "Включено сохранение выбора GRUB"
    fi
}

# === Обновление GRUB ===
grub_update() {
    if command -v update-grub >/dev/null 2>&1; then
        log INFO "Обновление конфигурации GRUB"
        if update-grub >/dev/null 2>&1; then
            log OK "GRUB обновлен успешно"
            return 0
        else
            log WARN "Ошибка обновления GRUB (код возврата: $?)"
            return 1
        fi
    else
        log WARN "Команда update-grub не найдена"
        return 1
    fi
}

# === Восстановление GRUB ===
grub_restore() {
    log INFO "Восстановление настроек GRUB"
    
    # Поиск последней резервной копии
    local latest_grub_backup
    latest_grub_backup="$(find /etc/default -name "grub.backup.*" -type f 2>/dev/null | sort | tail -n1)"
    
    if [[ -z "$latest_grub_backup" || ! -f "$latest_grub_backup" ]]; then
        log INFO "Резервная копия GRUB не найдена, пропуск восстановления"
        return 0
    fi
    
    log INFO "Восстановление GRUB из: $latest_grub_backup"
    
    # Восстановление файла
    if cp -a "$latest_grub_backup" "$GRUB_FILE"; then
        log OK "Восстановлен GRUB из: $latest_grub_backup"
        
        # Обновление GRUB после восстановления
        if grub_update; then
            log OK "GRUB обновлен после восстановления"
        else
            log WARN "Ошибка обновления GRUB после восстановления"
        fi
        
        GRUB_OPTIMIZATION_ENABLED=false
        return 0
    else
        log ERROR "Ошибка восстановления GRUB"
        return 1
    fi
}

# === Проверка оптимизации GRUB ===
grub_is_optimized() {
    if [[ ! -f "$GRUB_FILE" ]]; then
        return 1
    fi
    
    # Проверяем наличие ключевых параметров оптимизации
    local optimization_params=(
        "net.ifnames=0"
        "mitigations=off"
        "transparent_hugepage=never"
    )
    
    for param in "${optimization_params[@]}"; do
        if ! grep -q "$param" "$GRUB_FILE"; then
            return 1
        fi
    done
    
    return 0
}

# === Статус GRUB ===
grub_status() {
    echo "GRUB оптимизация: $(grub_is_optimized && echo "применена" || echo "не применена")"
    
    if [[ -f "$GRUB_FILE" ]]; then
        local timeout
        timeout="$(grep "GRUB_TIMEOUT=" "$GRUB_FILE" | cut -d'=' -f2 || echo "не установлен")"
        echo "Таймаут GRUB: $timeout"
        
        local default
        default="$(grep "GRUB_DEFAULT=" "$GRUB_FILE" | cut -d'=' -f2 || echo "не установлен")"
        echo "По умолчанию: $default"
    else
        echo "Файл GRUB: не найден"
    fi
    
    # Информация о резервных копиях
    local backup_count
    backup_count="$(find /etc/default -name "grub.backup.*" -type f 2>/dev/null | wc -l)"
    echo "Резервные копии: $backup_count"
}

# === Валидация GRUB ===
grub_validate() {
    log INFO "Валидация настроек GRUB"
    
    local errors=0
    
    # Проверка существования файла
    if [[ ! -f "$GRUB_FILE" ]]; then
        log ERROR "Файл GRUB не найден: $GRUB_FILE"
        ((errors++))
    fi
    
    # Проверка синтаксиса файла
    if [[ -f "$GRUB_FILE" ]]; then
        if ! bash -n "$GRUB_FILE" 2>/dev/null; then
            log WARN "Возможные проблемы с синтаксисом файла GRUB"
        fi
    fi
    
    # Проверка доступности update-grub
    if ! command -v update-grub >/dev/null 2>&1; then
        log WARN "Утилита update-grub недоступна"
    fi
    
    if [[ $errors -gt 0 ]]; then
        log ERROR "Валидация GRUB завершена с $errors ошибками"
        return 1
    else
        log OK "Валидация GRUB завершена успешно"
        return 0
    fi
}

# === Получение информации о GRUB ===
grub_info() {
    echo "=== Информация о GRUB ==="
    echo "Файл конфигурации: $GRUB_FILE"
    echo "Оптимизация: $(grub_is_optimized && echo "включена" || echo "отключена")"
    
    if [[ -f "$GRUB_FILE" ]]; then
        echo "Параметры ядра:"
        grep "GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_FILE" | sed 's/^/  /'
    fi
}

# === Экспорт функций ===
export -f grub_init grub_configure grub_restore grub_status grub_validate grub_info
export -f grub_create_backup grub_apply_optimizations grub_apply_additional_settings
export -f grub_update grub_is_optimized

# Автоматическая инициализация при загрузке компонента
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Если скрипт запущен напрямую
    grub_init "$@"
else
    # Если скрипт загружен как компонент
    grub_init
fi