#!/usr/bin/env bash

# === Система логирования Xray Gateway Installer ===
# Версия: 3.0.0
# Автор: Xray Gateway Installer Team
# Улучшения: Отдельные логи для модулей/плагинов + основной лог

# Глобальные переменные для логирования
declare -g LOG_LEVEL="INFO"
declare -g LOG_FILE=""
declare -g MODULE_LOG_FILE=""
declare -g PLUGIN_LOG_FILE=""
declare -g CORE_LOG_FILE=""
declare -g LOG_CONSOLE=true
declare -g LOG_SYSLOG=false
# НЕ объявляем SCRIPT_DIR здесь, так как это глобальная переменная
declare -g MODULE_NAME=""
declare -g CURRENT_MODULE=""
declare -g CURRENT_PLUGIN=""
declare -g CURRENT_CORE_MODULE=""

# Режимы работы с логами
declare -g LOG_MODE="append"  # append, overwrite, rotate
declare -g LOG_ROTATE_COUNT=5  # Количество файлов для ротации

# Уровни логирования
declare -A LOG_LEVELS=(
    ["DEBUG"]=0
    ["INFO"]=1
    ["WARN"]=2
    ["ERROR"]=3
    ["FATAL"]=4
)

# Цвета для консольного вывода
declare -A LOG_COLORS=(
    ["DEBUG"]='\033[0;36m'    # Cyan
    ["INFO"]='\033[1;34m'     # Blue
    ["OK"]='\033[1;32m'       # Green
    ["SUCCESS"]='\033[1;32m'  # Green
    ["WARN"]='\033[1;33m'     # Yellow
    ["ERROR"]='\033[1;31m'    # Red
    ["FATAL"]='\033[1;31m'    # Red
    ["SEP"]='\033[1;30m'      # Dark Gray
    ["SEPARATOR"]='\033[1;30m' # Dark Gray
    ["TITLE"]='\033[1;36m'    # Cyan
    ["HEADER"]='\033[1;36m'   # Cyan
)

declare -g RESET_COLOR='\033[0m'

# === Проверка необходимости логирования ===
should_log() {
    local level="${1:-INFO}"
    local log_level="${LOG_LEVEL:-INFO}"
    
    # Безопасное получение значений из ассоциативного массива
    local current_level=1
    local message_level=1
    
    # Проверяем, что переменные не пустые и существуют в массиве
    if [[ -n "$log_level" ]]; then
    case "$log_level" in
            "DEBUG") current_level=0 ;;
            "INFO") current_level=1 ;;
            "WARN") current_level=2 ;;
            "ERROR") current_level=3 ;;
            "FATAL") current_level=4 ;;
            *) current_level=1 ;;
        esac
    fi
    
    if [[ -n "$level" ]]; then
        case "$level" in
            "DEBUG") message_level=0 ;;
            "INFO") message_level=1 ;;
            "WARN") message_level=2 ;;
            "ERROR") message_level=3 ;;
            "FATAL") message_level=4 ;;
            *) message_level=1 ;;
        esac
    fi
    
    # Логируем если уровень сообщения >= текущего уровня
    [[ $message_level -ge $current_level ]]
}

# === Инициализация системы логирования ===
logger_init() {
    local script_name="${1:-installer}"
    local log_dir="${2:-_logs}"
    local module_name="${3:-}"
    local plugin_name="${4:-}"
    local log_mode="${5:-append}"
    
    # Установка переменных
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    LOG_LEVEL="${LOG_LEVEL:-INFO}"
    LOG_MODE="$log_mode"
    
    # Создание директории логов
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" || {
            echo "Ошибка создания директории логов: $log_dir" >&2
            return 1
        }
    fi
    
    # Основной лог файл
    LOG_FILE="$log_dir/${script_name}.log"
    
    # Обработка режима работы с основным логом
    handle_log_mode "$LOG_FILE"
    
    # Лог файл для модуля/плагина
    if [[ -n "$module_name" ]]; then
        CURRENT_MODULE="$module_name"
        MODULE_NAME="$module_name"
        MODULE_LOG_FILE="$log_dir/modules/${module_name}.log"
        mkdir -p "$(dirname "$MODULE_LOG_FILE")"
        handle_log_mode "$MODULE_LOG_FILE"
    elif [[ -n "$plugin_name" ]]; then
        CURRENT_PLUGIN="$plugin_name"
        # НЕ устанавливаем MODULE_NAME для плагинов, чтобы избежать конфликтов
        PLUGIN_LOG_FILE="$log_dir/plugins/${plugin_name}.log"
        mkdir -p "$(dirname "$PLUGIN_LOG_FILE")"
        handle_log_mode "$PLUGIN_LOG_FILE"
    fi
    
    # Инициализация основного лога
    if [[ -n "$LOG_FILE" ]]; then
        echo "=== Инициализация логирования $(date) ===" >> "$LOG_FILE"
    fi
    
    # Инициализация лога модуля
    if [[ -n "$MODULE_LOG_FILE" ]]; then
        echo "=== Инициализация логирования модуля $(date) ===" >> "$MODULE_LOG_FILE"
    fi
    
    # Инициализация лога плагина
    if [[ -n "$PLUGIN_LOG_FILE" ]]; then
        echo "=== Инициализация логирования плагина $(date) ===" >> "$PLUGIN_LOG_FILE"
    fi
    
    return 0
}

# === Основная функция логирования ===
log() {
    local level="${1:-INFO}"
    local message="${2:-}"
    local module="${3:-$MODULE_NAME}"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Проверка необходимости логирования
    if ! should_log "$level"; then
        return 0
    fi
    
    # Определение модуля и плагина
    local current_module=""
    local current_plugin=""
    
    # Определение текущего модуля
    if [[ -n "${CURRENT_MODULE:-}" ]]; then
        current_module="$CURRENT_MODULE"
    elif [[ -n "$module" ]]; then
        current_module="$module"
    fi
    
    # Определение текущего плагина
    if [[ -n "${CURRENT_PLUGIN:-}" ]]; then
        current_plugin="$CURRENT_PLUGIN"
    fi
    
    # Новый формат: [дата_время] [level] [module] [plugin] message
    local formatted_message="[$timestamp] [$level]"
    
    # Добавление модуля
    if [[ -n "$current_module" ]]; then
        formatted_message="$formatted_message [$current_module]"
    else
        formatted_message="$formatted_message [installer]"
    fi
    
    # Добавление плагина
    if [[ -n "$current_plugin" ]]; then
        formatted_message="$formatted_message [$current_plugin]"
    fi
    
    # Добавление сообщения
    formatted_message="$formatted_message $message"
    
    # Логирование в основной файл
    if [[ -n "$LOG_FILE" ]]; then
        echo "$formatted_message" >> "$LOG_FILE"
    fi
    
    # Логирование в файл модуля
    if [[ -n "$MODULE_LOG_FILE" ]]; then
        echo "$formatted_message" >> "$MODULE_LOG_FILE"
    fi
    
    # Логирование в файл плагина
    if [[ -n "$PLUGIN_LOG_FILE" ]]; then
        echo "$formatted_message" >> "$PLUGIN_LOG_FILE"
    fi
    
    # Консольный вывод
    if [[ "$LOG_CONSOLE" == "true" ]]; then
        log_to_console "$level" "$formatted_message"
    fi
    
    # Syslog
    if [[ "$LOG_SYSLOG" == "true" ]]; then
        log_to_syslog "$level" "$message"
    fi
}

# === Консольный вывод ===
log_to_console() {
    local level="${1:-INFO}"
    local message="$2"
    local color=""
    
    # Безопасное получение цвета
    case "$level" in
        "DEBUG") color='\033[0;36m' ;;
        "INFO") color='\033[1;34m' ;;
        "OK") color='\033[1;32m' ;;
        "SUCCESS") color='\033[1;32m' ;;
        "WARN") color='\033[1;33m' ;;
        "ERROR") color='\033[1;31m' ;;
        "FATAL") color='\033[1;31m' ;;
        "SEP") color='\033[1;30m' ;;
        "SEPARATOR") color='\033[1;30m' ;;
        "TITLE") color='\033[1;36m' ;;
        "HEADER") color='\033[1;36m' ;;
        *) color='' ;;
    esac
    
    if [[ -n "$color" ]]; then
    echo -e "${color}${message}${RESET_COLOR}"
    else
        echo "$message"
    fi
}

# === Syslog ===
log_to_syslog() {
    local level="$1"
    local message="$2"
    
    case "$level" in
        "DEBUG") logger -p user.debug "$message" ;;
        "INFO") logger -p user.info "$message" ;;
        "WARN") logger -p user.warning "$message" ;;
        "ERROR"|"FATAL") logger -p user.err "$message" ;;
        *) logger -p user.info "$message" ;;
    esac
}

# === Разделитель ===
log_separator() {
    local char="${1:-=}"
    local length="${2:-60}"
    local message="${3:-}"
    
    local separator=""
    for ((i=0; i<length; i++)); do
        separator+="$char"
    done
    
    if [[ -n "$message" ]]; then
        log "SEP" "$message"
        log "SEP" "$separator"
    else
        log "SEP" "$separator"
    fi
}

# === Заголовок ===
log_header() {
    local title="$1"
    local char="${2:-=}"
    local length="${3:-60}"
    
    log_separator "$char" "$length"
    log "HEADER" "$title"
    log_separator "$char" "$length"
}

# === Установка уровня логирования ===
set_log_level() {
    local level="$1"
    
    if [[ -n "${LOG_LEVELS[$level]:-}" ]]; then
        LOG_LEVEL="$level"
        log "INFO" "Уровень логирования установлен: $level"
        return 0
    else
        log "ERROR" "Неверный уровень логирования: $level"
            return 1
    fi
}

# === Получение уровня логирования ===
get_log_level() {
    echo "$LOG_LEVEL"
}

# === Проверка доступности логирования ===
is_logging_available() {
    [[ -n "$LOG_FILE" ]] && [[ -w "$(dirname "$LOG_FILE")" ]]
}

# === Инициализация логирования для модуля ===
module_logger_init() {
    local module_name="$1"
    local log_dir="${2:-_logs}"
    
    if [[ -z "$module_name" ]]; then
        echo "Ошибка: имя модуля не указано" >&2
        return 1
    fi
    
    # Установка переменных для модуля
    CURRENT_MODULE="$module_name"
    # НЕ устанавливаем MODULE_NAME, так как это глобальная переменная для командной строки
    MODULE_LOG_FILE="$log_dir/modules/${module_name}.log"
    
    # Установка основного лога для дублирования (если он не установлен)
    if [[ -z "${LOG_FILE:-}" ]]; then
        LOG_FILE="$log_dir/installer.log"
    fi
    
    # Создание директории для логов модуля
    mkdir -p "$(dirname "$MODULE_LOG_FILE")" || {
        echo "Ошибка создания директории логов модуля: $(dirname "$MODULE_LOG_FILE")" >&2
        return 1
    }
    
    # Дублирование в основной лог (если он установлен)
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "=== Инициализация логирования модуля $module_name $(date) ===" >> "$LOG_FILE"
    fi
    
    # Инициализация лога модуля
    echo "=== Инициализация логирования модуля $module_name $(date) ===" >> "$MODULE_LOG_FILE"
    
    return 0
}

# === Инициализация логирования для плагина ===
plugin_logger_init() {
    local plugin_name="$1"
    local log_dir="${2:-_logs}"
    
    if [[ -z "$plugin_name" ]]; then
        echo "Ошибка: имя плагина не указано" >&2
        return 1
    fi
    
    # Установка переменных для плагина
    CURRENT_PLUGIN="$plugin_name"
    # НЕ устанавливаем MODULE_NAME, так как это глобальная переменная для командной строки
    PLUGIN_LOG_FILE="$log_dir/plugins/${plugin_name}.log"
    
    # Установка основного лога для дублирования (если он не установлен)
    if [[ -z "${LOG_FILE:-}" ]]; then
        LOG_FILE="$log_dir/installer.log"
    fi
    
    # Создание директории для логов плагина
    mkdir -p "$(dirname "$PLUGIN_LOG_FILE")" || {
        echo "Ошибка создания директории логов плагина: $(dirname "$PLUGIN_LOG_FILE")" >&2
        return 1
    }
    
    # Дублирование в основной лог (если он установлен)
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "=== Инициализация логирования плагина $plugin_name $(date) ===" >> "$LOG_FILE"
    fi
    
    # Инициализация лога плагина
    echo "=== Инициализация логирования плагина $plugin_name $(date) ===" >> "$PLUGIN_LOG_FILE"
    
    return 0
}

# === Получение пути к логу модуля/плагина ===
get_module_log_file() {
    echo "$MODULE_LOG_FILE"
}

# === Получение пути к основному логу ===
get_main_log_file() {
    echo "$LOG_FILE"
}

# === Ротация логов ===
rotate_logs() {
    local log_file="$1"
    local max_size="${2:-10485760}"  # 10MB по умолчанию
    local max_files="${3:-5}"
    local lock_dir="${log_file}.rotate.lock"
    
    if [[ ! -f "$log_file" ]]; then
        return 0
    fi

    mkdir -p "$(dirname "$log_file")"

    if ! mkdir "$lock_dir" 2>/dev/null; then
        # Другой процесс уже выполняет ротацию этого файла.
        # Это не ошибка для вызывающего CLI.
        return 0
    fi
    
    local file_size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo "0")
    
    if [[ $file_size -gt $max_size ]]; then
        # Ротация логов
        for ((i=$max_files; i>1; i--)); do
            local old_file="${log_file}.$((i-1))"
            local new_file="${log_file}.$i"
            if [[ -f "$old_file" ]]; then
                mv -f "$old_file" "$new_file" 2>/dev/null || true
            fi
        done
        
        # Перемещение текущего лога
        if [[ -f "$log_file" ]]; then
            mv -f "$log_file" "${log_file}.1" 2>/dev/null || true
        fi
        
        # Создание нового лога
        touch "$log_file"
        echo "=== Ротация логов $(date) ===" >> "$log_file"
        
        log "INFO" "Ротация логов выполнена: $log_file"
    fi

    rmdir "$lock_dir" 2>/dev/null || true
}

# === Очистка старых логов ===
cleanup_old_logs() {
    local log_dir="$1"
    local days="${2:-30}"
    
    if [[ ! -d "$log_dir" ]]; then
        return 0
    fi
    
    # Поиск и удаление старых логов
    find "$log_dir" -name "*.log.*" -type f -mtime +$days -delete 2>/dev/null
    
    log "INFO" "Очистка старых логов выполнена (старше $days дней)"
}

# === Обработка режима работы с логами ===
handle_log_mode() {
    local log_file="$1"
    local mode="${LOG_MODE:-append}"
    
    if [[ -z "$log_file" ]]; then
        return 0
    fi
    
    case "$mode" in
        "overwrite")
            # Перезапись лога
            if [[ -f "$log_file" ]]; then
                rm -f "$log_file"
            fi
            touch "$log_file"
            ;;
        "rotate")
            # Ротация логов
            rotate_logs "$log_file" 0 "$LOG_ROTATE_COUNT"
            ;;
        "append"|*)
            # Дозапись (по умолчанию)
            if [[ ! -f "$log_file" ]]; then
                touch "$log_file"
            fi
            ;;
    esac
}

# === Инициализация логирования для модулей ядра ===
core_logger_init() {
    local core_module_name="$1"
    local log_dir="${2:-_logs}"
    local log_mode="${3:-append}"
    
    if [[ -z "$core_module_name" ]]; then
        echo "Ошибка: имя модуля ядра не указано" >&2
        return 1
    fi
    
    # Установка переменных для модуля ядра
    CURRENT_CORE_MODULE="$core_module_name"
    # НЕ устанавливаем MODULE_NAME, так как это глобальная переменная для командной строки
    CORE_LOG_FILE="$log_dir/core/${core_module_name}.log"
    
    # Создание директории для логов модулей ядра
    mkdir -p "$(dirname "$CORE_LOG_FILE")" || {
        echo "Ошибка создания директории логов модуля ядра: $(dirname "$CORE_LOG_FILE")" >&2
        return 1
    }
    
    # Обработка режима работы с логом
    LOG_MODE="$log_mode"
    handle_log_mode "$CORE_LOG_FILE"
    
    # Инициализация лога модуля ядра
    echo "=== Инициализация логирования модуля ядра $core_module_name $(date) ===" >> "$CORE_LOG_FILE"
    
    return 0
}

# === Установка режима логирования ===
set_log_mode() {
    local mode="$1"
    local rotate_count="${2:-5}"
    
    case "$mode" in
        "append"|"overwrite"|"rotate")
            LOG_MODE="$mode"
            LOG_ROTATE_COUNT="$rotate_count"
            log "INFO" "Режим логирования установлен: $mode (ротация: $rotate_count файлов)"
            return 0
            ;;
        *)
            log "ERROR" "Неверный режим логирования: $mode (доступны: append, overwrite, rotate)"
            return 1
            ;;
    esac
}

# === Получение режима логирования ===
get_log_mode() {
    echo "$LOG_MODE"
}

# === Получение пути к логу модуля ядра ===
get_core_log_file() {
    echo "$CORE_LOG_FILE"
}

# === Экспорт функций ===
export -f should_log
export -f logger_init
export -f log
export -f log_to_console
export -f log_to_syslog
export -f log_separator
export -f log_header
export -f set_log_level
export -f get_log_level
export -f is_logging_available
export -f module_logger_init
export -f plugin_logger_init
export -f core_logger_init
export -f get_module_log_file
export -f get_main_log_file
export -f get_core_log_file
export -f rotate_logs
export -f cleanup_old_logs
export -f handle_log_mode
export -f set_log_mode
export -f get_log_mode
