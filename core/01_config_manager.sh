#!/usr/bin/env bash

# === Менеджер конфигурации Xray Gateway Installer ===
# Версия: 2.0.0
# Автор: Xray Gateway Installer Team

# Глобальные переменные конфигурации
declare -g CONFIG_DIR="${CONFIG_DIR:-${SCRIPT_DIR:-/opt/xray-installer}/config}"
declare -g UNIFIED_CONFIG="${UNIFIED_CONFIG:-$CONFIG_DIR/unified.yaml}"
declare -g CONFIG_CACHE="${CONFIG_CACHE:-}"
declare -g CONFIG_INITIALIZED="${CONFIG_INITIALIZED:-false}"
declare -g CONFIG_INITIALIZED_PATH="${CONFIG_INITIALIZED_PATH:-}"

# === Безопасное логирование (работает без logger.sh) ===
safe_log() {
    local level="$1"
    shift
    local message="$*"
    
    # Если log доступна, используем её
    if command -v log >/dev/null 2>&1; then
        log "$level" "$message"
    else
        # Иначе простой вывод с префиксами
        local prefix=""
        case "$level" in
            ERROR|FATAL) prefix="❌ ОШИБКА" ;;
            WARN) prefix="⚠️  ПРЕДУПРЕЖДЕНИЕ" ;;
            OK) prefix="✅ OK" ;;
            INFO) prefix="ℹ️  ИНФО" ;;
            DEBUG) prefix="🔍 DEBUG" ;;
            *) prefix="📋 $level" ;;
        esac
        
        if [[ "$level" == "ERROR" || "$level" == "FATAL" || "$level" == "WARN" ]]; then
            echo "$prefix: $message" >&2
        else
            echo "$prefix: $message"
        fi
    fi
}

# === Инициализация менеджера конфигурации ===
config_init() {
    local base_dir="${1:-$SCRIPT_DIR}"
    local target_config_dir="$base_dir/config"
    local target_unified_config="$target_config_dir/unified.yaml"

    if [[ "${CONFIG_INITIALIZED:-false}" == "true" && "${CONFIG_INITIALIZED_PATH:-}" == "$target_unified_config" ]]; then
        return 0
    fi

    # Инициализация логирования для модуля ядра
    core_logger_init "config_manager" "_logs" "append"

    CONFIG_DIR="$target_config_dir"
    UNIFIED_CONFIG="$target_unified_config"
    
    # Проверка существования единого файла конфигурации
    if [[ ! -f "$UNIFIED_CONFIG" ]]; then
        safe_log ERROR "Единый файл конфигурации не найден: $UNIFIED_CONFIG"
        return 1
    fi
    
    # Проверка синтаксиса YAML
    if ! python3 -c "import yaml; yaml.safe_load(open('$UNIFIED_CONFIG'))" 2>/dev/null; then
        safe_log ERROR "Ошибка синтаксиса в файле конфигурации: $UNIFIED_CONFIG"
        return 1
    fi
    
    # Загрузка конфигурации в кэш
    load_config_cache

    CONFIG_INITIALIZED="true"
    CONFIG_INITIALIZED_PATH="$UNIFIED_CONFIG"
    
    safe_log INFO "Менеджер конфигурации инициализирован"
    safe_log DEBUG "Единый файл конфигурации: $UNIFIED_CONFIG"
}

# === Загрузка конфигурации в кэш ===
load_config_cache() {
    CONFIG_CACHE="$(mktemp)"
    
    # Копирование единого файла конфигурации в кэш
    cp "$UNIFIED_CONFIG" "$CONFIG_CACHE"
    
    safe_log DEBUG "Конфигурация загружена в кэш: $CONFIG_CACHE"
}

# === Подстановка переменных в строке ===
substitute_variables() {
    local input="$1"
    local result="$input"
    
    # Подставляем переменные вида ${VAR} или $VAR
    while [[ "$result" =~ \$\{([^}]+)\} ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local var_value="${!var_name:-}"
        result="${result//\$\{$var_name\}/$var_value}"
    done
    
    # Подставляем простые переменные вида $VAR (но не в середине слова)
    while [[ "$result" =~ \$([A-Z_][A-Z0-9_]*) ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local var_value="${!var_name:-}"
        result="${result//\$$var_name/$var_value}"
    done
    
    echo "$result"
}

# === Валидация пути после подстановки переменных ===
validate_path() {
    local path="$1"
    local path_type="${2:-file}"  # file, dir, or any
    
    # Проверяем, что путь не содержит неразвернутые переменные
    if [[ "$path" =~ \$\{|\$[A-Z_][A-Z0-9_]* ]]; then
        safe_log WARN "Путь содержит неразвернутые переменные: $path"
        return 1
    fi
    
    # Проверяем, что путь не пустой
    if [[ -z "$path" ]]; then
        safe_log WARN "Путь пустой после подстановки переменных"
        return 1
    fi
    
    # Проверяем тип пути
    case "$path_type" in
        "file")
            if [[ -f "$path" ]]; then
                safe_log DEBUG "Файл существует: $path"
                return 0
            elif [[ -d "$path" ]]; then
                safe_log WARN "Путь является директорией, а не файлом: $path"
                return 1
            else
                safe_log DEBUG "Файл не существует: $path"
                return 0  # Файл может быть создан позже
            fi
            ;;
        "dir")
            if [[ -d "$path" ]]; then
                safe_log DEBUG "Директория существует: $path"
                return 0
            elif [[ -f "$path" ]]; then
                safe_log WARN "Путь является файлом, а не директорией: $path"
                return 1
            else
                safe_log DEBUG "Директория не существует: $path"
                return 0  # Директория может быть создана позже
            fi
            ;;
        "any")
            if [[ -e "$path" ]]; then
                safe_log DEBUG "Путь существует: $path"
                return 0
            else
                safe_log DEBUG "Путь не существует: $path"
                return 0  # Путь может быть создан позже
            fi
            ;;
    esac
    
    return 0
}

# === Получение значения из YAML ===
yaml_get_value() {
    local file="$1"
    local key="$2"
    local default="${3:-}"
    
    if [[ ! -f "$file" ]]; then
        safe_log WARN "Файл конфигурации не найден: $file"
        echo "$default"
        return 1
    fi
    
    # Используем yq для парсинга YAML
    local value
    if command -v yq >/dev/null 2>&1; then
        value="$(yq -r ".$key.value // .$key // \"\"" "$file" 2>/dev/null || true)"

        if [[ -n "$value" && "$value" != "null" ]]; then
            # Подставляем переменные в полученное значение
            value="$(substitute_variables "$value")"
            
            # Валидируем путь, если это похоже на путь
            if [[ "$value" =~ ^/ ]]; then
                validate_path "$value" "any" || safe_log WARN "Проблема с путем: $value"
            fi
            
            echo "$value"
        else
            echo "$default"
        fi
    else
        value="$(
            python3 - "$file" "$key" <<'PY' 2>/dev/null || true
import sys
import yaml

file_path, dotted_key = sys.argv[1], sys.argv[2]

with open(file_path, "r", encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

current = data
for part in dotted_key.split("."):
    if not isinstance(current, dict) or part not in current:
        current = None
        break
    current = current[part]

if isinstance(current, dict) and "value" in current:
    current = current["value"]

if current is None:
    sys.exit(1)

if isinstance(current, (list, dict)):
    print(yaml.safe_dump(current, default_flow_style=True).strip())
else:
    print(str(current))
PY
        )"
        
        if [[ $? -eq 0 && -n "$value" ]]; then
            # Подставляем переменные в полученное значение
            value="$(substitute_variables "$value")"
            
            # Валидируем путь, если это похоже на путь
            if [[ "$value" =~ ^/ ]]; then
                validate_path "$value" "any" || safe_log WARN "Проблема с путем: $value"
            fi
            
            echo "$value"
        else
            echo "$default"
        fi
    fi
}

# === Получение значения из кэшированной конфигурации ===
config_get() {
    local key="$1"
    local default="${2:-}"
    
    yaml_get_value "$CONFIG_CACHE" "$key" "$default"
}

# === Получение конфигурации модуля ===
config_get_module() {
    local module_name="$1"
    local key="$2"
    local default="${3:-}"
    
    # Сначала пытаемся получить из config секции
    local value
    value="$(config_get "modules.$module_name.config.$key" "")"
    if [[ -n "$value" ]]; then
        echo "$value"
        return 0
    fi
    
    # Если не найдено в config, пытаемся получить из корня модуля
    config_get "modules.$module_name.$key" "$default"
}

# === Получение конфигурации плагина ===
config_get_plugin() {
    local plugin_name="$1"
    local key="$2"
    local default="${3:-}"
    
    # Сначала пытаемся получить из config секции
    local value
    value="$(config_get "plugins.$plugin_name.config.$key" "")"
    if [[ -n "$value" ]]; then
        echo "$value"
        return 0
    fi
    
    # Если не найдено в config, пытаемся получить из корня плагина
    config_get "plugins.$plugin_name.$key" "$default"
}

# === Проверка включенности модуля ===
is_module_enabled() {
    local module_name="$1"
    local enabled
    enabled="$(config_get_module "$module_name" "enabled" "false")"
    [[ "$enabled" == "true" ]]
}

# === Проверка включенности плагина ===
is_plugin_enabled() {
    local plugin_name="$1"
    local enabled
    enabled="$(config_get_plugin "$plugin_name" "enabled" "false")"
    [[ "$enabled" == "true" ]]
}

# === Получение приоритета модуля ===
get_module_priority() {
    local module_name="$1"
    config_get_module "$module_name" "priority" "999"
}

# === Получение приоритета плагина ===
get_plugin_priority() {
    local plugin_name="$1"
    config_get_plugin "$plugin_name" "priority" "999"
}

# === Получение зависимостей модуля ===
get_module_dependencies() {
    local module_name="$1"
    local deps
    deps="$(config_get_module "$module_name" "dependencies" "")"
    
    if [[ -n "$deps" ]]; then
        echo "$deps" | tr ',' ' '
    else
        echo ""
    fi
}

# === Получение зависимостей плагина ===
get_plugin_dependencies() {
    local plugin_name="$1"
    local deps
    deps="$(config_get_plugin "$plugin_name" "dependencies" "")"
    
    if [[ -n "$deps" ]]; then
        echo "$deps" | tr ',' ' '
    else
        echo ""
    fi
}

# === Получение списка всех модулей ===
get_all_modules() {
    local modules=()
    
    if [[ -f "$MODULES_CONFIG" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*$ ]]; then
                modules+=("${BASH_REMATCH[1]}")
            fi
        done < "$MODULES_CONFIG"
    fi
    
    printf '%s\n' "${modules[@]}"
}

# === Получение списка всех плагинов ===
get_all_plugins() {
    local plugins=()
    
    if [[ -f "$PLUGINS_CONFIG" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*$ ]]; then
                plugins+=("${BASH_REMATCH[1]}")
            fi
        done < "$PLUGINS_CONFIG"
    fi
    
    printf '%s\n' "${plugins[@]}"
}

# === Получение списка включенных модулей ===
# === Функции get_enabled_modules, get_enabled_plugins, sort_modules_by_priority, sort_plugins_by_priority ===
# Эти функции определены в installer.sh и используют Python для парсинга YAML
# Здесь мы не переопределяем их

# === Обновление конфигурации ===
config_update() {
    local key="$1"
    local value="$2"
    local file="$3"
    
    if [[ -z "$file" ]]; then
        file="$CONFIG_CACHE"
    fi
    
    # Простое обновление значения в YAML файле
    local temp_file
    temp_file="$(mktemp)"
    
    awk -v key="$key" -v value="$value" '
        BEGIN {
            FS = ":"
            key_parts = split(key, key_array, ".")
            in_section = 0
            current_level = 0
            found = 0
        }
        {
            # Удаляем пробелы в начале строки
            gsub(/^[ \t]+/, "", $0)
            
            # Пропускаем комментарии и пустые строки
            if ($0 ~ /^#/ || $0 == "") {
                print $0
                next
            }
            
            # Определяем уровень вложенности
            level = 0
            while (substr($0, level + 1, 1) == " ") level++
            level = level / 2
            
            # Проверяем, находимся ли мы в нужной секции
            if (level == 0 && $1 ~ /^[a-zA-Z_][a-zA-Z0-9_]*:$/) {
                section = substr($1, 1, length($1) - 1)
                if (section == key_array[1]) {
                    in_section = 1
                    current_level = 0
                } else {
                    in_section = 0
                }
            }
            
            # Если мы в нужной секции и достигли нужного уровня
            if (in_section && level == current_level + 1) {
                current_key = $1
                gsub(/[ \t]*$/, "", current_key)
                
                # Проверяем, является ли это нашим ключом
                if (current_key == key_array[key_parts]) {
                    # Обновляем значение
                    indent = ""
                    for (i = 0; i < level; i++) indent = indent "  "
                    print indent current_key ": " value
                    found = 1
                    next
                }
            }
            
            print $0
        }
        END {
            if (!found) {
                # Если ключ не найден, добавляем его
                print key ": " value
            }
        }
    ' "$file" > "$temp_file"
    
    mv "$temp_file" "$file"
}

# === Валидация конфигурации ===
validate_config() {
    local errors=0
    
    safe_log INFO "Валидация конфигурации..."
    
    # Проверка обязательных полей
    local required_fields=(
        "installer.version"
        "installer.supported_os"
        "installer.requirements.min_ram_mb"
        "installer.requirements.min_disk_gb"
    )
    
    for field in "${required_fields[@]}"; do
        if [[ -z "$(yaml_get_value "$INSTALLER_CONFIG" "$field")" ]]; then
            safe_log ERROR "Отсутствует обязательное поле: $field"
            ((errors++))
        fi
    done
    
    # Проверка модулей
    local modules
    modules="$(get_all_modules)"
    while IFS= read -r module; do
        if [[ -n "$module" ]]; then
            local priority
            priority="$(get_module_priority "$module")"
            if ! [[ "$priority" =~ ^[0-9]+$ ]]; then
                log ERROR "Неверный приоритет модуля $module: $priority"
                ((errors++))
            fi
        fi
    done <<< "$modules"
    
    # Проверка плагинов
    local plugins
    plugins="$(get_all_plugins)"
    while IFS= read -r plugin; do
        if [[ -n "$plugin" ]]; then
            local priority
            priority="$(get_plugin_priority "$plugin")"
            if ! [[ "$priority" =~ ^[0-9]+$ ]]; then
                log ERROR "Неверный приоритет плагина $plugin: $priority"
                ((errors++))
            fi
        fi
    done <<< "$plugins"
    
    if [[ $errors -eq 0 ]]; then
        log OK "Конфигурация валидна"
        return 0
    else
        log ERROR "Найдено $errors ошибок в конфигурации"
        return 1
    fi
}

# === Очистка кэша конфигурации ===
config_cleanup() {
    if [[ -n "$CONFIG_CACHE" && -f "$CONFIG_CACHE" ]]; then
        rm -f "$CONFIG_CACHE"
        log DEBUG "Кэш конфигурации очищен"
    fi
}

# Автоматическая инициализация при загрузке модуля
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Если скрипт запущен напрямую
    config_init "$@"
fi
# При загрузке как модуль НЕ вызываем config_init автоматически
# Инициализация будет вызвана вручную из installer.sh

# === Функция получения констант ===
config_get_constant() {
    local key="$1"
    local default_value="${2:-}"
    
    # Используем единый файл конфигурации
    config_get "constants.$key" "$default_value"
}

# === Универсальная функция для интерактивных запросов ===
ask_and_execute() {
    local module="$1"
    local config_key="$2"
    local description="$3"
    local default_value="$4"
    local function_name="$5"
    local default_text="${6:-Y/n}"
    
    # Проверка обязательных параметров
    if [[ -z "$module" || -z "$config_key" || -z "$description" || -z "$function_name" ]]; then
        log ERROR "ask_and_execute: Недостаточно параметров"
        return 1
    fi
    
    # Интерактивный запрос
    local user_choice
    user_choice="$(config_get_boolean_interactive "$module" "$config_key" "$description" "$default_value" "$default_text")"
    
    if [[ "$user_choice" == "true" ]]; then
        # Проверка существования функции
        if declare -f "$function_name" >/dev/null 2>&1; then
            log INFO "Выполнение: $description"
            if "$function_name"; then
                log OK "Завершено: $description"
            else
                log ERROR "Ошибка выполнения: $description"
                return 1
            fi
        else
            log ERROR "Функция $function_name не найдена"
            return 1
        fi
    else
        log INFO "Пропуск: $description"
    fi
}

# === Экспорт функций ===
# === Интерактивные запросы булевых переменных ===
config_get_boolean_interactive() {
    local module="$1"
    local key="$2"
    local description="$3"
    local default="${4:-true}"
    local default_text="${5:-Y/n}"
    
    # Сначала пытаемся получить значение из конфигурации
    local value
    value="$(config_get_module "$module" "$key" "")"
    
    # Если значение найдено, возвращаем его
    if [[ -n "$value" ]]; then
        echo "$value"
        return 0
    fi
    
    # Проверка NONINTERACTIVE режима
    if [[ -n "${NONINTERACTIVE:-}" ]]; then
        log INFO "Неинтерактивный режим: используем значение по умолчанию для $key"
        echo "$default"
        return 0
    fi
    
    # Если значение не найдено, запрашиваем у пользователя
    local prompt
    if [[ "$default" == "true" ]]; then
        prompt="[${key}: ${default_text}] : "
    else
        prompt="[${key}: ${default_text}] : "
    fi
    
    echo
    echo "❓ $description"
    IFS= read -r -p "$prompt" response
    
    # Обработка ответа
    case "${response,,}" in
        "y"|"yes"|"true"|"1"|"")
            echo "true"
            ;;
        "n"|"no"|"false"|"0")
            echo "false"
            ;;
        *)
            # Если введено неверное значение, используем значение по умолчанию
            echo "$default"
            ;;
    esac
}

# === Интерактивные запросы для плагинов ===
config_get_plugin_boolean_interactive() {
    local plugin="$1"
    local key="$2"
    local description="$3"
    local default="${4:-true}"
    local default_text="${5:-Y/n}"
    
    # Сначала пытаемся получить значение из конфигурации
    local value
    value="$(config_get_plugin "$plugin" "$key" "")"
    
    # Если значение найдено, возвращаем его
    if [[ -n "$value" ]]; then
        echo "$value"
        return 0
    fi
    
    # Если значение не найдено, запрашиваем у пользователя
    local prompt
    if [[ "$default" == "true" ]]; then
        prompt="[${key}: ${default_text}] : "
    else
        prompt="[${key}: ${default_text}] : "
    fi
    
    echo
    echo "❓ $description"
    IFS= read -r -p "$prompt" response
    
    # Обработка ответа
    case "${response,,}" in
        "y"|"yes"|"true"|"1"|"")
            echo "true"
            ;;
        "n"|"no"|"false"|"0")
            echo "false"
            ;;
        *)
            # Если введено неверное значение, используем значение по умолчанию
            echo "$default"
            ;;
    esac
}

export -f config_init config_get config_get_module config_get_plugin config_get_constant
export -f is_module_enabled is_plugin_enabled get_module_priority get_plugin_priority
export -f get_module_dependencies get_plugin_dependencies get_all_modules get_all_plugins
export -f config_update validate_config config_cleanup yaml_get_value substitute_variables validate_path
export -f config_get_boolean_interactive config_get_plugin_boolean_interactive
export -f ask_and_execute
