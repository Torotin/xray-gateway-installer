#!/usr/bin/env bash

# === Компонент обновлений Xray ===
# Версия: 2.0.0
# Автор: Xray Gateway Installer Team

# === Инициализация компонента ===
xray_updates_init() {
    log INFO "Инициализация компонента обновлений Xray"
    
    # Получение переменных из конфигурации
    XRAY_USER="$(config_get_constant "xray_user" "xray")"
    XRAY_GROUP="$(config_get_constant "xray_group" "xray")"
    XRAY_SERVICE="$(config_get_constant "xray_service" "xray")"
    XRAY_BINARY="$(config_get_constant "xray_binary" "/usr/local/bin/xray")"
    XRAY_DAT_PATH="$(config_get_constant "xray_dat_path" "/opt/xray/dat")"
    
    # Переменные компонента
    declare -g XRAY_UPDATES_DIR="/opt/xray/updates"
    declare -g XRAY_CORE_UPDATE_SCRIPT="$XRAY_UPDATES_DIR/update-xray-core.sh"
    declare -g XRAY_GEO_UPDATE_SCRIPT="$XRAY_UPDATES_DIR/update-geo-data.sh"
    declare -g XRAY_UPDATE_TEMPLATES_DIR="$SCRIPT_DIR/templates"
    
    log OK "Компонент обновлений Xray инициализирован"
    return 0
}

# === Создание скрипта обновления Xray Core ===
xray_updates_create_core_script() {
    log INFO "Создание скрипта обновления Xray Core"
    
    # Получение переменных если не определены
    local xray_user="${XRAY_USER:-xray}"
    local xray_group="${XRAY_GROUP:-xray}"
    local xray_service="${XRAY_SERVICE:-xray}"
    local xray_binary="${XRAY_BINARY:-/usr/local/bin/xray}"
    
    # Создание директории для скриптов обновления
    mkdir -p "$XRAY_UPDATES_DIR"
    chown "$xray_user:$xray_group" "$XRAY_UPDATES_DIR" 2>/dev/null || true
    chmod 755 "$XRAY_UPDATES_DIR"
    
    # Замена переменных в шаблоне
    sed -e "s|__XRAY_SERVICE__|$xray_service|g" \
        -e "s|__XRAY_BINARY__|$xray_binary|g" \
        -e "s|__XRAY_USER__|$xray_user|g" \
        -e "s|__XRAY_GROUP__|$xray_group|g" \
        -e "s|__LOG_FILE__|/opt/xray/logs/update-xray-core.log|g" \
        "$XRAY_UPDATE_TEMPLATES_DIR/update-xray-core.template.sh" > "$XRAY_CORE_UPDATE_SCRIPT"
    
    # Установка прав доступа
    chmod +x "$XRAY_CORE_UPDATE_SCRIPT"
    chown "$xray_user:$xray_group" "$XRAY_CORE_UPDATE_SCRIPT" 2>/dev/null || true
    
    log OK "Скрипт обновления Xray Core создан: $XRAY_CORE_UPDATE_SCRIPT"
}

# === Создание скрипта обновления Geo данных ===
xray_updates_create_geo_script() {
    log INFO "Создание скрипта обновления Geo данных"
    
    # Получение переменных если не определены
    local xray_user="${XRAY_USER:-xray}"
    local xray_group="${XRAY_GROUP:-xray}"
    local xray_service="${XRAY_SERVICE:-xray}"
    local xray_dat_path="${XRAY_DAT_PATH:-/opt/xray/dat}"
    
    # Создание директории для скриптов обновления
    mkdir -p "$XRAY_UPDATES_DIR"
    chown "$xray_user:$xray_group" "$XRAY_UPDATES_DIR" 2>/dev/null || true
    chmod 755 "$XRAY_UPDATES_DIR"
    
    # Замена переменных в шаблоне
    sed -e "s|__XRAY_SERVICE__|$xray_service|g" \
        -e "s|__XRAY_DAT_PATH__|$xray_dat_path|g" \
        -e "s|__XRAY_USER__|$xray_user|g" \
        -e "s|__XRAY_GROUP__|$xray_group|g" \
        -e "s|__LOG_FILE__|/opt/xray/logs/update-geo-data.log|g" \
        "$XRAY_UPDATE_TEMPLATES_DIR/update-geo-data.template.sh" > "$XRAY_GEO_UPDATE_SCRIPT"
    
    # Установка прав доступа
    chmod +x "$XRAY_GEO_UPDATE_SCRIPT"
    chown "$xray_user:$xray_group" "$XRAY_GEO_UPDATE_SCRIPT" 2>/dev/null || true
    
    log OK "Скрипт обновления Geo данных создан: $XRAY_GEO_UPDATE_SCRIPT"
}

# === Создание всех скриптов обновления ===
xray_updates_create_scripts() {
    log INFO "Создание скриптов обновления Xray"
    
    xray_updates_create_core_script
    xray_updates_create_geo_script
    
    # Настройка cron задач
    xray_updates_setup_cron
    
    log OK "Все скрипты обновления созданы"
}

# === Получение текущего crontab ===
xray_updates_get_crontab() {
    command -v crontab >/dev/null 2>&1 || return 0
    crontab -l 2>/dev/null || true
}

# === Запись crontab c безопасной очисткой ===
xray_updates_write_crontab() {
    local content="${1:-}"

    if [[ -z "${content//[[:space:]]/}" ]]; then
        crontab -r 2>/dev/null || true
        return 0
    fi

    printf '%s\n' "$content" | crontab -
}

# === Очистка update-задач Xray из crontab ===
xray_updates_filter_crontab() {
    local content="${1:-}"

    printf '%s\n' "$content" | grep -v -E \
        '(^|[[:space:]])/opt/xray/updates/update-xray-core\.sh([[:space:]]|$)|(^|[[:space:]])/opt/xray/updates/update-geo-data\.sh([[:space:]]|$)' || true
}

# === Настройка cron задач ===
xray_updates_setup_cron() {
    log INFO "Настройка cron задач для обновлений Xray"

    if ! command -v crontab >/dev/null 2>&1; then
        log WARN "crontab не найден, cron-задачи обновлений Xray пропущены"
        return 0
    fi

    # Настройка cron для Xray Core (еженедельно по воскресеньям в 3:00)
    local core_cron_schedule="0 3 * * 0"
    log INFO "Настройка cron для обновления Xray Core: $core_cron_schedule"

    # Настройка cron для Geo данных (ежедневно в 4:00)
    local geo_cron_schedule="0 4 * * *"
    log INFO "Настройка cron для обновления Geo данных: $geo_cron_schedule"

    local current_crontab=""
    local filtered_crontab=""
    local new_crontab=""
    current_crontab="$(xray_updates_get_crontab)"
    filtered_crontab="$(xray_updates_filter_crontab "$current_crontab")"

    new_crontab="$filtered_crontab"
    if [[ -n "${new_crontab//[[:space:]]/}" ]]; then
        new_crontab="${new_crontab}"$'\n'
    fi

    new_crontab+="$core_cron_schedule $XRAY_CORE_UPDATE_SCRIPT >> /opt/xray/logs/update-xray-core.log 2>&1"$'\n'
    new_crontab+="$geo_cron_schedule $XRAY_GEO_UPDATE_SCRIPT >> /opt/xray/logs/update-geo-data.log 2>&1"

    xray_updates_write_crontab "$new_crontab"

    log OK "Cron задачи для обновлений Xray настроены"
}

# === Первичная загрузка Geo данных ===
xray_updates_initial_geo_load() {
    log INFO "Первичная загрузка Geo данных"
    
    # Получение переменных если не определены
    local xray_dat_path="${XRAY_DAT_PATH:-/opt/xray/dat}"
    local xray_user="${XRAY_USER:-xray}"
    local xray_group="${XRAY_GROUP:-xray}"
    
    # Создание директории для Geo данных
    mkdir -p "$xray_dat_path"
    if id -u "$xray_user" >/dev/null 2>&1; then
        chown "$xray_user:$xray_group" "$xray_dat_path"
    fi
    
    # Запуск скрипта обновления Geo данных
    if [[ -f "$XRAY_GEO_UPDATE_SCRIPT" ]]; then
        log INFO "Запуск первичной загрузки Geo данных"
        if bash "$XRAY_GEO_UPDATE_SCRIPT"; then
            log OK "Первичная загрузка Geo данных завершена"
        else
            log WARN "Ошибка при первичной загрузке Geo данных"
        fi
    else
        log WARN "Скрипт обновления Geo данных не найден, пропускаем первичную загрузку"
    fi
}

# === Удаление скриптов обновления ===
xray_updates_remove_scripts() {
    log INFO "Удаление скриптов обновления Xray"
    
    # Удаление cron задач
    xray_updates_remove_cron
    
    # Удаление скриптов
    rm -f "$XRAY_CORE_UPDATE_SCRIPT" "$XRAY_GEO_UPDATE_SCRIPT"
    
    # Удаление директории, если пуста
    if [[ -d "$XRAY_UPDATES_DIR" ]] && [[ -z "$(ls -A "$XRAY_UPDATES_DIR" 2>/dev/null)" ]]; then
        rmdir "$XRAY_UPDATES_DIR"
    fi
    
    log OK "Скрипты обновления удалены"
}

# === Удаление cron задач ===
xray_updates_remove_cron() {
    log INFO "Удаление cron задач обновлений Xray"

    if ! command -v crontab >/dev/null 2>&1; then
        log INFO "crontab не найден, удаление cron-задач не требуется"
        return 0
    fi

    local current_crontab=""
    local filtered_crontab=""
    current_crontab="$(xray_updates_get_crontab)"
    filtered_crontab="$(xray_updates_filter_crontab "$current_crontab")"
    xray_updates_write_crontab "$filtered_crontab"

    log OK "Cron задачи обновлений Xray удалены"
}

# === Запуск обновления Xray Core ===
xray_updates_update_core() {
    log INFO "Запуск обновления Xray Core"
    
    if [[ -f "$XRAY_CORE_UPDATE_SCRIPT" ]]; then
        if bash "$XRAY_CORE_UPDATE_SCRIPT"; then
            log OK "Обновление Xray Core завершено"
        else
            log ERROR "Ошибка при обновлении Xray Core"
            return 1
        fi
    else
        log ERROR "Скрипт обновления Xray Core не найден: $XRAY_CORE_UPDATE_SCRIPT"
        return 1
    fi
}

# === Запуск обновления Geo данных ===
xray_updates_update_geo() {
    log INFO "Запуск обновления Geo данных"
    
    if [[ -f "$XRAY_GEO_UPDATE_SCRIPT" ]]; then
        if bash "$XRAY_GEO_UPDATE_SCRIPT"; then
            log OK "Обновление Geo данных завершено"
        else
            log ERROR "Ошибка при обновлении Geo данных"
            return 1
        fi
    else
        log ERROR "Скрипт обновления Geo данных не найден: $XRAY_GEO_UPDATE_SCRIPT"
        return 1
    fi
}

# === Статус скриптов обновления ===
xray_updates_status() {
    echo "Скрипты обновления Xray:"
    echo "  └─ Xray Core: $([ -f "$XRAY_CORE_UPDATE_SCRIPT" ] && echo "создан" || echo "не найден")"
    echo "  └─ Geo данные: $([ -f "$XRAY_GEO_UPDATE_SCRIPT" ] && echo "создан" || echo "не найден")"
}

# === Экспорт функций ===
export -f xray_updates_init \
         xray_updates_create_core_script \
         xray_updates_create_geo_script \
         xray_updates_create_scripts \
         xray_updates_get_crontab \
         xray_updates_write_crontab \
         xray_updates_filter_crontab \
         xray_updates_setup_cron \
         xray_updates_initial_geo_load \
         xray_updates_remove_scripts \
         xray_updates_remove_cron \
         xray_updates_update_core \
         xray_updates_update_geo \
         xray_updates_status

# Автоматическая инициализация при загрузке компонента
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Если скрипт запущен напрямую
    xray_updates_init "$@"
else
    # Если скрипт загружен как компонент
    xray_updates_init
fi
