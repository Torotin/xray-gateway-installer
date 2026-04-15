#!/usr/bin/env bash

# === Плагин автообновлений Xray Gateway Installer ===
# Версия: 2.0.0
# Автор: Xray Gateway Installer Team

# Глобальные переменные плагина
declare -g UPDATES_SCRIPT_DIR="/opt/xray/updates"
declare -g XRAY_CORE_UPDATE_SCRIPT=""
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
    
    # Пути к скриптам обновления
    XRAY_CORE_UPDATE_SCRIPT="$UPDATES_SCRIPT_DIR/update-xray-core.sh"
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
            updates_update "${args[@]}"
            ;;
        *)
            log ERROR "Неизвестное действие для плагина updates: $action"
            return 1
            ;;
    esac
}

# === Статус плагина ===
plugin_updates_status() {
    log INFO "Проверка статуса автообновлений..."
    
    # Проверка наличия скриптов обновления
    if [[ -f "$XRAY_CORE_UPDATE_SCRIPT" ]]; then
        log OK "Скрипт обновления Xray Core найден: $XRAY_CORE_UPDATE_SCRIPT"
    else
        log WARN "Скрипт обновления Xray Core не найден: $XRAY_CORE_UPDATE_SCRIPT"
    fi
    
    if [[ -f "$GEO_DATA_UPDATE_SCRIPT" ]]; then
        log OK "Скрипт обновления Geo данных найден: $GEO_DATA_UPDATE_SCRIPT"
    else
        log WARN "Скрипт обновления Geo данных не найден: $GEO_DATA_UPDATE_SCRIPT"
    fi
    
    # Проверка cron задач
    if crontab -l 2>/dev/null | grep -q "update-xray-core.sh"; then
        log OK "Cron задача для обновления Xray Core настроена"
    else
        log WARN "Cron задача для обновления Xray Core не настроена"
    fi
    
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
    echo "Версия: 2.0.0"
    echo "Описание: Автоматическое обновление Xray Core и Geo данных"
    echo "Зависимости: xray"
}

# === Установка плагина обновлений ===
updates_install() {
    log SEP
    log TITLE "Установка плагина автообновлений"
    
    # Инициализация конфигурации если не была выполнена
    if [[ -z "${CONFIG_CACHE:-}" ]]; then
        config_init
    fi
    
    # Инициализация плагина если не была выполнена
    if [[ -z "${XRAY_CORE_UPDATE_SCRIPT:-}" ]]; then
        plugin_updates_init
    fi
    
    # Создание скрипта обновления Xray Core
    local xray_core_enabled
    xray_core_enabled="$(config_get_plugin_boolean_interactive "updates" "xray_core.enabled" "Включить обновления Xray Core (рекомендуется)?" "true" "Y/n")"
    if [[ "$xray_core_enabled" == "true" ]]; then
        updates_create_xray_core_script
        updates_setup_xray_core_cron
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

# === Удаление плагина обновлений ===
updates_uninstall() {
    log SEP
    log TITLE "Удаление плагина автообновлений"
    
    # Удаление cron задач
    updates_remove_cron_tasks
    
    # Удаление скриптов
    rm -f "$XRAY_CORE_UPDATE_SCRIPT"
    rm -f "$GEO_DATA_UPDATE_SCRIPT"
    
    log OK "Плагин автообновлений удалён"
}

# === Статус плагина обновлений ===
updates_status() {
    log SEP
    log TITLE "Статус плагина автообновлений"
    
    echo "Скрипт обновления Xray Core: ${XRAY_CORE_UPDATE_SCRIPT:-не создан}"
    echo "Скрипт обновления Geo данных: ${GEO_DATA_UPDATE_SCRIPT:-не создан}"
    echo
    echo "Cron задачи:"
    crontab -l 2>/dev/null | grep -E "(xray|geo)" || echo "  Не найдены"
}

# === Обновление ===
updates_update() {
    log SEP
    log TITLE "Принудительное обновление"
    
    if [[ -x "$XRAY_CORE_UPDATE_SCRIPT" ]]; then
        log INFO "Обновление Xray Core"
        "$XRAY_CORE_UPDATE_SCRIPT"
    fi
    
    if [[ -x "$GEO_DATA_UPDATE_SCRIPT" ]]; then
        log INFO "Обновление Geo данных"
        "$GEO_DATA_UPDATE_SCRIPT"
    fi
    
    log OK "Обновление завершено"
}

# === Создание скрипта обновления Xray Core ===
updates_create_xray_core_script() {
    log INFO "Создание скрипта обновления Xray Core"
    
    cat > "$XRAY_CORE_UPDATE_SCRIPT" <<'EOF'
#!/usr/bin/env bash

# === Скрипт обновления Xray Core ===
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
XRAY_SERVICE="xray"
XRAY_BINARY="$(which xray 2>/dev/null || echo '/usr/local/bin/xray')"
XRAY_USER="__XRAY_USER__"
XRAY_GROUP="__XRAY_GROUP__"
LOG_FILE="/opt/xray/logs/update-xray-core.log"

# Получение текущей версии
get_current_version() {
    # Проверяем, существует ли бинарный файл
    if [[ ! -f "$XRAY_BINARY" ]]; then
        log WARN "Xray не установлен: $XRAY_BINARY не найден"
        echo "not_installed"
        return 0
    fi
    
    # Проверяем, можем ли запустить xray
    if ! "$XRAY_BINARY" version >/dev/null 2>&1; then
        log WARN "Не удалось получить версию Xray (возможно, не запущен)"
        echo "unknown"
        return 0
    fi
    
    # Получаем версию
    local version
    local version_output
    version_output="$("$XRAY_BINARY" version 2>/dev/null | head -n1)"
    
    # Пробуем разные способы извлечения версии
    if echo "$version_output" | grep -q "v[0-9]\+\.[0-9]\+\.[0-9]\+"; then
        version="$(echo "$version_output" | grep -o "v[0-9]\+\.[0-9]\+\.[0-9]\+" | head -1)"
    elif echo "$version_output" | grep -q "Xray [0-9]\+\.[0-9]\+\.[0-9]\+"; then
        version="$(echo "$version_output" | grep -o "[0-9]\+\.[0-9]\+\.[0-9]\+" | head -1)"
        version="v$version"
    elif echo "$version_output" | grep -q "[0-9]\+\.[0-9]\+\.[0-9]\+"; then
        version="$(echo "$version_output" | grep -o "[0-9]\+\.[0-9]\+\.[0-9]\+" | head -1)"
        version="v$version"
    fi
    
    if [[ -n "$version" ]]; then
        echo "$version"
    else
        log WARN "Не удалось распарсить версию Xray"
        echo "unknown"
    fi
}

# Получение последней версии
get_latest_version() {
    local api_url="https://api.github.com/repos/XTLS/Xray-core/releases/latest"
    curl -s "$api_url" | jq -r '.tag_name' 2>/dev/null || echo "unknown"
}

# Загрузка и установка новой версии
install_xray_core() {
    local version="$1"
    local arch
    arch="$(uname -m)"
    
    # Определение архитектуры
    case "$arch" in
        x86_64) arch="64" ;;
        aarch64|arm64) arch="arm64-v8a" ;;
        armv7l) arch="arm32-v7a" ;;
        *) log ERROR "Неподдерживаемая архитектура: $arch"; return 1 ;;
    esac
    
    local download_url="https://github.com/XTLS/Xray-core/releases/download/$version/Xray-linux-${arch}.zip"
    local temp_dir
    temp_dir="$(mktemp -d)"
    local zip_file="$temp_dir/xray.zip"
    
    log INFO "Загрузка Xray $version для архитектуры $arch"
    if ! curl -fsSL -o "$zip_file" "$download_url"; then
        log ERROR "Не удалось загрузить Xray $version"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Распаковка
    cd "$temp_dir"
    unzip -q "$zip_file"
    
    # Остановка сервиса
    systemctl stop "$XRAY_SERVICE" 2>/dev/null || true
    
    # Создание резервной копии
    cp "$XRAY_BINARY" "${XRAY_BINARY}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    
    # Установка новой версии
    cp xray "$XRAY_BINARY"
    chmod +x "$XRAY_BINARY"
    if id -u "$XRAY_USER" >/dev/null 2>&1; then
        chown "$XRAY_USER:$XRAY_GROUP" "$XRAY_BINARY"
    fi
    
    # Запуск сервиса
    systemctl start "$XRAY_SERVICE"
    
    # Очистка
    rm -rf "$temp_dir"
    
    log OK "Xray обновлён до версии $version"
}

# Основная функция
main() {
    log INFO "Проверка обновлений Xray Core"
    
    local current_version
    current_version="$(get_current_version)"
    log INFO "Текущая версия: $current_version"
    
    local latest_version
    latest_version="$(get_latest_version)"
    log INFO "Последняя версия: $latest_version"
    
    if [[ "$current_version" == "not_installed" ]]; then
        log INFO "Xray не установлен, будет выполнена первичная установка"
        install_xray_core "$latest_version"
        return 0
    elif [[ "$current_version" == "unknown" ]]; then
        log ERROR "Не удалось определить текущую версию Xray"
        exit 1
    fi
    
    if [[ "$latest_version" == "unknown" ]]; then
        log ERROR "Не удалось получить информацию о последней версии"
        exit 1
    fi
    
    if [[ "$current_version" != "$latest_version" ]]; then
        log INFO "Доступна новая версия: $latest_version (текущая: $current_version)"
        install_xray_core "$latest_version"
    else
        log INFO "Xray уже актуальной версии: $current_version"
    fi
}

main "$@"
EOF
    
    # Подстановка переменных
    sed -i \
        -e "s|__XRAY_USER__|$XRAY_USER|g" \
        -e "s|__XRAY_GROUP__|$XRAY_GROUP|g" \
        "$XRAY_CORE_UPDATE_SCRIPT"
    
    chmod +x "$XRAY_CORE_UPDATE_SCRIPT"
    if id -u "$XRAY_USER" >/dev/null 2>&1; then
        chown "$XRAY_USER:$XRAY_GROUP" "$XRAY_CORE_UPDATE_SCRIPT"
    fi
    
    log OK "Скрипт обновления Xray Core создан: $XRAY_CORE_UPDATE_SCRIPT"
}

# === Создание скрипта обновления Geo данных ===
updates_create_geo_data_script() {
    log INFO "Создание скрипта обновления Geo данных"
    
    cat > "$GEO_DATA_UPDATE_SCRIPT" <<'EOF'
#!/usr/bin/env bash

# === Скрипт обновления GeoIP/GeoSite данных ===
# Автоматически сгенерирован Xray Gateway Installer

set -euo pipefail
umask 022
PATH=/usr/sbin:/usr/bin:/sbin:/bin

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
XRAY_SERVICE="xray"
XRAY_DAT_PATH="__XRAY_DAT_PATH__"
XRAY_USER="__XRAY_USER__"
XRAY_GROUP="__XRAY_GROUP__"
XRAY_DATCHECK_DIR="$XRAY_DAT_PATH/dat-check"
ETAG_DIR="$XRAY_DATCHECK_DIR/etag"
HASH_DIR="$XRAY_DATCHECK_DIR/hash"
LOG_FILE="/opt/xray/logs/update-geo-data.log"

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

# Блокировка от параллельных запусков
setup_lock() {
    mkdir -p "$XRAY_DATCHECK_DIR"
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        log WARN "Другой экземпляр уже запущен; завершение"
        exit 0
    fi
}

# Очистка при выходе
cleanup() {
    [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR:-}" ]] && rm -rf "$TMP_DIR"
    [[ -n "${LOCK_FILE:-}" ]] && rm -f "$LOCK_FILE"
}

# Обновление файла данных
update_data_file() {
    local filename="$1"
    local url="$2"
    local temp_file="$TMP_DIR/$filename"
    local etag_file="$ETAG_DIR/.etag-$filename"
    local hash_file="$HASH_DIR/.hash-$filename"
    local header_file="$TMP_DIR/header-$filename"
    
    local etag
    etag="$(cat "$etag_file" 2>/dev/null || true)"
    
    # Загрузка файла
    local curl_args=(-sS -L --connect-timeout 10 --max-time 60 --retry 3 --retry-all-errors \
                    -w "%{http_code}" -D "$header_file" -o "$temp_file" "$url")
    if [[ -n "${etag:-}" ]]; then
        curl_args+=(-H "If-None-Match: $etag")
    fi
    
    # Выполняем curl и отдельно берём код возврата и http-код
    set +e
    local http_status curl_rc
    http_status="$(curl "${curl_args[@]}")"
    curl_rc=$?
    set -e
    
    if (( curl_rc != 0 )); then
        log WARN "Сетевая ошибка curl (rc=$curl_rc) для $filename"
        rm -f "$temp_file" "$header_file"
        return 1
    fi
    
    # Получение ETag
    local etag_server
    etag_server="$(awk '
        tolower($1)=="etag:"{
            $1="";
            sub(/^[ \t]+/,"");
            gsub(/"/,"");
            sub(/^W\//,"");
            last=$0
        }
        END{ if(length(last)) print last }
    ' "$header_file")"
    
    local old_hash
    old_hash="$(cat "$hash_file" 2>/dev/null || true)"
    
    case "$http_status" in
        200)
            local current_hash
            current_hash="$(sha256sum "$temp_file" 2>/dev/null | cut -d" " -f1 || true)"
            
            if [[ -n "$etag_server" && "$etag_server" == "$etag" && -n "$current_hash" && "$current_hash" == "$old_hash" ]]; then
                log INFO "ПРОПУЩЕНО: $filename — ETag и хеш совпадают"
                rm -f "$temp_file" "$header_file"
                return 1
            fi
            
            if [[ -n "$etag_server" && "$etag_server" == "$etag" && -n "$current_hash" && "$current_hash" != "$old_hash" ]]; then
                log WARN "ETag совпадает, но хеш отличается для $filename — обновляем"
            fi
            
            mv "$temp_file" "$XRAY_DAT_PATH/$filename"
            if [[ -n "${XRAY_USER:-}" && -n "${XRAY_GROUP:-}" ]] && id -u "$XRAY_USER" >/dev/null 2>&1; then
                chown "$XRAY_USER:$XRAY_GROUP" "$XRAY_DAT_PATH/$filename" || true
            fi
            
            [[ -n "$etag_server" ]] && echo "$etag_server" > "$etag_file"
            [[ -n "$current_hash" ]] && echo "$current_hash" > "$hash_file"
            
            log OK "ОБНОВЛЕНО: $filename"
            rm -f "$header_file"
            return 0
            ;;
        304)
            log INFO "ПРОПУЩЕНО: $filename — HTTP 304 (не изменено)"
            rm -f "$temp_file" "$header_file"
            return 1
            ;;
        404)
            log ERROR "Файл не найден (404) для $filename"
            rm -f "$temp_file" "$header_file" "$etag_file"
            return 1
            ;;
        *)
            log WARN "Неожиданный статус HTTP $http_status для $filename"
            rm -f "$temp_file" "$header_file"
            return 1
            ;;
    esac
}

# Основная функция
main() {
    log INFO "Проверка обновлений Geo данных"
    
    # Настройка блокировки
    setup_lock
    
    # Базовые директории
    create_directories
    
    # Временная директория в пределах XRAY_DATCHECK_DIR
    TMP_DIR="$(mktemp -d "$XRAY_DATCHECK_DIR/tmp.XXXXXX")"
    
    local updated=0
    
    # Детерминированный порядок файлов
    mapfile -t _keys < <(printf '%s\n' "${!DATA_SOURCES[@]}" | sort)
    for filename in "${_keys[@]}"; do
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
    
    # Подстановка переменных
    sed -i \
        -e "s|__XRAY_DAT_PATH__|$XRAY_DATA_PATH|g" \
        -e "s|__XRAY_USER__|$XRAY_USER|g" \
        -e "s|__XRAY_GROUP__|$XRAY_GROUP|g" \
        "$GEO_DATA_UPDATE_SCRIPT"
    
    chmod +x "$GEO_DATA_UPDATE_SCRIPT"
    if id -u "$XRAY_USER" >/dev/null 2>&1; then
        chown "$XRAY_USER:$XRAY_GROUP" "$GEO_DATA_UPDATE_SCRIPT"
    fi
    
    log OK "Скрипт обновления Geo данных создан: $GEO_DATA_UPDATE_SCRIPT"
}

# === Настройка cron для Xray Core ===
updates_setup_xray_core_cron() {
    local cron_schedule
    cron_schedule="$(config_get_plugin "updates" "xray_core.cron_schedule" "0 3 * * 0")"
    
    log INFO "Настройка cron для обновления Xray Core: $cron_schedule"
    
    # Удаление существующих задач
    crontab -l 2>/dev/null | grep -v "$XRAY_CORE_UPDATE_SCRIPT" | crontab - 2>/dev/null || true
    
    # Добавление новой задачи
    {
        echo "SHELL=/bin/bash"
        echo "PATH=/usr/sbin:/usr/bin:/sbin:/bin"
        crontab -l 2>/dev/null | grep -v "SHELL=" | grep -v "PATH=" | grep -v "$XRAY_CORE_UPDATE_SCRIPT" || true
        echo "$cron_schedule $XRAY_CORE_UPDATE_SCRIPT >> $LOG_FILE 2>&1"
    } | crontab -
    
    log OK "Cron задача для Xray Core настроена"
}

# === Настройка cron для Geo данных ===
updates_setup_geo_data_cron() {
    local cron_schedule
    cron_schedule="$(config_get_plugin "updates" "geo_data.cron_schedule" "0 2 * * *")"
    
    log INFO "Настройка cron для обновления Geo данных: $cron_schedule"
    
    # Удаление существующих задач
    crontab -l 2>/dev/null | grep -v "$GEO_DATA_UPDATE_SCRIPT" | crontab - 2>/dev/null || true
    
    # Добавление новой задачи
    {
        echo "SHELL=/bin/bash"
        echo "PATH=/usr/sbin:/usr/bin:/sbin:/bin"
        crontab -l 2>/dev/null | grep -v "SHELL=" | grep -v "PATH=" | grep -v "$GEO_DATA_UPDATE_SCRIPT" || true
        echo "$cron_schedule $GEO_DATA_UPDATE_SCRIPT >> $LOG_FILE 2>&1"
    } | crontab -
    
    log OK "Cron задача для Geo данных настроена"
}

# === Удаление cron задач ===
updates_remove_cron_tasks() {
    log INFO "Удаление cron задач автообновлений"
    
    # Полное удаление crontab
    crontab -r 2>/dev/null || true
    
    log OK "Cron задачи удалены"
}

# === Экспорт функций ===
export -f plugin_updates_init plugin_updates_execute plugin_updates_dependencies plugin_updates_info plugin_updates_status
export -f updates_install updates_uninstall updates_status updates_update
export -f updates_create_xray_core_script updates_create_geo_data_script
export -f updates_setup_xray_core_cron updates_setup_geo_data_cron updates_remove_cron_tasks

# Автоматическая инициализация при загрузке плагина
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Если скрипт запущен напрямую
    plugin_updates_init "$@"
fi
# При загрузке как плагин НЕ вызываем plugin_updates_init автоматически
# Инициализация будет вызвана вручную из installer.sh
