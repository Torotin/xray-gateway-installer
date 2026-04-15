#!/usr/bin/env bash

# === Модуль системных настроек Xray Gateway Installer ===
# Версия: 2.2.0 (Рефакторинг)
# Автор: Xray Gateway Installer Team

# === Глобальные переменные модуля ===
declare -g SYSTEM_MODULE_VERSION="2.2.0"
declare -g SYSTEM_COMPONENTS_LOADED=false
declare -g SYSTEM_COMPONENTS_INITIALIZED=false

# === Инициализация модуля ===
module_system_init() {
    # Инициализация логирования для модуля
    module_logger_init "system" "_logs"
    
    log INFO "Инициализация модуля системных настроек v$SYSTEM_MODULE_VERSION"
    
    # Установка переменных если они не определены
    if [[ -z "${SCRIPT_DIR:-}" ]]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
        log INFO "Установлена переменная SCRIPT_DIR: $SCRIPT_DIR"
    fi
    
    # Инициализация конфигурации
    if ! config_init; then
        log ERROR "Ошибка инициализации конфигурации"
        return 1
    fi
    
    # Загрузка компонентов
    if ! load_system_components; then
        log ERROR "Ошибка загрузки компонентов системы"
        return 1
    fi
    
    # Инициализация компонентов
    if ! init_system_components; then
        log ERROR "Ошибка инициализации компонентов системы"
        return 1
    fi
    
    log OK "Модуль системных настроек инициализирован"
    return 0
}

# === Загрузка компонентов ===
load_system_components() {
    # Проверка переменной SCRIPT_DIR
    if [[ -z "${SCRIPT_DIR:-}" ]]; then
        log ERROR "Переменная SCRIPT_DIR не определена"
        return 1
    fi
    
    local components_dir="${SCRIPT_DIR}/modules/system/components"
    local loaded_count=0
    local failed_count=0
    
    # Проверка существования директории компонентов
    if [[ ! -d "$components_dir" ]]; then
        log ERROR "Директория компонентов не найдена: $components_dir"
        return 1
    fi
    
    log INFO "Загрузка компонентов системы из: $components_dir"
    
    # Динамическая загрузка всех .sh файлов в директории components
    for component_file in "${components_dir}"/*.sh; do
        if [[ -f "$component_file" ]]; then
            local component_name=$(basename "$component_file" .sh)
            log INFO "Загрузка компонента: $component_name"
            
            # Проверка синтаксиса перед загрузкой
            if bash -n "$component_file" 2>&1; then
                log DEBUG "Синтаксис компонента $component_name корректен"
                if source "$component_file"; then
                    log OK "Компонент $component_name загружен"
                    ((loaded_count++))
                else
                    log ERROR "Ошибка загрузки компонента $component_name"
                    ((failed_count++))
                fi
            else
                log ERROR "Синтаксическая ошибка в компоненте $component_name"
                ((failed_count++))
            fi
        fi
    done
    
    if [[ $failed_count -gt 0 ]]; then
        log WARN "Загружено компонентов: $loaded_count, ошибок: $failed_count"
        return 1
    else
        log OK "Компоненты системы загружены ($loaded_count компонентов)"
        SYSTEM_COMPONENTS_LOADED=true
        return 0
    fi
}

# === Инициализация компонентов ===
init_system_components() {
    if [[ "$SYSTEM_COMPONENTS_LOADED" != "true" ]]; then
        log ERROR "Компоненты не загружены, невозможно инициализировать"
        return 1
    fi
    
    local components_dir="${SCRIPT_DIR}/modules/system/components"
    local initialized_count=0
    local failed_count=0
    
    log INFO "Инициализация компонентов системы"
    
    # Динамическая инициализация компонентов
    for component_file in "${components_dir}"/*.sh; do
        if [[ -f "$component_file" ]]; then
            local component_name=$(basename "$component_file" .sh)
            local init_function="${component_name}_init"
            
            if declare -f "$init_function" >/dev/null 2>&1; then
                log DEBUG "Инициализация компонента: $component_name"
                if "$init_function"; then
                    log OK "Компонент $component_name инициализирован"
                    ((initialized_count++))
                else
                    log ERROR "Ошибка инициализации компонента $component_name"
                    ((failed_count++))
                fi
            else
                log DEBUG "Компонент $component_name не имеет функции инициализации"
            fi
        fi
    done
    
    if [[ $failed_count -gt 0 ]]; then
        log WARN "Инициализировано компонентов: $initialized_count, ошибок: $failed_count"
        return 1
    else
        log OK "Компоненты системы инициализированы ($initialized_count компонентов)"
        SYSTEM_COMPONENTS_INITIALIZED=true
        return 0
    fi
}

# === Выполнение модуля ===
module_system_execute() {
    local action="$1"
    shift
    local args=("$@")
    
    # Проверка инициализации
    if [[ "$SYSTEM_COMPONENTS_INITIALIZED" != "true" ]]; then
        log ERROR "Модуль не инициализирован"
        return 1
    fi
    
    case "$action" in
        "install")
            system_install "${args[@]}"
            ;;
        "uninstall")
            system_uninstall "${args[@]}"
            ;;
        "status")
            system_status "${args[@]}"
            ;;
        "validate")
            system_validate "${args[@]}"
            ;;
        *)
            log ERROR "Неизвестное действие для модуля system: $action"
            return 1
            ;;
    esac
}

# === Зависимости модуля ===
module_system_dependencies() {
    echo "network"
}

# === Информация о модуле ===
module_system_info() {
    echo "Модуль системных настроек v$SYSTEM_MODULE_VERSION"
    echo "  - Создание административного пользователя"
    echo "  - Настройка SSH-ключей и sudo-прав"
    echo "  - Отключение root-доступа"
    echo "  - Оптимизация GRUB и sysctl"
    echo "  - Управление сервисами"
    echo "  - Резервное копирование"
    echo "  - Валидация конфигурации"
}

# === Валидация системы ===
system_validate() {
    log SEP
    log TITLE "Валидация системных настроек"
    
    local errors=0
    local warnings=0
    
    # Проверка компонентов
    if [[ "$SYSTEM_COMPONENTS_LOADED" != "true" ]]; then
        log ERROR "Компоненты не загружены"
        ((errors++))
    fi
    
    if [[ "$SYSTEM_COMPONENTS_INITIALIZED" != "true" ]]; then
        log ERROR "Компоненты не инициализированы"
        ((errors++))
    fi
    
    # Проверка функций компонентов
    local required_functions=(
        "backups_create" "backups_restore" "backups_status"
        "grub_configure" "grub_restore" "grub_status"
        "services_disable_conflicting" "services_restore" "services_status"
        "sysctl_configure" "sysctl_restore" "sysctl_status"
        "users_create_admin" "users_restore" "users_status"
    )
    
    for func in "${required_functions[@]}"; do
        if ! declare -f "$func" >/dev/null 2>&1; then
            log ERROR "Функция $func не найдена"
            ((errors++))
        fi
    done
    
    # Проверка директорий
    if [[ ! -d "${SCRIPT_DIR}/backups/system" ]]; then
        log WARN "Директория резервных копий не создана"
        ((warnings++))
    fi
    
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

# === Установка системных настроек ===
system_install() {
    log SEP
    log TITLE "Установка системных настроек"
    
    # Валидация перед установкой
    if ! system_validate; then
        log ERROR "Валидация не пройдена, установка прервана"
        return 1
    fi
    
    # Создание резервных копий
    if ! backups_create; then
        log ERROR "Ошибка создания резервных копий"
        return 1
    fi
    
    # Обнаружение сетевых интерфейсов
    if declare -f interfaces_detect >/dev/null 2>&1; then
        if ! interfaces_detect; then
            log WARN "Ошибка обнаружения сетевых интерфейсов"
        fi
    fi
    
    # Интерактивные настройки (только в интерактивном режиме)
    if [[ -z "${NONINTERACTIVE:-}" ]]; then
        # Создание административного пользователя
        ask_and_execute "system" "create_admin_user" "Создать административного пользователя?" "true" "users_create_admin"
        
        # Отключение root-доступа
        ask_and_execute "system" "disable_root_login" "Отключить вход под root (рекомендуется)?" "true" "users_disable_root_login"
        
        # Оптимизация GRUB
        ask_and_execute "system" "optimize_grub" "Оптимизировать GRUB (рекомендуется)?" "true" "grub_configure"
        
        # Оптимизация sysctl
        ask_and_execute "system" "optimize_sysctl" "Оптимизировать sysctl (рекомендуется)?" "true" "sysctl_configure"
        
        # Отключение конфликтующих сервисов
        ask_and_execute "system" "disable_conflicting_services" "Отключить конфликтующие сервисы (рекомендуется)?" "true" "services_disable_conflicting"
        
        # Переименование сетевых интерфейсов
        ask_and_execute "system" "rename_interfaces" "Переименовать сетевые интерфейсы (рекомендуется)?" "true" "interfaces_rename"
    else
        log INFO "Неинтерактивный режим: применяем рекомендуемые настройки"
        
        # Автоматическая настройка sysctl
        if declare -f sysctl_configure >/dev/null 2>&1; then
            if sysctl_configure; then
                log OK "sysctl настроен автоматически"
            else
                log WARN "Ошибка автоматической настройки sysctl"
            fi
        fi
    fi
    
    log OK "Системные настройки установлены"
    return 0
}

# === Удаление системных настроек ===
system_uninstall() {
    log SEP
    log TITLE "Удаление системных настроек"
    
    local errors=0
    local restored_count=0
    
    # Восстановление пользователей
    if users_restore; then
        log OK "Пользователи восстановлены"
        restored_count=$((restored_count + 1))
    else
        log WARN "Ошибка восстановления пользователей"
        errors=$((errors + 1))
    fi
    
    # Восстановление GRUB
    if grub_restore; then
        log OK "GRUB восстановлен"
        restored_count=$((restored_count + 1))
    else
        log WARN "Ошибка восстановления GRUB"
        errors=$((errors + 1))
    fi
    
    # Восстановление sysctl
    if sysctl_restore; then
        log OK "Sysctl восстановлен"
        restored_count=$((restored_count + 1))
    else
        log WARN "Ошибка восстановления sysctl"
        errors=$((errors + 1))
    fi
    
    # Восстановление сервисов
    if services_restore; then
        log OK "Сервисы восстановлены"
        restored_count=$((restored_count + 1))
    else
        log WARN "Ошибка восстановления сервисов"
        errors=$((errors + 1))
    fi
    
    # Восстановление сетевых интерфейсов
    if declare -f interfaces_restore >/dev/null 2>&1; then
        if interfaces_restore; then
            log OK "Сетевые интерфейсы восстановлены"
            restored_count=$((restored_count + 1))
        else
            log WARN "Ошибка восстановления сетевых интерфейсов"
            errors=$((errors + 1))
        fi
    fi
    
    # Восстановление из резервных копий
    if backups_restore; then
        log OK "Резервные копии восстановлены"
        restored_count=$((restored_count + 1))
    else
        log WARN "Ошибка восстановления из резервных копий"
        errors=$((errors + 1))
    fi
    
    if [[ $errors -gt 0 ]]; then
        log WARN "Системные настройки удалены с $errors ошибками ($restored_count компонентов восстановлено)"
        # Не возвращаем ошибку для некритичных проблем
        return 0
    else
        log OK "Системные настройки удалены ($restored_count компонентов восстановлено)"
        return 0
    fi
}

# === Статус системных настроек ===
system_status() {
    log SEP
    log TITLE "Статус системных настроек"
    
    # Общая информация
    echo "Версия модуля: $SYSTEM_MODULE_VERSION"
    echo "Компоненты загружены: $SYSTEM_COMPONENTS_LOADED"
    echo "Компоненты инициализированы: $SYSTEM_COMPONENTS_INITIALIZED"
    echo
    
    # Статус пользователей
    users_status
    
    echo
    
    # Статус GRUB
    grub_status
    
    echo
    
    # Статус sysctl
    sysctl_status
    
    echo
    
    # Статус сервисов
    services_status
    
    echo
    
    # Статус резервных копий
    backups_status
}

# === Экспорт функций ===
export -f module_system_init module_system_execute module_system_dependencies module_system_info
export -f system_install system_uninstall system_status system_validate
export -f load_system_components init_system_components

# Автоматическая инициализация при загрузке модуля
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Если скрипт запущен напрямую
    module_system_init "$@"
else
    # Если скрипт загружен как модуль
    module_system_init
fi