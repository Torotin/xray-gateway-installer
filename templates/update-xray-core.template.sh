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
XRAY_SERVICE="__XRAY_SERVICE__"
XRAY_BINARY="__XRAY_BINARY__"
XRAY_USER="__XRAY_USER__"
XRAY_GROUP="__XRAY_GROUP__"
LOG_FILE="__LOG_FILE__"

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
    
    if [[ "$current_version" == "$latest_version" ]]; then
        log INFO "Xray уже обновлён до последней версии: $current_version"
        return 0
    fi
    
    log INFO "Обновление с $current_version до $latest_version"
    install_xray_core "$latest_version"
}

main "$@"
