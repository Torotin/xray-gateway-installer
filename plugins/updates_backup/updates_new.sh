#!/usr/bin/env bash

# === Плагин автообновлений Xray Gateway Installer ===
# Версия: 2.1.0 (Без логики Xray)
# Автор: Xray Gateway Installer Team

# Глобальные переменные плагина
declare -g UPDATES_SCRIPT_DIR="/opt/xray/updates"
declare -g GEO_DATA_UPDATE_SCRIPT=""

# === Инициализация плагина ===
plugin_updates_init() {
    log INFO "Инициализация плагина автообновлений"
    
    # Получение пользователя и группы Xray
    XRAY_USER="$(config_get_constant "xray_user" "xray")"
    XRAY_GROUP="$(config_get_constant "xray_group" "xray")"
    XRAY_DATA_PATH="$(config_get_constant "xray_dat_path" "/opt/xray/dat")"
    
    # Проверка существования пользователя
    if id -u "$XRAY_USER" >/dev/null 2>&1; then
        # Создание директории для скриптов обновления
        mkdir -p "$UPDATES_SCRIPT_DIR"
        chown "$XRAY_USER:$XRAY_GROUP" "$UPDATES_SCRIPT_DIR" 2>/dev/null || true
        chmod 755 "$UPDATES_SCRIPT_DIR"
    else
        # Создание директории с root владельцем если пользователь не существует
        mkdir -p "$UPDATES_SCRIPT_DIR"
        chown root:root "$UPDATES_SCRIPT_DIR" 2>/dev/null || true
        chmod 755 "$UPDATES_SCRIPT_DIR"
        log WARN "Пользователь $XRAY_USER не найден, директория создана с root владельцем"
    fi
    
    # Путь к скрипту обновления Geo данных
    GEO_DATA_UPDATE_SCRIPT="$UPDATES_SCRIPT_DIR/update-geo-data.sh"
    
    log OK "Плагин автообновлений инициализирован"
}

# === Выполнение плагина ===
plugin_updates_execute() {
    local action="$1"
    shift
    local args=("$@")
    
    case "$action" in
        "install")
            updates_install "${args[@]}"
            ;;
        "uninstall")
            updates_uninstall "${args[@]}"
            ;;
        "status")
            updates_status "${args[@]}"
            ;;
        "update")
            updates_run "${args[@]}"
            ;;
        *)
            log ERROR "Неизвестное действие: $action"
            return 1
            ;;
    esac
}

# === Проверка статуса скриптов ===
updates_check_scripts() {
    log INFO "Проверка скриптов обновления"
    
    if [[ -f "$GEO_DATA_UPDATE_SCRIPT" ]]; then
        log OK "Скрипт обновления Geo данных найден: $GEO_DATA_UPDATE_SCRIPT"
    else
        log WARN "Скрипт обновления Geo данных не найден: $GEO_DATA_UPDATE_SCRIPT"
    fi
    
    # Проверка cron задач
    if crontab -l 2>/dev/null | grep -q "update-geo-data.sh"; then
        log OK "Cron задача для обновления Geo данных настроена"
    else
        log WARN "Cron задача для обновления Geo данных не настроена"
    fi
}

# === Зависимости плагина ===
plugin_updates_dependencies() {
    echo "xray"
}

# === Информация о плагине ===
plugin_updates_info() {
    echo "Плагин автообновлений Xray Gateway Installer"
    echo "Версия: 2.1.0"
    echo "Описание: Автоматическое обновление Geo данных"
    echo "Зависимости: xray"
}

# === Установка плагина ===
updates_install() {
    log SEP
    log TITLE "Установка плагина автообновлений"
    
    # Инициализация конфигурации если не была выполнена
    if [[ -z "${CONFIG_CACHE:-}" ]]; then
        config_init
    fi
    
    # Инициализация плагина если не была выполнена
    if [[ -z "${GEO_DATA_UPDATE_SCRIPT:-}" ]]; then
        plugin_updates_init
    fi
    
    # Создание скрипта обновления Geo данных
    local geo_data_enabled
    geo_data_enabled="$(config_get_plugin_boolean_interactive "updates" "geo_data.enabled" "Включить обновления Geo данных (рекомендуется)?" "true" "Y/n")"
    if [[ "$geo_data_enabled" == "true" ]]; then
        updates_create_geo_data_script
        updates_setup_geo_data_cron
    fi
    
    log OK "Плагин автообновлений установлен"
}

# === Удаление плагина ===
updates_uninstall() {
    log SEP
    log TITLE "Удаление плагина автообновлений"
    
    # Удаление скриптов
    rm -f "$GEO_DATA_UPDATE_SCRIPT"
    
    # Удаление cron задач
    updates_remove_cron_tasks
    
    # Удаление директории, если пуста
    if [[ -d "$UPDATES_SCRIPT_DIR" ]] && [[ -z "$(ls -A "$UPDATES_SCRIPT_DIR" 2>/dev/null)" ]]; then
        rmdir "$UPDATES_SCRIPT_DIR"
    fi
    
    log OK "Плагин автообновлений удален"
}

# === Статус плагина ===
updates_status() {
    log SEP
    log TITLE "Статус плагина автообновлений"
    
    echo "Скрипт обновления Geo данных: ${GEO_DATA_UPDATE_SCRIPT:-не создан}"
    echo
    echo "Cron задачи:"
    crontab -l 2>/dev/null | grep -E "(geo)" || echo "  Не найдены"
}

# === Запуск обновлений ===
updates_run() {
    log SEP
    log TITLE "Запуск обновлений"
    
    # Обновление Geo данных
    if [[ -x "$GEO_DATA_UPDATE_SCRIPT" ]]; then
        log INFO "Обновление Geo данных"
        "$GEO_DATA_UPDATE_SCRIPT"
    else
        log WARN "Скрипт обновления Geo данных не найден или не исполняемый"
    fi
}

# === Создание скрипта обновления Geo данных ===
updates_create_geo_data_script() {
    log INFO "Создание скрипта обновления Geo данных"
    
    cat > "$GEO_DATA_UPDATE_SCRIPT" <<'EOF'
#!/usr/bin/env bash

# === Скрипт обновления GeoIP/GeoSite данных ===
# Автоматически сгенерирован Xray Gateway Installer

set -euo pipefail

# === Функция логирования ===
# Функции логирования для автономного выполнения скрипта
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    case "$level" in
        "INFO")
            echo "[$timestamp] [INFO] $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo "[$timestamp] [WARN] $message" | tee -a "$LOG_FILE" >&2
            ;;
        "ERROR")
            echo "[$timestamp] [ERROR] $message" | tee -a "$LOG_FILE" >&2
            ;;
        "OK")
            echo "[$timestamp] [OK] $message" | tee -a "$LOG_FILE"
            ;;
        *)
            echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Конфигурация
XRAY_SERVICE="__XRAY_SERVICE__"
XRAY_DAT_PATH="__XRAY_DAT_PATH__"
XRAY_USER="__XRAY_USER__"
XRAY_GROUP="__XRAY_GROUP__"
XRAY_DATCHECK_DIR="$XRAY_DAT_PATH/dat-check"
ETAG_DIR="$XRAY_DATCHECK_DIR/etag"
HASH_DIR="$XRAY_DATCHECK_DIR/hash"
LOG_FILE="__LOG_FILE__"

# Блокировка от параллельных запусков
LOCK_FILE="$XRAY_DATCHECK_DIR/.lock"

# Источники данных (расширенный список)
declare -A DATA_SOURCES=(
    ["geoip_antifilter.dat"]="https://github.com/Skrill0/AntiFilter-IP/releases/latest/download/geoip.dat"
    ["geosite_antifilter.dat"]="https://github.com/Skrill0/AntiFilter-Domains/releases/latest/download/geosite.dat"
    ["geoip_v2fly.dat"]="https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"
    ["geosite_v2fly.dat"]="https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"
    ["geoip_zkeen.dat"]="https://github.com/jameszeroX/zkeen-ip/releases/latest/download/zkeenip.dat"
    ["geosite_zkeen.dat"]="https://github.com/jameszeroX/zkeen-domains/releases/latest/download/zkeen.dat"
    ["geoip_antizapret.dat"]="https://github.com/savely-krasovsky/antizapret-sing-box/releases/latest/download/geoip.db"
    ["geosite_antizapret.dat"]="https://github.com/savely-krasovsky/antizapret-sing-box/releases/latest/download/geosite.db"
    ["geoip_russia-blocked.dat"]="https://raw.githubusercontent.com/runetfreedom/russia-blocked-geoip/release/geoip.dat"
    ["geosite_russia-blocked.dat"]="https://raw.githubusercontent.com/runetfreedom/russia-blocked-geosite/release/geosite.dat"
)

# Создание необходимых директорий
create_directories() {
    mkdir -p "$XRAY_DAT_PATH" "$ETAG_DIR" "$HASH_DIR" "$XRAY_DATCHECK_DIR"
    if id -u "$XRAY_USER" >/dev/null 2>&1; then
        chown -R "$XRAY_USER:$XRAY_GROUP" "$XRAY_DAT_PATH"
    fi
}

# Блокировка
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid
        pid="$(cat "$LOCK_FILE" 2>/dev/null || echo "")"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log WARN "Другой экземпляр уже запущен; завершение"
            exit 0
        fi
    fi
    echo $$ > "$LOCK_FILE"
}

# Освобождение блокировки
release_lock() {
    rm -f "$LOCK_FILE"
}

# Очистка при выходе
cleanup() {
    release_lock
    rm -rf "$temp_dir" 2>/dev/null || true
}

# Получение ETag
get_etag() {
    local url="$1"
    curl -sI "$url" | grep -i "etag:" | cut -d'"' -f2 2>/dev/null || echo ""
}

# Получение хеша файла
get_file_hash() {
    local file="$1"
    if [[ -f "$file" ]]; then
        sha256sum "$file" | cut -d' ' -f1 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Обновление файла данных
update_data_file() {
    local filename="$1"
    local url="$2"
    local filepath="$XRAY_DAT_PATH/$filename"
    local etag_file="$ETAG_DIR/$filename.etag"
    local hash_file="$HASH_DIR/$filename.hash"
    
    log INFO "Проверка обновлений для $filename"
    
    # Получение текущего ETag
    local current_etag
    current_etag="$(get_etag "$url")"
    
    # Получение сохраненного ETag
    local saved_etag
    saved_etag="$(cat "$etag_file" 2>/dev/null || echo "")"
    
    # Получение текущего хеша файла
    local current_hash
    current_hash="$(get_file_hash "$filepath")"
    
    # Получение сохраненного хеша
    local saved_hash
    saved_hash="$(cat "$hash_file" 2>/dev/null || echo "")"
    
    # Проверка необходимости обновления
    if [[ "$current_etag" == "$saved_etag" && "$current_hash" == "$saved_hash" && -f "$filepath" ]]; then
        log INFO "ПРОПУЩЕНО: $filename — ETag и хеш совпадают"
        return 0
    fi
    
    # Загрузка файла
    log INFO "Загрузка $filename"
    if curl -fsSL -o "$filepath" "$url"; then
        # Сохранение ETag и хеша
        echo "$current_etag" > "$etag_file"
        get_file_hash "$filepath" > "$hash_file"
        
        # Установка прав доступа
        if id -u "$XRAY_USER" >/dev/null 2>&1; then
            chown "$XRAY_USER:$XRAY_GROUP" "$filepath"
        fi
        chmod 644 "$filepath"
        
        log OK "ОБНОВЛЕНО: $filename"
        return 1
    else
        log ERROR "Ошибка загрузки $filename"
        return 0
    fi
}

# Основная функция
main() {
    log INFO "Проверка обновлений Geo данных"
    
    # Создание директорий
    create_directories
    
    # Блокировка
    acquire_lock
    
    # Установка обработчика очистки
    trap cleanup EXIT
    
    local updated=0
    
    # Обновление всех файлов данных
    for filename in "${!DATA_SOURCES[@]}"; do
        if update_data_file "$filename" "${DATA_SOURCES[$filename]}"; then
            updated=1
        fi
    done
    
    # Перезапуск Xray при наличии обновлений
    if [[ $updated -eq 1 ]]; then
        log INFO "Перезапуск сервиса $XRAY_SERVICE"
        if command -v systemctl >/dev/null 2>&1; then
            # Проверяем, существует ли сервис
            if systemctl list-unit-files "$XRAY_SERVICE.service" >/dev/null 2>&1; then
                if systemctl is-active --quiet "$XRAY_SERVICE" 2>/dev/null; then
                    if systemctl restart "$XRAY_SERVICE"; then
                        log OK "Обновление завершено, сервис перезапущен"
                    else
                        log ERROR "Ошибка при перезапуске сервиса $XRAY_SERVICE"
                    fi
                else
                    log INFO "Сервис $XRAY_SERVICE не запущен, запускаю..."
                    if systemctl start "$XRAY_SERVICE"; then
                        log OK "Сервис $XRAY_SERVICE запущен"
                    else
                        log WARN "Не удалось запустить сервис $XRAY_SERVICE"
                    fi
                fi
            else
                log WARN "Сервис $XRAY_SERVICE не найден в systemd"
            fi
        else
            log WARN "systemctl недоступен — пропускаю перезапуск"
        fi
    else
        log INFO "Все файлы актуальны. Перезапуск не требуется"
    fi
}

trap cleanup EXIT
main "$@"
EOF

    # Замена переменных в скрипте
    sed -i -e "s|__XRAY_SERVICE__|xray|g" \
           -e "s|__XRAY_DAT_PATH__|$XRAY_DATA_PATH|g" \
           -e "s|__XRAY_USER__|$XRAY_USER|g" \
           -e "s|__XRAY_GROUP__|$XRAY_GROUP|g" \
           -e "s|__LOG_FILE__|/opt/xray/logs/update-geo-data.log|g" \
           "$GEO_DATA_UPDATE_SCRIPT"
    
    # Установка прав доступа
    chmod +x "$GEO_DATA_UPDATE_SCRIPT"
    if id -u "$XRAY_USER" >/dev/null 2>&1; then
        chown "$XRAY_USER:$XRAY_GROUP" "$GEO_DATA_UPDATE_SCRIPT"
    fi
    
    log OK "Скрипт обновления Geo данных создан: $GEO_DATA_UPDATE_SCRIPT"
}

# === Настройка cron для Geo данных ===
updates_setup_geo_data_cron() {
    local cron_schedule
    cron_schedule="$(config_get_plugin "updates" "geo_data.cron_schedule" "0 4 * * *")"
    
    log INFO "Настройка cron для обновления Geo данных: $cron_schedule"
    
    # Удаление существующих задач
    crontab -l 2>/dev/null | grep -v "$GEO_DATA_UPDATE_SCRIPT" | crontab - 2>/dev/null || true
    
    # Добавление новой задачи
    {
        crontab -l 2>/dev/null | grep -v "SHELL=" | grep -v "PATH=" | grep -v "$GEO_DATA_UPDATE_SCRIPT" || true
        echo "$cron_schedule $GEO_DATA_UPDATE_SCRIPT >> $LOG_FILE 2>&1"
    } | crontab -
    
    log OK "Cron задача для Geo данных настроена"
}

# === Удаление cron задач ===
updates_remove_cron_tasks() {
    log INFO "Удаление cron задач автообновлений"
    
    # Удаление всех задач, связанных с обновлениями
    crontab -l 2>/dev/null | grep -v -E "(update-|xray|geo)" | crontab - 2>/dev/null || true
    
    log OK "Cron задачи удалены"
}

# === Экспорт функций ===
export -f updates_create_geo_data_script \
         updates_setup_geo_data_cron \
         updates_remove_cron_tasks

# Автоматическая инициализация при загрузке плагина
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Если скрипт запущен напрямую
    plugin_updates_init "$@"
else
    # Если скрипт загружен как плагин
    plugin_updates_init
fi
