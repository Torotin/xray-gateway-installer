#!/usr/bin/env bash

# === Скрипт обновления GeoIP/GeoSite данных ===
# Автоматически сгенерирован Xray Gateway Installer
# Версия: 2.0.0
# Дата: $(date '+%Y-%m-%d')

set -uo pipefail

# === Конфигурация ===
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="update-geo-data"
readonly MAX_RETRIES=3
readonly CURL_TIMEOUT=30
readonly CURL_CONNECT_TIMEOUT=10
readonly DEBUG_MODE="${DEBUG:-false}"
readonly DRY_RUN="${DRY_RUN:-false}"

# === Функция логирования ===
# Улучшенная система логирования с поддержкой debug режима
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local log_entry="[$timestamp] [$level] $message"
    
    # Debug режим - выводим все в stderr
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo "$log_entry" >&2
    fi
    
    case "$level" in
        "DEBUG")
            if [[ "$DEBUG_MODE" == "true" ]]; then
                echo "$log_entry" | tee -a "$LOG_FILE"
            fi
            ;;
        "INFO")
            echo "$log_entry" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo "$log_entry" | tee -a "$LOG_FILE" >&2
            ;;
        "ERROR")
            echo "$log_entry" | tee -a "$LOG_FILE" >&2
            ;;
        "OK")
            echo "$log_entry" | tee -a "$LOG_FILE"
            ;;
        *)
            echo "$log_entry" | tee -a "$LOG_FILE"
            ;;
    esac
}

# === Функция debug логирования ===
debug_log() {
    if [[ "$DEBUG_MODE" == "true" ]]; then
        log DEBUG "$@"
    fi
}

# === Функции валидации ===
# Проверка зависимостей
check_dependencies() {
    local missing_deps=()
    
    # Проверка curl
    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
    fi
    
    # Проверка systemctl (опционально)
    if ! command -v systemctl >/dev/null 2>&1; then
        log WARN "systemctl недоступен - перезапуск сервиса будет пропущен"
    fi
    
    # Проверка sha256sum
    if ! command -v sha256sum >/dev/null 2>&1; then
        missing_deps+=("sha256sum")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log ERROR "Отсутствуют обязательные зависимости: ${missing_deps[*]}"
        return 1
    fi
    
    debug_log "Все зависимости найдены"
    return 0
}

# Валидация URL
validate_url() {
    local url="$1"
    
    if [[ -z "$url" ]]; then
        log ERROR "URL не может быть пустым"
        return 1
    fi
    
    if [[ ! "$url" =~ ^https?:// ]]; then
        log ERROR "Некорректный URL: $url (должен начинаться с http:// или https://)"
        return 1
    fi
    
    debug_log "URL валиден: $url"
    return 0
}

# Валидация файла
validate_file() {
    local filepath="$1"
    local expected_size="${2:-0}"
    
    if [[ ! -f "$filepath" ]]; then
        log ERROR "Файл не найден: $filepath"
        return 1
    fi
    
    if [[ "$expected_size" -gt 0 ]]; then
        local actual_size
        actual_size="$(stat -c%s "$filepath" 2>/dev/null || echo "0")"
        if [[ "$actual_size" -lt "$expected_size" ]]; then
            log ERROR "Файл слишком мал: $filepath (ожидалось >= $expected_size, получено $actual_size)"
            return 1
        fi
    fi
    
    debug_log "Файл валиден: $filepath"
    return 0
}

# === Конфигурация ===
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

# Временная директория
TEMP_DIR=""
TEMP_PREFIX="xray-geo-"

# === Функции работы с временными файлами ===
# Создание временной директории
create_temp_dir() {
    TEMP_DIR="$(mktemp -d -t "${TEMP_PREFIX}XXXXXX" 2>/dev/null || echo "/tmp/${TEMP_PREFIX}$$")"
    if [[ ! -d "$TEMP_DIR" ]]; then
        mkdir -p "$TEMP_DIR" || {
            log ERROR "Не удалось создать временную директорию: $TEMP_DIR"
            return 1
        }
    fi
    debug_log "Создана временная директория: $TEMP_DIR"
    return 0
}

# Безопасное создание временного файла
create_temp_file() {
    local suffix="${1:-.tmp}"
    local temp_file
    temp_file="$(mktemp -p "$TEMP_DIR" "${TEMP_PREFIX}XXXXXX${suffix}" 2>/dev/null || echo "$TEMP_DIR/${TEMP_PREFIX}$$${suffix}")"
    echo "$temp_file"
}

# Прокси для загрузки с GitHub
gh_proxy="https://ghfast.top"

# Источники данных (обновленный список с fallback)
declare -A DATA_SOURCES=(
    # Re-filter списки (новые)
    ["geosite_refilter.dat"]="https://github.com/1andrevich/Re-filter-lists/releases/latest/download/geosite.dat"
    ["geoip_refilter.dat"]="https://github.com/1andrevich/Re-filter-lists/releases/latest/download/geoip.dat"
    
    # V2Fly списки (обновленные)
    ["geoip_v2fly.dat"]="https://github.com/loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
    ["geosite_v2fly.dat"]="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
    
    # ZKeen списки
    ["geoip_zkeen.dat"]="https://github.com/jameszeroX/zkeen-ip/releases/latest/download/zkeenip.dat"
    ["geosite_zkeen.dat"]="https://github.com/jameszeroX/zkeen-domains/releases/latest/download/zkeen.dat"
    
    # AntiZapret списки
    ["geoip_antizapret.dat"]="https://github.com/savely-krasovsky/antizapret-sing-box/releases/latest/download/geoip.db"
    ["geosite_antizapret.dat"]="https://github.com/savely-krasovsky/antizapret-sing-box/releases/latest/download/geosite.db"
    
    # Russia Blocked списки
    ["geoip_russia-blocked.dat"]="https://raw.githubusercontent.com/runetfreedom/russia-blocked-geoip/release/geoip.dat"
    ["geosite_russia-blocked.dat"]="https://raw.githubusercontent.com/runetfreedom/russia-blocked-geosite/release/geosite.dat"
    
    # AdBlock списки
    ["geosite_adlist.dat"]="https://github.com/zxc-rv/ad-filter/releases/latest/download/adlist.dat"

    # RoscomVPN списки
    ["geosite_roscomvpn.dat"]="https://github.com/hydraponique/roscomvpn-geosite/releases/latest/download/geosite.dat"
    ["geoip_roscomvpn.dat"]="https://github.com/hydraponique/roscomvpn-geoip/releases/latest/download/geoip.dat"
)


# Создание необходимых директорий
create_directories() {
    mkdir -p "$XRAY_DAT_PATH" "$ETAG_DIR" "$HASH_DIR" "$XRAY_DATCHECK_DIR"
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

ensure_compat_aliases() {
    local -a alias_specs=(
        "geoip_v2fly.dat|$XRAY_DAT_PATH/geoip.dat|/usr/local/bin/geoip.dat"
        "geosite_v2fly.dat|$XRAY_DAT_PATH/geosite.dat|/usr/local/bin/geosite.dat"
        "geoip_zkeen.dat|$XRAY_DAT_PATH/geoip_zkeenip.dat|/usr/local/bin/geoip_zkeenip.dat"
    )

    local spec source_name dat_alias bin_alias source_file
    for spec in "${alias_specs[@]}"; do
        IFS='|' read -r source_name dat_alias bin_alias <<< "$spec"
        source_file="$XRAY_DAT_PATH/$source_name"

        [[ -f "$source_file" ]] || continue

        ln -sfn "$source_file" "$dat_alias"
        ln -sfn "$source_file" "$bin_alias"
        debug_log "Compatibility aliases updated: $dat_alias and $bin_alias -> $source_file"
    done
}

# === Функции очистки ===
# Очистка при выходе
cleanup() {
    debug_log "Начало очистки ресурсов"
    
    # Освобождение блокировки
    release_lock
    
    # Очистка временной директории
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        debug_log "Очистка временной директории: $TEMP_DIR"
        rm -rf "$TEMP_DIR" 2>/dev/null || true
    fi
    
    # Дополнительная очистка старых временных файлов
    rm -rf "/tmp/${TEMP_PREFIX}*" 2>/dev/null || true
    
    debug_log "Очистка завершена"
}

# === Функции retry логики ===
# Выполнение команды с повторными попытками
retry_command() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local command=("$@")
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        debug_log "Попытка $attempt/$max_attempts: ${command[*]}"
        
        if "${command[@]}" 2>/dev/null; then
            debug_log "Команда выполнена успешно"
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log WARN "Попытка $attempt не удалась, повтор через ${delay}с..."
            sleep "$delay"
        fi
        
        ((attempt++))
    done
    
    log ERROR "Все $max_attempts попыток не удались: ${command[*]}"
    return 1
}

# === Функции получения метаданных ===
# Получение ETag с retry логикой и fallback на Last-Modified
get_etag() {
    local url="$1"
    
    if ! validate_url "$url"; then
        return 1
    fi
    
    debug_log "Получение ETag для: $url"
    
    local headers
    headers="$(retry_command 3 2 curl -sI --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_TIMEOUT" "$url" 2>/dev/null || echo "")"
    
    # Попытка получить ETag
    local etag
    etag="$(echo "$headers" | grep -i "etag:" | cut -d'"' -f2 2>/dev/null || echo "")"
    
    # Fallback на Last-Modified если ETag недоступен
    if [[ -z "$etag" ]]; then
        local last_modified
        last_modified="$(echo "$headers" | grep -i "last-modified:" | cut -d':' -f2- | sed 's/^[[:space:]]*//' 2>/dev/null || echo "")"
        
        if [[ -n "$last_modified" ]]; then
            etag="last-modified:$last_modified"
            debug_log "Использован Last-Modified как ETag: $last_modified"
        else
            # Fallback на timestamp
            etag="timestamp:$(date +%s)"
            debug_log "Использован timestamp как ETag: $etag"
        fi
    else
        debug_log "ETag получен: $etag"
    fi
    
    echo "$etag"
}

# Получение хеша файла
get_file_hash() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        debug_log "Файл не найден для хеширования: $file"
        echo ""
        return 0
    fi
    
    debug_log "Вычисление хеша для: $file"
    
    local hash
    hash="$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1 || echo "")"
    
    if [[ -n "$hash" ]]; then
        debug_log "Хеш вычислен: ${hash:0:16}..."
    else
        log WARN "Не удалось вычислить хеш для: $file"
    fi
    
    echo "$hash"
}

# === Функции обновления данных ===
# Безопасная загрузка файла
safe_download() {
    local url="$1"
    local output_file="$2"
    local filename="$(basename "$output_file")"
    local temp_file
    
    temp_file="$(create_temp_file ".download")"
    debug_log "Загрузка файла: $filename"
    
    # Первая попытка: загрузка с основного URL
    if curl -L -o "$temp_file" "$url" >/dev/null 2>&1; then
        if [[ -s "$temp_file" ]]; then
            # Валидация загруженного файла
            if validate_file "$temp_file" 1024; then
                mv "$temp_file" "$output_file"
                log SUCCESS "Файл $filename успешно загружен"
                return 0
            else
                log ERROR "Загруженный файл не прошел валидацию: $temp_file"
                rm -f "$temp_file"
            fi
        else
            log ERROR "Неизвестная ошибка при загрузке $filename"
            rm -f "$temp_file"
        fi
    else
        # Вторая попытка: загрузка через прокси
        log INFO "Попытка загрузки через прокси: $gh_proxy/$url"
        if curl -L -o "$temp_file" "$gh_proxy/$url" >/dev/null 2>&1; then
            if [[ -s "$temp_file" ]]; then
                # Валидация загруженного файла
                if validate_file "$temp_file" 1024; then
                    mv "$temp_file" "$output_file"
                    log SUCCESS "Файл $filename успешно загружен через прокси"
                    return 0
                else
                    log ERROR "Загруженный файл через прокси не прошел валидацию: $temp_file"
                    rm -f "$temp_file"
                fi
            else
                log ERROR "Неизвестная ошибка при загрузке $filename через прокси"
                rm -f "$temp_file"
            fi
        else
            rm -f "$temp_file"
            log ERROR "Ошибка при загрузке $filename. Проверьте соединение с интернетом или повторите позже"
            return 1
        fi
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
    
    # Валидация входных параметров
    if ! validate_url "$url"; then
        log ERROR "Некорректный URL для $filename: $url"
        return 0
    fi
    
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
    
    # Dry run режим
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "DRY RUN: Будет загружен $filename из $url"
        return 1
    fi
    
    # Загрузка файла
    log INFO "Загрузка $filename"
    if safe_download "$url" "$filepath"; then
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

# === Основная функция ===
main() {
    log INFO "Запуск скрипта обновления Geo данных v$SCRIPT_VERSION"
    
    # Проверка зависимостей
    if ! check_dependencies; then
        log ERROR "Проверка зависимостей не пройдена"
        exit 1
    fi
    
    # Создание временной директории
    if ! create_temp_dir; then
        log ERROR "Не удалось создать временную директорию"
        exit 1
    fi
    
    # Создание необходимых директорий
    if ! create_directories; then
        log ERROR "Не удалось создать необходимые директории"
        exit 1
    fi
    
    # Блокировка от параллельных запусков
    if ! acquire_lock; then
        log ERROR "Не удалось получить блокировку"
        exit 1
    fi
    
    # Установка обработчика очистки
    trap cleanup EXIT
    
    local updated=0
    local total_files="${#DATA_SOURCES[@]}"
    local processed=0
    
    log INFO "Найдено $total_files файлов для проверки"
    
    # Обновление всех файлов данных
    for filename in "${!DATA_SOURCES[@]}"; do
        ((processed++))
        log INFO "Обработка файла $processed/$total_files: $filename"
        
        if update_data_file "$filename" "${DATA_SOURCES[$filename]}"; then
            ((updated++))
        fi
    done
    
    log INFO "Обработано файлов: $processed, обновлено: $updated"

    ensure_compat_aliases
    
    # Перезапуск Xray при наличии обновлений
    if [[ $updated -gt 0 ]]; then
        restart_xray_service
    else
        log INFO "Все файлы актуальны. Перезапуск не требуется"
    fi
    
    log OK "Обновление Geo данных завершено"
}

# === Функция перезапуска сервиса ===
restart_xray_service() {
    log INFO "Перезапуск сервиса $XRAY_SERVICE"
    
    if ! command -v systemctl >/dev/null 2>&1; then
        log WARN "systemctl недоступен — пропускаю перезапуск"
        return 0
    fi
    
    # Проверяем, существует ли сервис
    if ! systemctl list-unit-files "$XRAY_SERVICE.service" >/dev/null 2>&1; then
        log WARN "Сервис $XRAY_SERVICE не найден в systemd"
        return 0
    fi
    
    # Проверяем статус сервиса
    if systemctl is-active --quiet "$XRAY_SERVICE" 2>/dev/null; then
        # Сервис запущен - перезапускаем
        if retry_command 3 2 systemctl restart "$XRAY_SERVICE"; then
            log OK "Сервис $XRAY_SERVICE перезапущен"
        else
            log ERROR "Ошибка при перезапуске сервиса $XRAY_SERVICE"
            return 1
        fi
    else
        # Сервис не запущен - запускаем
        log INFO "Сервис $XRAY_SERVICE не запущен, запускаю..."
        if retry_command 3 2 systemctl start "$XRAY_SERVICE"; then
            log OK "Сервис $XRAY_SERVICE запущен"
        else
            log WARN "Не удалось запустить сервис $XRAY_SERVICE"
            return 1
        fi
    fi
    
    # Проверяем финальный статус
    sleep 2
    if systemctl is-active --quiet "$XRAY_SERVICE" 2>/dev/null; then
        log OK "Сервис $XRAY_SERVICE работает корректно"
    else
        log WARN "Сервис $XRAY_SERVICE не запущен после перезапуска"
    fi
}

trap cleanup EXIT
main "$@"
