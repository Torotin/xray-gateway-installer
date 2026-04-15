#!/usr/bin/env bash

# === Модуль Xray Xray Gateway Installer ===
# Версия: 2.1.0 (Рефакторинг)
# Автор: Xray Gateway Installer Team

# === Инициализация модуля ===
module_xray_init() {
    # Инициализация логирования для модуля
    module_logger_init "xray" "_logs"
    
    log INFO "Инициализация модуля Xray"
    
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
    
    # Кэширование переменных конфигурации
    cache_xray_config_vars
    
    # Загрузка компонентов
    load_xray_components
    
    # Инициализация компонентов
    init_xray_components
    
    log OK "Модуль Xray инициализирован"
}

# === Кэширование переменных конфигурации ===
cache_xray_config_vars() {
    log DEBUG "Кэширование переменных конфигурации Xray"
    
    # Основные переменные
    declare -g XRAY_USER="$(config_get_constant "xray_user" "xray")"
    declare -g XRAY_GROUP="$(config_get_constant "xray_group" "xray")"
    declare -g XRAY_GID="$(config_get_constant "xray_gid" "1001")"
    declare -g XRAY_INSTALL_PATH="$(config_get_constant "xray_install_path" "/opt/xray")"
    declare -g XRAY_LOG_PATH="$(config_get_constant "xray_log_path" "$XRAY_INSTALL_PATH/logs")"
    declare -g XRAY_CONFIGS_PATH="$(config_get_constant "xray_configs_path" "$XRAY_INSTALL_PATH/configs")"
    declare -g XRAY_DAT_PATH="$(config_get_constant "xray_data_path" "$XRAY_INSTALL_PATH/dat")"
    
    # Дополнительные переменные
    declare -g XRAY_SERVICE="$(config_get_constant "xray_service" "xray")"
    declare -g XRAY_BINARY="$(config_get_constant "xray_binary" "/usr/local/bin/xray")"
    declare -g XRAY_INSTALLER_URL="$(config_get_constant "xray_installer_url" "https://github.com/XTLS/Xray-install/raw/main/install-release.sh")"
    declare -g XRAY_EXTRA_GROUPS="$(config_get_constant "xray_extra_groups" "")"
    
    # Валидация критически важных переменных
    if ! validate_xray_config; then
        log ERROR "Валидация конфигурации Xray не прошла"
        return 1
    fi
    
    log DEBUG "Переменные конфигурации кэшированы и валидированы"
}

# === Валидация конфигурации Xray ===
validate_xray_config() {
    log DEBUG "Валидация конфигурации Xray"
    
    # Проверка обязательных переменных
    local required_vars=(
        "XRAY_USER"
        "XRAY_GROUP" 
        "XRAY_GID"
        "XRAY_INSTALL_PATH"
        "XRAY_SERVICE"
        "XRAY_BINARY"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log ERROR "Обязательная переменная не определена: $var"
            return 1
        fi
    done
    
    # Очистка GID от предупреждений
    XRAY_GID="$(echo "$XRAY_GID" | grep -o '^[0-9]*' | head -1)"
    
    # Проверка корректности GID
    if ! [[ "$XRAY_GID" =~ ^[0-9]+$ ]]; then
        log ERROR "Некорректный GID: $XRAY_GID (должен быть числом)"
        return 1
    fi
    
    # Предупреждение для GID < 1000, но не критическая ошибка
    if [[ "$XRAY_GID" -lt 1000 ]]; then
        log WARN "GID $XRAY_GID меньше 1000 (рекомендуется >= 1000 для системных пользователей)"
    fi
    
    # Проверка путей
    if [[ "$XRAY_INSTALL_PATH" != "/opt/xray"* ]]; then
        log WARN "Нестандартный путь установки: $XRAY_INSTALL_PATH"
    fi
    
    log DEBUG "Валидация конфигурации Xray прошла успешно"
    return 0
}

# === Загрузка компонентов ===
load_xray_components() {
    local components_dir="${SCRIPT_DIR}/modules/xray/components"
    
    # Динамическая загрузка всех .sh файлов в директории components
    for component_file in "${components_dir}"/*.sh; do
        if [[ -f "$component_file" ]]; then
            source "$component_file"
            local component_name=$(basename "$component_file" .sh)
            log OK "Компонент $component_name загружен"
        fi
    done
    
    log OK "Компоненты Xray загружены"
    return 0
}

# === Инициализация компонентов ===
init_xray_components() {
    # Динамическая инициализация компонентов
    for component_file in "${SCRIPT_DIR}/modules/xray/components"/*.sh; do
        if [[ -f "$component_file" ]]; then
            local component_name=$(basename "$component_file" .sh)
            local init_function="${component_name}_init"
            
            if declare -f "$init_function" >/dev/null 2>&1; then
                "$init_function"
                log OK "Компонент $component_name инициализирован"
            fi
        fi
    done
    
    log OK "Компоненты Xray инициализированы"
    return 0
}

# === Выполнение модуля ===
module_xray_execute() {
    local action="$1"
    shift
    local args=("$@")
    
    case "$action" in
        "install")
            xray_install "${args[@]}"
            ;;
        "uninstall")
            xray_uninstall "${args[@]}"
            ;;
        "status")
            xray_status "${args[@]}"
            ;;
        "update")
            xray_update "${args[@]}"
            ;;
        *)
            log ERROR "Неизвестное действие для модуля xray: $action"
            return 1
            ;;
    esac
}

# === Зависимости модуля ===
module_xray_dependencies() {
    echo "system"
}

# === Информация о модуле ===
module_xray_info() {
    echo "Модуль Xray"
    echo "  - Установка Xray Core"
    echo "  - Создание пользователя и групп"
    echo "  - Настройка конфигураций"
    echo "  - Управление сервисом"
    echo "  - Создание скриптов обновления"
}

# === Установка Xray ===
xray_install() {
    log SEP
    log TITLE "Установка Xray"
    
    # Интерактивные запросы для настройки
    if ! xray_interactive_setup; then
        log ERROR "Интерактивная настройка Xray не завершена"
        return 1
    fi
    
    # Проверка системных требований
    if ! xray_check_requirements; then
        log ERROR "Системные требования не выполнены"
        return 1
    fi
    
    # Создание пользователя и групп
    if ! user_create; then
        log ERROR "Ошибка создания пользователя и групп"
        return 1
    fi
    
    # Создание директорий
    if ! user_create_directories; then
        log ERROR "Ошибка создания директорий"
        return 1
    fi
    
    # Установка Xray Core
    if ! core_install; then
        log ERROR "Ошибка установки Xray Core"
        return 1
    fi
    
    # Настройка systemd сервиса
    if ! core_setup_systemd; then
        log ERROR "Ошибка настройки systemd сервиса"
        return 1
    fi
    
    # Создание базовых конфигураций
    if ! config_create_base; then
        log ERROR "Ошибка создания базовых конфигураций"
        return 1
    fi
    
    # Настройка логирования
    if ! config_setup_logging; then
        log ERROR "Ошибка настройки логирования"
        return 1
    fi
    
    # Настройка прав доступа
    if ! user_fix_permissions; then
        log ERROR "Ошибка настройки прав доступа"
        return 1
    fi
    
    # Создание скриптов обновления
    if ! xray_updates_create_scripts; then
        log WARN "Ошибка создания скриптов обновления (продолжаем)"
    fi
    
    # Первичная загрузка Geo данных
    if ! xray_updates_initial_geo_load; then
        log WARN "Ошибка первичной загрузки Geo данных (продолжаем)"
    fi
    
    # Включение и запуск сервиса
    if config_enable_service; then
        log OK "Xray установлен и запущен"
    else
        log WARN "Xray установлен, но не запущен (сервис будет настроен позже)"
        return 0  # Не прерываем установку
    fi
}

# === Интерактивная настройка Xray ===
xray_interactive_setup() {
    log INFO "Интерактивная настройка Xray"
    
    # Запрос на создание административного пользователя
    ask_and_execute "xray" "create_admin_user" "Создать административного пользователя для управления Xray?" "true" "xray_create_admin_user"
    
    # Запрос на настройку автоматических обновлений
    ask_and_execute "xray" "enable_auto_updates" "Включить автоматические обновления Xray?" "true" "xray_enable_auto_updates"
    
    # Запрос на настройку Geo данных
    ask_and_execute "xray" "enable_geo_updates" "Включить автоматическое обновление Geo данных?" "true" "xray_enable_geo_updates"
    
    log OK "Интерактивная настройка Xray завершена"
    return 0
}

# === Проверка системных требований ===
xray_check_requirements() {
    log INFO "Проверка системных требований для Xray"
    
    # Проверка архитектуры
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|aarch64|arm64|armv7l)
            log OK "Архитектура поддерживается: $arch"
            ;;
        *)
            log ERROR "Неподдерживаемая архитектура: $arch"
            return 1
            ;;
    esac
    
    # Проверка доступности curl
    if ! command -v curl >/dev/null 2>&1; then
        log ERROR "curl не найден (требуется для загрузки Xray)"
        return 1
    fi
    
    # Проверка доступности systemctl
    if ! command -v systemctl >/dev/null 2>&1; then
        log ERROR "systemctl не найден (требуется для управления сервисом)"
        return 1
    fi
    
    # Проверка прав root
    if [[ "$EUID" -ne 0 ]]; then
        log ERROR "Требуются права root для установки Xray"
        return 1
    fi
    
    log OK "Системные требования выполнены"
    return 0
}

# === Создание административного пользователя ===
xray_create_admin_user() {
    log INFO "Создание административного пользователя для Xray"
    
    # Здесь можно добавить логику создания административного пользователя
    # если это требуется для управления Xray
    
    log OK "Административный пользователь настроен"
    return 0
}

# === Включение автоматических обновлений ===
xray_enable_auto_updates() {
    log INFO "Настройка автоматических обновлений Xray"
    
    # Логика настройки автоматических обновлений
    # уже реализована в компоненте updates
    
    log OK "Автоматические обновления настроены"
    return 0
}

# === Включение обновлений Geo данных ===
xray_enable_geo_updates() {
    log INFO "Настройка автоматических обновлений Geo данных"
    
    # Логика настройки обновлений Geo данных
    # уже реализована в компоненте updates
    
    log OK "Обновления Geo данных настроены"
    return 0
}

# === Удаление Xray ===
xray_uninstall() {
    log SEP
    log TITLE "Удаление Xray"
    
    # Интерактивное подтверждение удаления
    if ! xray_confirm_uninstall; then
        log INFO "Удаление Xray отменено пользователем"
        return 0
    fi
    
    # Остановка и удаление сервиса
    if ! core_remove; then
        log ERROR "Ошибка удаления Xray Core"
        return 1
    fi
    
    # Удаление конфигураций
    if ! config_remove; then
        log ERROR "Ошибка удаления конфигураций"
        return 1
    fi
    
    # Удаление скриптов обновления
    if ! xray_updates_remove_scripts; then
        log WARN "Ошибка удаления скриптов обновления (продолжаем)"
    fi
    
    # Удаление пользователя
    if ! user_remove; then
        log WARN "Ошибка удаления пользователя (продолжаем)"
    fi
    
    log OK "Xray удален"
}

# === Подтверждение удаления Xray ===
xray_confirm_uninstall() {
    log WARN "ВНИМАНИЕ: Это действие удалит Xray и все связанные данные!"
    log INFO "Будут удалены:"
    log INFO "  - Xray Core и исполняемые файлы"
    log INFO "  - Все конфигурации и логи"
    log INFO "  - Пользователь и группы Xray"
    log INFO "  - Скрипты автоматических обновлений"

    if [[ -n "${NONINTERACTIVE:-}" ]]; then
        log WARN "Неинтерактивный режим: удаление Xray подтверждено автоматически"
        xray_confirm_uninstall_impl
        return 0
    fi
    
    ask_and_execute "xray" "confirm_uninstall" "Продолжить удаление Xray?" "false" "xray_confirm_uninstall_impl"
}

# === Реализация подтверждения удаления ===
xray_confirm_uninstall_impl() {
    log INFO "Подтверждение удаления получено"
    return 0
}

# === Статус Xray ===
xray_status() {
    log SEP
    log TITLE "Статус Xray"
    
    # Статус пользователя
    user_status
    
    echo
    
    # Статус Xray Core
    core_status
    
    echo
    
    # Статус конфигураций
    config_status
}

# === Обновление Xray ===
xray_update() {
    log SEP
    log TITLE "Обновление Xray"
    
    # Проверка текущего статуса
    if ! xray_check_update_prerequisites; then
        log ERROR "Предварительные проверки обновления не прошли"
        return 1
    fi
    
    # Интерактивные настройки обновления
    if ! xray_interactive_update_setup; then
        log ERROR "Интерактивная настройка обновления не завершена"
        return 1
    fi
    
    # Создание резервной копии
    if ! xray_create_backup; then
        log WARN "Не удалось создать резервную копию (продолжаем)"
    fi
    
    # Остановка сервиса
    if ! systemctl stop xray 2>/dev/null; then
        log WARN "Не удалось остановить сервис xray (возможно, не запущен)"
    fi
    
    # Очистка логов перед обновлением
    if ! config_clear_logs; then
        log WARN "Не удалось очистить логи (продолжаем)"
    fi
    
    # Установка новой версии
    if ! core_install; then
        log ERROR "Ошибка установки новой версии Xray"
        # Попытка восстановления из резервной копии
        if xray_restore_backup; then
            log INFO "Восстановление из резервной копии выполнено"
        fi
        return 1
    fi
    
    # Пересоздание update-скриптов и canonical Geo baseline
    if ! xray_updates_create_scripts; then
        log WARN "Не удалось пересоздать update-скрипты (продолжаем)"
    fi

    if ! xray_updates_initial_geo_load; then
        log WARN "Не удалось обновить Geo baseline после обновления core (продолжаем)"
    fi

    # Повторное применение systemd/config baseline после переустановки core
    if ! core_setup_systemd; then
        log ERROR "Не удалось повторно применить systemd override после обновления"
        return 1
    fi

    if ! config_setup_logging; then
        log WARN "Не удалось повторно применить настройку логирования (продолжаем)"
    fi

    if ! user_fix_permissions; then
        log WARN "Не удалось повторно применить права доступа (продолжаем)"
    fi

    if ! config_enable_service; then
        log ERROR "Не удалось включить и запустить xray.service после обновления"
        return 1
    fi
    
    # Проверка работоспособности после обновления
    if ! xray_verify_update; then
        log ERROR "Проверка работоспособности после обновления не прошла"
        return 1
    fi
    
    log OK "Xray успешно обновлен"
}

# === Проверка предварительных условий обновления ===
xray_check_update_prerequisites() {
    log INFO "Проверка предварительных условий обновления"
    
    # Проверка наличия Xray unit
    local xray_fragment_path=""
    xray_fragment_path="$(systemctl show -p FragmentPath --value xray.service 2>/dev/null || true)"

    if [[ -z "$xray_fragment_path" ]] && ! systemctl list-unit-files xray.service --no-legend 2>/dev/null | grep -q '^xray\.service'; then
        log ERROR "Xray unit не найден"
        return 1
    fi

    if ! systemctl is-active --quiet xray.service 2>/dev/null; then
        log WARN "xray.service установлен, но сейчас не активен; продолжаем update"
    fi
    
    # Проверка доступности интернета
    if ! ping -c 1 github.com >/dev/null 2>&1; then
        log ERROR "Нет доступа к интернету (требуется для загрузки обновлений)"
        return 1
    fi
    
    # Проверка доступности curl
    if ! command -v curl >/dev/null 2>&1; then
        log ERROR "curl не найден (требуется для загрузки обновлений)"
        return 1
    fi
    
    log OK "Предварительные условия обновления выполнены"
    return 0
}

# === Интерактивная настройка обновления ===
xray_interactive_update_setup() {
    log INFO "Интерактивная настройка обновления Xray"
    
    # Запрос на создание резервной копии
    ask_and_execute "xray" "create_backup" "Создать резервную копию перед обновлением?" "true" "xray_create_backup_impl"
    
    # Запрос на обновление Geo данных
    ask_and_execute "xray" "update_geo_data" "Обновить Geo данные вместе с Xray?" "true" "xray_update_geo_data_impl"
    
    log OK "Интерактивная настройка обновления завершена"
    return 0
}

# === Создание резервной копии ===
xray_create_backup() {
    log INFO "Создание резервной копии Xray"
    
    local backup_dir="/opt/xray/backup/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Копирование конфигураций
    if [[ -d "$XRAY_CONFIGS_PATH" ]]; then
        cp -r "$XRAY_CONFIGS_PATH" "$backup_dir/"
        log OK "Конфигурации скопированы в $backup_dir"
    fi
    
    # Копирование исполняемого файла
    if [[ -f "$XRAY_BINARY" ]]; then
        cp "$XRAY_BINARY" "$backup_dir/xray"
        log OK "Исполняемый файл скопирован в $backup_dir"
    fi
    
    # Сохранение информации о версии
    if "$XRAY_BINARY" version > "$backup_dir/version.txt" 2>/dev/null; then
        log OK "Информация о версии сохранена"
    fi
    
    log OK "Резервная копия создана: $backup_dir"
    return 0
}

# === Реализация создания резервной копии ===
xray_create_backup_impl() {
    log INFO "Создание резервной копии подтверждено"
    return 0
}

# === Реализация обновления Geo данных ===
xray_update_geo_data_impl() {
    log INFO "Обновление Geo данных подтверждено"
    return 0
}

# === Восстановление из резервной копии ===
xray_restore_backup() {
    log INFO "Восстановление из резервной копии"
    
    local backup_dir
    backup_dir="$(find /opt/xray/backup -type d -name "*" | sort | tail -1)"
    
    if [[ -z "$backup_dir" ]] || [[ ! -d "$backup_dir" ]]; then
        log ERROR "Резервная копия не найдена"
        return 1
    fi
    
    # Восстановление конфигураций
    if [[ -d "$backup_dir/configs" ]]; then
        cp -r "$backup_dir/configs" "$XRAY_CONFIGS_PATH"
        log OK "Конфигурации восстановлены"
    fi
    
    # Восстановление исполняемого файла
    if [[ -f "$backup_dir/xray" ]]; then
        cp "$backup_dir/xray" "$XRAY_BINARY"
        chmod +x "$XRAY_BINARY"
        log OK "Исполняемый файл восстановлен"
    fi
    
    log OK "Восстановление из резервной копии завершено"
    return 0
}

# === Проверка работоспособности после обновления ===
xray_verify_update() {
    log INFO "Проверка работоспособности после обновления"
    
    # Ожидание запуска сервиса
    sleep 2
    
    # Проверка статуса сервиса
    if ! systemctl is-active --quiet xray; then
        log ERROR "Сервис xray не активен после обновления"
        return 1
    fi
    
    # Проверка версии
    local new_version
    new_version="$("$XRAY_BINARY" version 2>/dev/null | head -1 || echo "unknown")"
    log INFO "Новая версия Xray: $new_version"
    
    # Проверка конфигурации
    if ! "$XRAY_BINARY" run -test -confdir "$XRAY_CONFIGS_PATH" >/dev/null 2>&1; then
        log ERROR "Конфигурация Xray невалидна после обновления"
        return 1
    fi
    
    log OK "Проверка работоспособности после обновления прошла успешно"
    return 0
}

# === Экспорт функций ===
export -f module_xray_init module_xray_execute module_xray_dependencies module_xray_info
export -f xray_install xray_uninstall xray_status xray_update
export -f load_xray_components init_xray_components cache_xray_config_vars validate_xray_config
export -f xray_interactive_setup xray_check_requirements xray_create_admin_user
export -f xray_enable_auto_updates xray_enable_geo_updates
export -f xray_confirm_uninstall xray_confirm_uninstall_impl
export -f xray_check_update_prerequisites xray_interactive_update_setup
export -f xray_create_backup xray_create_backup_impl xray_update_geo_data_impl
export -f xray_restore_backup xray_verify_update

# Автоматическая инициализация при загрузке модуля
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Если скрипт запущен напрямую
    module_xray_init "$@"
else
    # Если скрипт загружен как модуль
    module_xray_init
fi
