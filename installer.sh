#!/usr/bin/env bash

# === Xray Gateway Installer ===
# Версия: 2.0.0
# Автор: Xray Gateway Installer Team
# Описание: Модульный установщик и настройщик Xray Gateway

set -euo pipefail

# === Обработка SIGPIPE для CI/CD ===
# Игнорируем SIGPIPE чтобы избежать ложных ошибок в CI/CD
trap 'exit 0' SIGPIPE

# === Глобальные переменные ===
declare -g SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -g INSTALLER_VERSION="2.0.0"
declare -g CONFIG_DIR="${SCRIPT_DIR}/config"
declare -g LOG_FILE="${SCRIPT_DIR}/install.log"
declare -g DRY_RUN=false
declare -g VERBOSE=false
declare -g LOG_LEVEL="INFO"
declare -g COMMAND=""
declare -g MODULE_NAME=""
declare -g PLUGIN_NAME=""
declare -g FIREWALL_ACTION=""
declare -g MONITORING_ACTION=""
declare -g CONFIG_FILE=""
declare -g VARIABLES_FILE=""
declare -g AUTO_INSTALL_DEPENDENCIES="${AUTO_INSTALL_DEPENDENCIES:-true}"

# === Переменные логирования ===
declare -g LOGS_DIR=""
declare -g LOG_ROTATION_MODE=""
declare -g LOG_ROTATION_ENABLED=""
declare -g LOG_MAX_FILES=""
declare -g LOG_RETENTION_DAYS=""
declare -g AUTO_DETECT_STRUCTURE=""
declare -g COMPONENT_LOGGING_ENABLED=""
declare -g AUTO_CREATE_DIRS=""
declare -g DUPLICATE_TO_MAIN=""

installer_bootstrap_echo() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo "$*"
    fi
}

# === Загрузка переменных из YAML ===
load_variables() {
    local variables_file="${VARIABLES_FILE:-${CONFIG_DIR}/unified.yaml}"
    local runtime_script_dir="$SCRIPT_DIR"
    local runtime_config_dir="$CONFIG_DIR"
    
    if [[ ! -f "$variables_file" ]]; then
        installer_bootstrap_echo "WARN: Файл переменных не найден: $variables_file"
        return 0
    fi
    
    installer_bootstrap_echo "Загрузка переменных из: $variables_file"
    
    # Загрузка основных переменных
    # SCRIPT_DIR и CONFIG_DIR должны оставаться привязанными к реальному checkout,
    # из которого запущен installer. Иначе команды из репозитория начинают искать
    # core/modules в deploy-пути из YAML и ломаются.
    SCRIPT_DIR="$runtime_script_dir"
    CONFIG_DIR="$runtime_config_dir"
    LOG_FILE="$(yq -r '.variables.installer.log_file.value' "$variables_file" 2>/dev/null | tr -d '[]," ' || echo "$LOG_FILE")"
    LOG_LEVEL="$(yq -r '.variables.installer.log_level.value' "$variables_file" 2>/dev/null || echo "$LOG_LEVEL")"
    
    # Загрузка переменных логирования
    LOGS_DIR="$(yq -r '.logging.logs_dir.value' "$variables_file" 2>/dev/null | tr -d '[]," ' || echo "${SCRIPT_DIR}/_logs")"
    LOG_ROTATION_MODE="$(yq -r '.logging.log_rotation.mode.value' "$variables_file" 2>/dev/null || echo "per_run_overwrite")"
    LOG_ROTATION_ENABLED="$(yq -r '.logging.log_rotation.enabled.value' "$variables_file" 2>/dev/null || echo "true")"
    LOG_MAX_FILES="$(yq -r '.logging.log_rotation.max_files.value' "$variables_file" 2>/dev/null || echo "5")"
    LOG_RETENTION_DAYS="$(yq -r '.logging.log_rotation.retention_days.value' "$variables_file" 2>/dev/null || echo "7")"
    AUTO_DETECT_STRUCTURE="$(yq -r '.logging.auto_detect_structure.value' "$variables_file" 2>/dev/null || echo "true")"
    COMPONENT_LOGGING_ENABLED="$(yq -r '.logging.component_logging.enabled.value' "$variables_file" 2>/dev/null || echo "true")"
    AUTO_CREATE_DIRS="$(yq -r '.logging.component_logging.auto_create_dirs.value' "$variables_file" 2>/dev/null || echo "true")"
    DUPLICATE_TO_MAIN="$(yq -r '.logging.component_logging.duplicate_to_main.value' "$variables_file" 2>/dev/null || echo "false")"
    
    installer_bootstrap_echo "  ✓ Переменные загружены из YAML"
}

# === Инициализация ===
init() {
    # Загрузка переменных
    load_variables
    
    # Экспорт переменных
    export SCRIPT_DIR CONFIG_DIR LOG_FILE XRAY_INSTALL_PATH XRAY_CONFIG_DIR XRAY_LOG_DIR XRAY_USER XRAY_GROUP
    export LAN_INTERFACE WAN_INTERFACE TPROXY_PORT REDIRECT_PORT MARK_ID ROUTE_TABLE_ID XRAY_GID
    export LOGS_DIR LOG_ROTATION_MODE LOG_ROTATION_ENABLED LOG_MAX_FILES LOG_RETENTION_DAYS
    export AUTO_DETECT_STRUCTURE COMPONENT_LOGGING_ENABLED AUTO_CREATE_DIRS DUPLICATE_TO_MAIN
    export LOG_LEVEL LOG_CONSOLE LOG_SYSLOG
    export LOG_FILE LOGS_DIR COMPONENT_LOGGING_ENABLED AUTO_CREATE_DIRS DUPLICATE_TO_MAIN
    
    # Инициализация модулей ядра
    init_core_modules
}

# === Инициализация модулей ядра ===
init_core_modules() {
    installer_bootstrap_echo "Загрузка модулей ядра из директории: $SCRIPT_DIR/core"
    
    # Автоматическое обнаружение модулей по номерам
    installer_bootstrap_echo "Используется автоматическое обнаружение модулей по номерам"
    local core_modules=()
    while IFS= read -r -d '' file; do
        local module_name="$(basename "$file" .sh)"
        installer_bootstrap_echo "    Загружаем модуль: $module_name"
        source "$file"
        installer_bootstrap_echo "  ✓ Модуль загружен: $module_name"
        core_modules+=("$module_name")
    done < <(find "$SCRIPT_DIR/core" -name "*.sh" -type f -print0 | sort -z)
    
    installer_bootstrap_echo "Загружено модулей ядра: ${#core_modules[@]} (ошибок: 0)"
    
    # Инициализация модулей
    installer_bootstrap_echo "Инициализация модулей ядра"
    
    # Инициализация логгера с режимом ротации
    logger_init "installer" "_logs" "" "" "rotate"
    installer_bootstrap_echo "  ✓ Система логирования инициализирована (режим: ротация)"
    
    # Инициализация менеджера конфигурации
    config_init
    installer_bootstrap_echo "  ✓ Менеджер конфигурации инициализирован"
    
    # Инициализация менеджера плагинов
    plugin_manager_init
    installer_bootstrap_echo "  ✓ Менеджер плагинов инициализирован"
    
    installer_bootstrap_echo "Все модули ядра инициализированы"
}

should_precheck_dependencies() {
    case "${COMMAND:-}" in
        install|update)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# === Парсинг аргументов ===
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                [[ $# -ge 2 ]] || {
                    echo "ERROR: Для --config требуется значение"
                    exit 1
                }
                VARIABLES_FILE="$2"
                shift 2
                ;;
            --log-level)
                [[ $# -ge 2 ]] || {
                    echo "ERROR: Для --log-level требуется значение"
                    exit 1
                }
                LOG_LEVEL="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --version|-v)
                echo "Xray Gateway Installer v$INSTALLER_VERSION"
                exit 0
                ;;
            install|uninstall|status|update|dependencies)
                COMMAND="$1"
                shift
                break
                ;;
            firewall)
                COMMAND="firewall"
                if [[ $# -ge 2 && ! "$2" =~ ^-- ]]; then
                    FIREWALL_ACTION="$2"
                    shift 2
                else
                    FIREWALL_ACTION="status"
                    shift
                fi
                break
                ;;
            monitoring)
                COMMAND="monitoring"
                if [[ $# -ge 2 && ! "$2" =~ ^-- ]]; then
                    MONITORING_ACTION="$2"
                    shift 2
                else
                    MONITORING_ACTION="status"
                    shift
                fi
                break
                ;;
            *)
                echo "ERROR: Неизвестный аргумент: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Обработка дополнительных аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --module)
                [[ $# -ge 2 ]] || {
                    echo "ERROR: Для --module требуется значение"
                    exit 1
                }
                MODULE_NAME="$2"
                shift 2
                ;;
            --plugin)
                [[ $# -ge 2 ]] || {
                    echo "ERROR: Для --plugin требуется значение"
                    exit 1
                }
                PLUGIN_NAME="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
}

# === Показать справку ===
show_help() {
    cat << EOF
Xray Gateway Installer v$INSTALLER_VERSION

Использование: ./installer.sh [КОМАНДА] [ОПЦИИ]

КОМАНДЫ:
  install       Установка Xray Gateway
  uninstall     Удаление Xray Gateway
  status        Показать статус системы
  update        Принудительное обновление
  dependencies  Проверка зависимостей системы
  firewall      Управление файрволом
  monitoring    Управление мониторингом
  --help        Показать эту справку
  --version     Показать версию

ОПЦИИ:
  --config FILE        Файл конфигурации
  --log-level LEVEL    Уровень логирования (DEBUG|INFO|WARN|ERROR)
  --dry-run           Режим симуляции (не реализован)
  --verbose           Подробный вывод

УПРАВЛЕНИЕ КОМПОНЕНТАМИ:
  --module NAME       Работа с конкретным модулем
  --plugin NAME       Работа с конкретным плагином

ПОДКОМАНДЫ FIREWALL:
  firewall enable     Переключение в активный режим
  firewall disable    Переключение в kill-switch режим
  firewall diagnose   Диагностика kill-switch

ПОДКОМАНДЫ MONITORING:
  monitoring status   Статус мониторинга
  monitoring collect  Сбор метрик
  monitoring dashboard Показать дашборд
  monitoring export   Экспорт данных
  monitoring alerts   Управление алертами

ПРИМЕРЫ:
  ./installer.sh install
  ./installer.sh status --plugin firewall
  ./installer.sh firewall enable
  ./installer.sh monitoring status
EOF
}

# === Основная функция ===
main() {
    # Парсинг аргументов
    parse_arguments "$@"
    
    # Инициализация
    init
    
    # Полная проверка зависимостей нужна только для install/update.
    # status/firewall/monitoring/uninstall не должны побочно включать сервисы
    # или доустанавливать зависимости, если оператор просто смотрит состояние.
    if should_precheck_dependencies; then
        check_all_dependencies
    fi
    
    log INFO "Xray Gateway Installer v$INSTALLER_VERSION инициализирован"
    log INFO "Уровень логирования изменён на: $LOG_LEVEL"
    
    # Выполнение команд
    case "$COMMAND" in
        "install")
            install_system
            ;;
        "uninstall")
            uninstall_system
            ;;
        "status")
            if [[ -n "$MODULE_NAME" ]]; then
                status_module "$MODULE_NAME"
            elif [[ -n "$PLUGIN_NAME" ]]; then
                status_plugin "$PLUGIN_NAME"
            else
                show_status
            fi
            ;;
        "update")
            update_system
            ;;
        "dependencies")
            check_all_dependencies
            ;;
        "firewall")
            firewall_action "$FIREWALL_ACTION"
            ;;
        "monitoring")
            monitoring_action "$MONITORING_ACTION"
            ;;
        "")
            show_help
            ;;
        *)
            log ERROR "Неизвестная команда: $COMMAND"
            show_help
            exit 1
            ;;
    esac
    
    # Очистка
    cleanup
}

# === Установка системы ===
install_system() {
    log INFO "Установка Xray Gateway"
    
    # Загрузка плагинов
    load_plugins
    
    # Установка модулей
    if [[ -n "$MODULE_NAME" && "$MODULE_NAME" != "installer.sh" ]]; then
        install_module "$MODULE_NAME"
    else
        install_all_modules
    fi
    
    # Установка плагинов
    if [[ -n "$PLUGIN_NAME" ]]; then
        install_plugin "$PLUGIN_NAME"
    else
        install_all_plugins
    fi
    
    log OK "Установка Xray Gateway завершена"
}

# === Удаление системы ===
uninstall_system() {
    log INFO "Удаление Xray Gateway"
    
    # Загрузка плагинов
    load_plugins

    # Сначала удаляем плагины, пока runtime Xray и /opt/xray ещё существуют.
    # Это позволяет корректно снять firewall, monitoring и связанные systemd/cron хвосты.
    if [[ -n "$PLUGIN_NAME" ]]; then
        uninstall_plugin "$PLUGIN_NAME"
    else
        uninstall_all_plugins
    fi

    # Затем удаляем модули
    if [[ -n "$MODULE_NAME" && "$MODULE_NAME" != "installer.sh" ]]; then
        uninstall_module "$MODULE_NAME"
    else
        uninstall_all_modules
    fi
    
    log OK "Удаление Xray Gateway завершено"
}

# === Показать статус ===
show_status() {
    log INFO "Статус системы Xray Gateway"
    
    # Статус модулей
    log INFO "Проверка модулей..."
    for module in system xray; do
        if [[ -f "$SCRIPT_DIR/modules/$module/$module.sh" ]]; then
            log OK "Модуль $module найден"
        else
            log WARN "Модуль $module не найден"
        fi
    done
    
    # Статус плагинов
    log INFO "Проверка плагинов..."
    local plugin
    while IFS= read -r plugin; do
        [[ -z "$plugin" ]] && continue
        if [[ -f "$SCRIPT_DIR/plugins/$plugin/$plugin.sh" ]]; then
            log OK "Плагин $plugin найден"
        else
            log WARN "Плагин $plugin не найден"
        fi
    done < <(discover_available_plugins)
}

# === Загрузка плагинов ===
load_plugins() {
    log INFO "Загрузка плагинов системы"
    load_all_plugins
    log OK "Плагины загружены и инициализированы"
}

# === Действия с файрволом ===
firewall_action() {
    local action="$1"
    
    if [[ -z "$action" ]]; then
        log ERROR "Не указано действие для файрвола"
        return 1
    fi
    
    log INFO "Получение статуса плагина firewall..."
    load_plugins
    
    log INFO "Выполнение действия firewall: $action"
    plugin_firewall_execute "$action"
    log OK "Действие firewall: $action выполнено"
}

# === Действия с мониторингом ===
monitoring_action() {
    local action="$1"
    
    if [[ -z "$action" ]]; then
        log ERROR "Не указано действие для мониторинга"
        return 1
    fi
    
    log INFO "Получение статуса плагина monitoring..."
    load_plugins
    
    log INFO "Выполнение действия monitoring: $action"
    plugin_monitoring_execute "$action"
    log OK "Действие monitoring: $action выполнено"
}

# === Очистка ===
cleanup() {
    if declare -f cleanup_plugins >/dev/null 2>&1; then
        cleanup_plugins
    fi
}

update_module() {
    local module_name="$1"

    if [[ ! -f "$SCRIPT_DIR/modules/$module_name/$module_name.sh" ]]; then
        log ERROR "Модуль $module_name не найден"
        return 1
    fi

    export SCRIPT_DIR CONFIG_DIR LOG_FILE
    export NONINTERACTIVE=1

    source "$SCRIPT_DIR/modules/$module_name/$module_name.sh"

    if declare -f "${module_name}_update" >/dev/null 2>&1; then
        log INFO "Обновление модуля: $module_name"
        "${module_name}_update"
        log OK "Модуль $module_name обновлён"
        return 0
    fi

    log WARN "Модуль $module_name не поддерживает update"
    return 0
}

update_system() {
    log INFO "Принудительное обновление Xray Gateway"

    load_plugins

    if [[ -n "$MODULE_NAME" && "$MODULE_NAME" != "installer.sh" ]]; then
        update_module "$MODULE_NAME"
    else
        update_module "xray"
    fi

    if [[ -n "$PLUGIN_NAME" ]]; then
        if [[ "$PLUGIN_NAME" == "firewall" ]]; then
            log INFO "Приведение firewall к актуальному runtime-состоянию"
            plugin_firewall_execute "restart"
        else
            log WARN "Плагин $PLUGIN_NAME не поддерживает отдельный update, пропускаем"
        fi
    fi

    log OK "Принудительное обновление завершено"
}

# === Управление модулями ===
install_module() {
    local module_name="$1"
    log INFO "Установка модуля: $module_name"
    
    if [[ -f "$SCRIPT_DIR/modules/$module_name/$module_name.sh" ]]; then
        log INFO "Файл модуля найден: $SCRIPT_DIR/modules/$module_name/$module_name.sh"
        
        # Экспорт переменных для модуля
        export SCRIPT_DIR CONFIG_DIR LOG_FILE
        # Установка неинтерактивного режима для автоматической установки
        export NONINTERACTIVE=1
        log INFO "Переменные экспортированы для модуля $module_name"
        
        log INFO "Начинаем загрузку модуля $module_name"
        if source "$SCRIPT_DIR/modules/$module_name/$module_name.sh"; then
            log OK "Модуль $module_name загружен успешно"
        else
            log ERROR "Ошибка загрузки модуля $module_name"
            return 1
        fi
        
        log INFO "Проверяем наличие функции установки для модуля $module_name"
        if declare -f "${module_name}_install" >/dev/null 2>&1; then
            log INFO "Функция ${module_name}_install найдена, начинаем выполнение"
            if "${module_name}_install"; then
                log OK "Модуль $module_name установлен"
            else
                log ERROR "Ошибка установки модуля $module_name"
                return 1
            fi
        else
            log WARN "Функция установки модуля $module_name не найдена"
        fi
    else
        log ERROR "Модуль $module_name не найден"
        return 1
    fi
}

uninstall_module() {
    local module_name="$1"
    log INFO "Удаление модуля: $module_name"
    
    if [[ -f "$SCRIPT_DIR/modules/$module_name/$module_name.sh" ]]; then
        # Экспорт переменных для модуля
        export SCRIPT_DIR CONFIG_DIR LOG_FILE
        export NONINTERACTIVE=1
        source "$SCRIPT_DIR/modules/$module_name/$module_name.sh"
        if declare -f "${module_name}_uninstall" >/dev/null 2>&1; then
            "${module_name}_uninstall"
            log OK "Модуль $module_name удален"
        else
            log WARN "Функция удаления модуля $module_name не найдена"
        fi
    else
        log ERROR "Модуль $module_name не найден"
        return 1
    fi
}

install_all_modules() {
    log INFO "Установка всех модулей"
    
    
    # Экспорт переменных для всех модулей
    export SCRIPT_DIR CONFIG_DIR LOG_FILE
    export NONINTERACTIVE=1
    
    for module in system xray; do
        log INFO "Обработка модуля: $module"
        if [[ -f "$SCRIPT_DIR/modules/$module/$module.sh" ]]; then
            log INFO "Файл модуля $module существует, начинаем установку"
            if install_module "$module"; then
                log OK "Модуль $module установлен успешно"
            else
                log ERROR "Ошибка установки модуля $module"
                return 1
            fi
        else
            log ERROR "Файл модуля $module не найден: $SCRIPT_DIR/modules/$module/$module.sh"
            return 1
        fi
    done
    log OK "Все модули установлены"
}

uninstall_all_modules() {
    log INFO "Удаление всех модулей"
    
    # Экспорт переменных для всех модулей
    export SCRIPT_DIR CONFIG_DIR LOG_FILE
    export NONINTERACTIVE=1
    
    for module in xray system; do
        if [[ -f "$SCRIPT_DIR/modules/$module/$module.sh" ]]; then
            uninstall_module "$module"
        fi
    done
    log OK "Все модули удалены"
}

# === Управление плагинами ===
install_plugin() {
    local plugin_name="$1"
    log INFO "Установка плагина: $plugin_name"
    
    if [[ -f "$SCRIPT_DIR/plugins/$plugin_name/$plugin_name.sh" ]]; then
        log INFO "Загрузка плагина: $plugin_name"
        source "$SCRIPT_DIR/plugins/$plugin_name/$plugin_name.sh"
        if declare -f "${plugin_name}_install" >/dev/null 2>&1; then
            log INFO "Вызов функции ${plugin_name}_install"
            "${plugin_name}_install"
            log OK "Плагин $plugin_name установлен"
        else
            log WARN "Функция установки плагина $plugin_name не найдена"
        fi
    else
        log ERROR "Плагин $plugin_name не найден: $SCRIPT_DIR/plugins/$plugin_name/$plugin_name.sh"
        return 1
    fi
}

uninstall_plugin() {
    local plugin_name="$1"
    log INFO "Удаление плагина: $plugin_name"
    
    if [[ -f "$SCRIPT_DIR/plugins/$plugin_name/$plugin_name.sh" ]]; then
        source "$SCRIPT_DIR/plugins/$plugin_name/$plugin_name.sh"
        if declare -f "${plugin_name}_uninstall" >/dev/null 2>&1; then
            "${plugin_name}_uninstall"
            log OK "Плагин $plugin_name удален"
        else
            log WARN "Функция удаления плагина $plugin_name не найдена"
        fi
    else
        log ERROR "Плагин $plugin_name не найден"
        return 1
    fi
}

install_all_plugins() {
    log INFO "Установка всех плагинов"
    for plugin in firewall monitoring; do
        if [[ -f "$SCRIPT_DIR/plugins/$plugin/$plugin.sh" ]]; then
            install_plugin "$plugin"
        else
            log WARN "Плагин $plugin не найден: $SCRIPT_DIR/plugins/$plugin/$plugin.sh"
        fi
    done
    log OK "Все плагины установлены"
}

uninstall_all_plugins() {
    log INFO "Удаление всех плагинов"
    for plugin in monitoring firewall; do
        if [[ -f "$SCRIPT_DIR/plugins/$plugin/$plugin.sh" ]]; then
            uninstall_plugin "$plugin"
        fi
    done
    log OK "Все плагины удалены"
}

# === Обработка завершения ===
cleanup_and_exit() {
    local exit_code="${1:-0}"
    
    # Обработка SIGPIPE - не считаем это ошибкой
    if [[ $exit_code -eq 141 ]]; then
        exit_code=0
    fi
    
    exit $exit_code
}

# === Запуск ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Обработка сигналов
    trap 'cleanup_and_exit 0' SIGPIPE
    trap 'cleanup_and_exit 1' ERR
    
    main "$@"
    
    # Нормальное завершение
    cleanup_and_exit 0
fi
