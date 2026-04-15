#!/usr/bin/env bash

# === Менеджер плагинов Xray Gateway Installer ===
# Версия: 2.0.0
# Автор: Xray Gateway Installer Team

# Глобальные переменные
declare -g PLUGINS_DIR="${SCRIPT_DIR:-/opt/xray-installer}/plugins"
declare -g LOADED_PLUGINS=()
declare -g PLUGIN_EXECUTION_ORDER=()

plugin_dir_is_loadable() {
    local plugin_name="$1"
    local plugin_file="$PLUGINS_DIR/$plugin_name/${plugin_name}.sh"
    [[ -f "$plugin_file" ]] || return 1

    grep -q "plugin_${plugin_name}_execute()" "$plugin_file"
}

discover_available_plugins() {
    local plugin_dirs=()
    local plugin_dir

    if [[ ! -d "$PLUGINS_DIR" ]]; then
        return 0
    fi

    while IFS= read -r -d '' plugin_dir; do
        local plugin_name
        plugin_name="$(basename "$plugin_dir")"
        if plugin_dir_is_loadable "$plugin_name"; then
            plugin_dirs+=("$plugin_name")
        fi
    done < <(find "$PLUGINS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

    printf '%s\n' "${plugin_dirs[@]}"
}

# === Инициализация менеджера плагинов ===
plugin_manager_init() {
    # Инициализация логирования для модуля ядра
    core_logger_init "plugin_manager" "_logs" "append"
    
    local base_dir="${1:-$SCRIPT_DIR}"
    PLUGINS_DIR="$base_dir/plugins"
    
    # Проверка существования директории плагинов
    if [[ ! -d "$PLUGINS_DIR" ]]; then
        log ERROR "Директория плагинов не найдена: $PLUGINS_DIR"
        return 1
    fi
    
    log INFO "Менеджер плагинов инициализирован"
    log DEBUG "Директория плагинов: $PLUGINS_DIR"
}

# === Загрузка плагина ===
load_plugin() {
    local plugin_name="$1"
    local plugin_file="$PLUGINS_DIR/$plugin_name/${plugin_name}.sh"
    
    # Проверка существования файла плагина
    if [[ ! -f "$plugin_file" ]]; then
        log ERROR "Файл плагина не найден: $plugin_file"
        return 1
    fi
    
    # Проверка, не загружен ли уже плагин
    if [[ " ${LOADED_PLUGINS[@]} " =~ " $plugin_name " ]]; then
        log WARN "Плагин $plugin_name уже загружен"
        return 0
    fi
    
    # Загрузка плагина
    if source "$plugin_file"; then
        LOADED_PLUGINS+=("$plugin_name")
        log OK "Плагин $plugin_name загружен"
        return 0
    else
        log ERROR "Ошибка загрузки плагина: $plugin_name"
        return 1
    fi
}

# === Получение списка включенных плагинов ===
get_enabled_plugins() {
    local enabled_plugins=()
    local config_file="$SCRIPT_DIR/config/unified.yaml"
    local plugin

    while IFS= read -r plugin; do
        [[ -z "$plugin" ]] && continue

        if [[ -f "$config_file" ]]; then
            local enabled
            enabled="$(yq -r ".plugins.${plugin}.enabled.value" "$config_file" 2>/dev/null || echo "true")"
            if [[ "$enabled" != "true" ]]; then
                log DEBUG "Плагин $plugin отключен в конфигурации"
                continue
            fi
        fi

        enabled_plugins+=("$plugin")
    done < <(discover_available_plugins)

    printf '%s\n' "${enabled_plugins[@]}" | xargs
}

# === Загрузка всех включенных плагинов ===
load_all_plugins() {
    local enabled_plugins
    
    # Проверяем, доступна ли функция get_enabled_plugins
    if declare -f get_enabled_plugins >/dev/null 2>&1; then
        enabled_plugins="$(get_enabled_plugins)"
    else
        log WARN "Функция get_enabled_plugins недоступна, загружаем все плагины"
        enabled_plugins="$(discover_available_plugins | xargs)"
    fi
    
    # Сортируем по приоритету
    local sorted_plugins
    if declare -f sort_plugins_by_priority >/dev/null 2>&1; then
        sorted_plugins="$(sort_plugins_by_priority "$enabled_plugins")"
    else
        sorted_plugins="$enabled_plugins"
    fi
    
    # Загружаем плагины в порядке приоритета
    local plugins_array=($sorted_plugins)
    for plugin in "${plugins_array[@]}"; do
        if [[ -n "$plugin" ]]; then
            load_plugin "$plugin"
        fi
    done
    
    log INFO "Загружено ${#LOADED_PLUGINS[@]} плагинов: ${LOADED_PLUGINS[*]}"
}

# === Выполнение функции плагина ===
execute_plugin_function() {
    local plugin_name="$1"
    local function_name="$2"
    shift 2
    local args=("$@")
    
    # Проверка, загружен ли плагин
    if [[ ! " ${LOADED_PLUGINS[@]} " =~ " $plugin_name " ]]; then
        log ERROR "Плагин $plugin_name не загружен"
        return 1
    fi
    
    # Проверка существования функции
    if ! declare -f "plugin_${plugin_name}_${function_name}" >/dev/null 2>&1; then
        log ERROR "Функция plugin_${plugin_name}_${function_name} не найдена"
        return 1
    fi
    
    # Выполнение функции
    log DEBUG "Выполнение функции: plugin_${plugin_name}_${function_name}"
    "plugin_${plugin_name}_${function_name}" "${args[@]}"
}

# === Инициализация всех плагинов ===
init_all_plugins() {
    log INFO "Инициализация всех плагинов..."
    
    for plugin in "${LOADED_PLUGINS[@]}"; do
        log DEBUG "Инициализация плагина: $plugin"
        execute_plugin_function "$plugin" "init" || {
            log ERROR "Ошибка инициализации плагина: $plugin"
            return 1
        }
    done
    
    log OK "Все плагины инициализированы"
}

# === Выполнение всех плагинов ===
execute_all_plugins() {
    local action="$1"
    shift
    local args=("$@")
    
    log INFO "Выполнение плагинов для действия: $action"
    
    # Определяем порядок выполнения на основе зависимостей
    determine_execution_order
    
    # Выполняем плагины в правильном порядке
    for plugin in "${PLUGIN_EXECUTION_ORDER[@]}"; do
        log DEBUG "Выполнение плагина: $plugin"
        execute_plugin_function "$plugin" "execute" "$action" "${args[@]}" || {
            log ERROR "Ошибка выполнения плагина: $plugin"
            return 1
        }
    done
    
    log OK "Все плагины выполнены"
}

# === Получение зависимостей плагина ===
get_plugin_dependencies() {
    local plugin_name="$1"
    
    # Вызываем функцию зависимостей плагина
    if declare -f "plugin_${plugin_name}_dependencies" >/dev/null 2>&1; then
        "plugin_${plugin_name}_dependencies"
    else
        echo ""
    fi
}

# === Определение порядка выполнения плагинов ===
determine_execution_order() {
    local plugins=("${LOADED_PLUGINS[@]}")
    local ordered=()
    local remaining=("${plugins[@]}")
    
    log DEBUG "Начальная сортировка плагинов: ${plugins[*]}"
    
    # Простой алгоритм топологической сортировки
    while [[ ${#remaining[@]} -gt 0 ]]; do
        local added=false
        
        for i in "${!remaining[@]}"; do
            local plugin="${remaining[$i]}"
            local deps
            deps="$(get_plugin_dependencies "$plugin")"
            
            log DEBUG "Плагин $plugin, зависимости: '$deps'"
            
            # Проверяем, выполнены ли все зависимости
            local deps_satisfied=true
            for dep in $deps; do
                # Проверяем, является ли зависимость модулем или плагином
                local dep_satisfied=false
                
                # Если зависимость уже в списке выполненных плагинов
                if [[ " ${ordered[@]} " =~ " $dep " ]]; then
                    dep_satisfied=true
                # Если зависимость - это модуль (проверяем, что это не плагин)
                elif [[ ! " ${LOADED_PLUGINS[@]} " =~ " $dep " ]]; then
                    # Это модуль, считаем его выполненным
                    dep_satisfied=true
                    log DEBUG "Зависимость $dep - это модуль, считаем выполненным"
                fi
                
                if [[ "$dep_satisfied" == "false" ]]; then
                    deps_satisfied=false
                    log DEBUG "Зависимость $dep не выполнена для $plugin"
                    break
                fi
            done
            
            if [[ "$deps_satisfied" == "true" ]]; then
                ordered+=("$plugin")
                unset 'remaining[$i]'
                remaining=("${remaining[@]}")  # Переиндексируем массив
                added=true
                log DEBUG "Добавлен плагин $plugin в порядок выполнения"
                break
            fi
        done
        
        if [[ "$added" == "false" ]]; then
            log ERROR "Обнаружена циклическая зависимость в плагинах"
            log ERROR "Оставшиеся плагины: ${remaining[*]}"
            return 1
        fi
    done
    
    PLUGIN_EXECUTION_ORDER=("${ordered[@]}")
    log DEBUG "Порядок выполнения плагинов: ${PLUGIN_EXECUTION_ORDER[*]}"
}

# === Получение информации о плагине ===
get_plugin_info() {
    local plugin_name="$1"
    
    # Проверка, загружен ли плагин
    if [[ ! " ${LOADED_PLUGINS[@]} " =~ " $plugin_name " ]]; then
        log ERROR "Плагин $plugin_name не загружен"
        return 1
    fi
    
    # Выполнение функции получения информации
    execute_plugin_function "$plugin_name" "info"
}

# === Получение информации о всех плагинах ===
get_all_plugins_info() {
    log INFO "Информация о загруженных плагинах:"
    
    for plugin in "${LOADED_PLUGINS[@]}"; do
        log INFO "Плагин: $plugin"
        get_plugin_info "$plugin" || log WARN "Не удалось получить информацию о плагине: $plugin"
        log SEP
    done
}

# === Проверка зависимостей плагина ===
check_plugin_dependencies() {
    local plugin_name="$1"
    local deps
    deps="$(get_plugin_dependencies "$plugin_name")"
    
    if [[ -z "$deps" ]]; then
        log DEBUG "Плагин $plugin_name не имеет зависимостей"
        return 0
    fi
    
    log DEBUG "Проверка зависимостей плагина $plugin_name: $deps"
    
    local missing_deps=()
    for dep in $deps; do
        if [[ ! " ${LOADED_PLUGINS[@]} " =~ " $dep " ]]; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log ERROR "Отсутствуют зависимости для плагина $plugin_name: ${missing_deps[*]}"
        return 1
    fi
    
    log DEBUG "Все зависимости плагина $plugin_name удовлетворены"
    return 0
}

# === Валидация плагина ===
validate_plugin() {
    local plugin_name="$1"
    local plugin_file="$PLUGINS_DIR/$plugin_name/${plugin_name}.sh"
    
    # Проверка существования файла
    if [[ ! -f "$plugin_file" ]]; then
        log ERROR "Файл плагина не найден: $plugin_file"
        return 1
    fi
    
    # Проверка обязательных функций
    local required_functions=("init" "execute" "info")
    for func in "${required_functions[@]}"; do
        if ! grep -q "plugin_${plugin_name}_${func}()" "$plugin_file"; then
            log ERROR "Отсутствует обязательная функция: plugin_${plugin_name}_${func}"
            return 1
        fi
    done
    
    # Проверка синтаксиса
    if ! bash -n "$plugin_file"; then
        log ERROR "Синтаксическая ошибка в файле плагина: $plugin_file"
        return 1
    fi
    
    log OK "Плагин $plugin_name валиден"
    return 0
}

# === Валидация всех плагинов ===
validate_all_plugins() {
    local enabled_plugins
    enabled_plugins="$(get_enabled_plugins)"
    local errors=0
    
    log INFO "Валидация всех плагинов..."
    
    while IFS= read -r plugin; do
        if [[ -n "$plugin" ]]; then
            if ! validate_plugin "$plugin"; then
                ((errors++))
            fi
        fi
    done <<< "$enabled_plugins"
    
    if [[ $errors -eq 0 ]]; then
        log OK "Все плагины валидны"
        return 0
    else
        log ERROR "Найдено $errors ошибок в плагинах"
        return 1
    fi
}

# === Очистка плагинов ===
cleanup_plugins() {
    if [[ ${#LOADED_PLUGINS[@]} -eq 0 ]]; then
        log DEBUG "Загруженные плагины отсутствуют, очистка не требуется"
        return 0
    fi

    log INFO "Очистка плагинов..."
    
    # Выполняем cleanup для всех загруженных плагинов
    for plugin in "${LOADED_PLUGINS[@]}"; do
        if declare -f "plugin_${plugin}_cleanup" >/dev/null 2>&1; then
            log DEBUG "Очистка плагина: $plugin"
            execute_plugin_function "$plugin" "cleanup" || {
                log WARN "Ошибка очистки плагина: $plugin"
            }
        fi
    done
    
    # Очищаем списки
    LOADED_PLUGINS=()
    PLUGIN_EXECUTION_ORDER=()
    
    log OK "Плагины очищены"
}

# === Получение списка загруженных плагинов ===
get_loaded_plugins() {
    printf '%s\n' "${LOADED_PLUGINS[@]}"
}

# === Проверка загруженности плагина ===
is_plugin_loaded() {
    local plugin_name="$1"
    [[ " ${LOADED_PLUGINS[@]} " =~ " $plugin_name " ]]
}

# === Экспорт функций ===
export -f plugin_manager_init load_plugin load_all_plugins execute_plugin_function
export -f init_all_plugins execute_all_plugins determine_execution_order
export -f get_plugin_dependencies get_plugin_info get_all_plugins_info check_plugin_dependencies
export -f validate_plugin validate_all_plugins cleanup_plugins
export -f get_loaded_plugins is_plugin_loaded

# Автоматическая инициализация при загрузке модуля
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Если скрипт запущен напрямую
    plugin_manager_init "$@"
fi
# При загрузке как модуль НЕ вызываем plugin_manager_init автоматически
# Инициализация будет вызвана вручную из installer.sh
