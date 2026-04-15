#!/usr/bin/env bash

# === Модуль проверки зависимостей Xray Gateway Installer ===
# Версия: 2.0.0
# Автор: Xray Gateway Installer Team

# Глобальные переменные модуля
declare -g DEPENDENCIES_STATUS="unknown"
declare -g MISSING_DEPENDENCIES=()

# Список обязательных зависимостей
declare -gA REQUIRED_DEPENDENCIES=(
    ["python3"]="python3"
    ["curl"]="curl"
    ["wget"]="wget"
    ["jq"]="jq"
    ["crontab"]="cron"
    ["yq"]="yq"
    ["git"]="git"
    ["unzip"]="unzip"
    ["systemctl"]="systemd"
    ["iptables"]="iptables"
    ["ip"]="iproute2"
    ["ss"]="iproute2"
    ["grep"]="grep"
    ["awk"]="gawk"
    ["sed"]="sed"
    ["gzip"]="gzip"
    ["tar"]="tar"
    ["openssl"]="openssl"
    ["gpg"]="gnupg"
    ["ssh"]="openssh-client"
    ["ssh-keygen"]="openssh-client"
    ["resolvectl"]="systemd-resolved"
)

# Список опциональных зависимостей
declare -gA OPTIONAL_DEPENDENCIES=(
    ["htop"]="htop"
    ["nano"]="nano"
    ["vim"]="vim"
    ["tree"]="tree"
    ["netstat"]="net-tools"
    ["ifconfig"]="net-tools"
    ["route"]="net-tools"
)

# === Инициализация модуля ===
dependencies_init() {
    # Инициализация логирования для модуля ядра
    core_logger_init "dependencies" "_logs" "append"
    
    log INFO "Инициализация модуля проверки зависимостей"
    
    # Проверяем, что мы запущены от root
    if [[ "$(id -u)" -ne 0 ]]; then
        log ERROR "Модуль зависимостей требует прав root"
        return 1
    fi
    
    log OK "Модуль проверки зависимостей инициализирован"
}

# === Проверка наличия команды ===
check_command() {
    local command="$1"
    local package="${2:-$command}"
    
    if command -v "$command" >/dev/null 2>&1; then
        log DEBUG "Команда $command найдена"
        return 0
    else
        log DEBUG "Команда $command не найдена (пакет: $package)"
        return 1
    fi
}

dedupe_packages() {
    declare -A seen=()
    local package

    for package in "$@"; do
        [[ -n "$package" ]] || continue
        if [[ -z "${seen[$package]:-}" ]]; then
            seen["$package"]=1
            printf '%s\n' "$package"
        fi
    done
}

# === Проверка обязательных зависимостей ===
check_required_dependencies() {
    log INFO "Проверка обязательных зависимостей"
    
    local missing=()
    
    for command in "${!REQUIRED_DEPENDENCIES[@]}"; do
        local package="${REQUIRED_DEPENDENCIES[$command]}"
        
        if ! check_command "$command" "$package"; then
            missing+=("$package")
            log WARN "Отсутствует обязательная зависимость: $command (пакет: $package)"
        else
            log DEBUG "✓ $command"
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        mapfile -t MISSING_DEPENDENCIES < <(dedupe_packages "${missing[@]}")
        DEPENDENCIES_STATUS="missing_required"
        log ERROR "Найдено ${#MISSING_DEPENDENCIES[@]} отсутствующих обязательных зависимостей"
        return 1
    else
        DEPENDENCIES_STATUS="required_ok"
        log OK "Все обязательные зависимости найдены"
        return 0
    fi
}

# === Проверка опциональных зависимостей ===
check_optional_dependencies() {
    log INFO "Проверка опциональных зависимостей"
    
    local missing=()
    
    for command in "${!OPTIONAL_DEPENDENCIES[@]}"; do
        local package="${OPTIONAL_DEPENDENCIES[$command]}"
        
        if ! check_command "$command" "$package"; then
            missing+=("$package")
            log DEBUG "Отсутствует опциональная зависимость: $command (пакет: $package)"
        else
            log DEBUG "✓ $command (опциональная)"
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        mapfile -t missing < <(dedupe_packages "${missing[@]}")
        log INFO "Найдено ${#missing[@]} отсутствующих опциональных зависимостей (не критично)"
        log INFO "Отсутствующие опциональные пакеты: ${missing[*]}"
    else
        log OK "Все опциональные зависимости найдены"
    fi
}

# === Сравнение версий ===
version_compare() {
    local version1="$1"
    local version2="$2"
    local operator="$3"
    
    # Разбиваем версии на массивы
    IFS='.' read -ra v1 <<< "$version1"
    IFS='.' read -ra v2 <<< "$version2"
    
    # Дополняем массивы нулями до одинаковой длины
    local max_len=$(( ${#v1[@]} > ${#v2[@]} ? ${#v1[@]} : ${#v2[@]} ))
    for ((i=${#v1[@]}; i<max_len; i++)); do v1[i]=0; done
    for ((i=${#v2[@]}; i<max_len; i++)); do v2[i]=0; done
    
    # Сравниваем по частям
    for ((i=0; i<max_len; i++)); do
        if [[ ${v1[i]} -gt ${v2[i]} ]]; then
            [[ "$operator" == ">" || "$operator" == ">=" || "$operator" == "!=" ]] && return 0 || return 1
        elif [[ ${v1[i]} -lt ${v2[i]} ]]; then
            [[ "$operator" == "<" || "$operator" == "<=" || "$operator" == "!=" ]] && return 0 || return 1
        fi
    done
    
    # Версии равны
    [[ "$operator" == "==" || "$operator" == ">=" || "$operator" == "<=" ]] && return 0 || return 1
}

# === Проверка версий критических зависимостей ===
check_version_requirements() {
    log INFO "Проверка версий критических зависимостей"
    
    # Проверка версии bash
    local bash_version
    bash_version="$(bash --version | head -n1 | grep -oP '\d+\.\d+' | head -n1)"
    if version_compare "$bash_version" "4.0" ">="; then
        log OK "Bash версия: $bash_version (требуется >= 4.0)"
    else
        log WARN "Bash версия: $bash_version (требуется >= 4.0)"
    fi
    
    # Проверка версии Python3
    if command -v python3 >/dev/null 2>&1; then
        local python_version
        python_version="$(python3 --version 2>&1 | grep -oP '\d+\.\d+' | head -n1)"
        if version_compare "$python_version" "3.6" ">="; then
            log OK "Python3 версия: $python_version (требуется >= 3.6)"
            
            # Проверка наличия модуля yaml
            if python3 -c "import yaml" 2>/dev/null; then
                log OK "Python3 модуль yaml доступен"
            else
                log WARN "Python3 модуль yaml не найден (требуется для парсинга YAML)"
                log INFO "Установите: sudo apt install python3-yaml"
            fi
        else
            log WARN "Python3 версия: $python_version (требуется >= 3.6)"
        fi
    else
        log WARN "Python3 не найден (требуется для парсинга YAML)"
    fi
    
    # Проверка версии systemd
    if command -v systemctl >/dev/null 2>&1; then
        local systemd_version
        systemd_version="$(systemctl --version | head -n1 | grep -oP '\d+\.\d+' | head -n1)"
        log OK "Systemd версия: $systemd_version"
    fi
    
    # Проверка версии iptables
    if command -v iptables >/dev/null 2>&1; then
        local iptables_version
        iptables_version="$(iptables --version | head -n1 | grep -oP '\d+\.\d+' | head -n1)"
        log OK "Iptables версия: $iptables_version"
    fi
}

# === Проверка и запуск обязательных сервисов ===
ensure_required_services() {
    log INFO "Проверка обязательных сервисов"

    if ! command -v systemctl >/dev/null 2>&1; then
        log WARN "systemctl недоступен, проверка сервисов пропущена"
        return 0
    fi

    if command -v crontab >/dev/null 2>&1; then
        if ! systemctl list-unit-files cron.service --no-legend >/dev/null 2>&1; then
            log ERROR "cron.service не найден, хотя crontab доступен"
            return 1
        fi

        if systemctl enable cron >/dev/null 2>&1; then
            log OK "cron.service включён"
        else
            log ERROR "Не удалось включить cron.service"
            return 1
        fi

        if systemctl start cron >/dev/null 2>&1; then
            log OK "cron.service запущен"
        else
            log ERROR "Не удалось запустить cron.service"
            return 1
        fi

        if systemctl is-active --quiet cron; then
            log OK "cron.service активен"
        else
            log ERROR "cron.service неактивен после запуска"
            return 1
        fi
    fi
}

# === Автоматическая установка зависимостей ===
install_missing_dependencies() {
    log INFO "Автоматическая установка отсутствующих зависимостей"
    
    if [[ ${#MISSING_DEPENDENCIES[@]} -eq 0 ]]; then
        log INFO "Нет отсутствующих зависимостей для установки"
        return 0
    fi
    
    # Обновляем список пакетов
    log INFO "Обновление списка пакетов"
    if ! apt update >/dev/null 2>&1; then
        log ERROR "Не удалось обновить список пакетов"
        return 1
    fi
    
    # Устанавливаем отсутствующие пакеты
    log INFO "Установка пакетов: ${MISSING_DEPENDENCIES[*]}"
    if apt install -y "${MISSING_DEPENDENCIES[@]}" >/dev/null 2>&1; then
        log OK "Все отсутствующие зависимости установлены"
        
        # Повторная проверка
        MISSING_DEPENDENCIES=()
        if check_required_dependencies && ensure_required_services; then
            DEPENDENCIES_STATUS="installed"
            log OK "Зависимости успешно установлены и проверены"
            return 0
        else
            log ERROR "После установки зависимости или обязательные сервисы не прошли проверку"
            return 1
        fi
    else
        log ERROR "Не удалось установить отсутствующие зависимости"
        return 1
    fi
}


# === Полная проверка зависимостей ===
check_all_dependencies() {
    log INFO "Выполнение полной проверки зависимостей"
    
    # Проверяем обязательные зависимости
    if ! check_required_dependencies; then
        log ERROR "Обнаружены отсутствующие обязательные зависимости"
        
        # Предлагаем автоматическую установку
        if [[ "${AUTO_INSTALL_DEPENDENCIES:-false}" == "true" ]]; then
            log INFO "Автоматическая установка включена, устанавливаем зависимости..."
            if install_missing_dependencies; then
                log OK "Зависимости успешно установлены"
            else
                log ERROR "Не удалось установить зависимости автоматически"
                return 1
            fi
        else
            log ERROR "Для установки зависимостей используйте:"
            log ERROR "  sudo apt update && sudo apt install -y curl wget jq cron yq git unzip systemd iptables iproute2"
            log ERROR "или установите AUTO_INSTALL_DEPENDENCIES=true"
            return 1
        fi
    fi
    
    # Проверяем опциональные зависимости
    check_optional_dependencies
    
    # Проверяем версии
    check_version_requirements

    # Проверяем обязательные сервисы
    ensure_required_services

    # Все зависимости проверены
    
    DEPENDENCIES_STATUS="all_ok"
    log OK "Все зависимости проверены успешно"
    return 0
}

# === Получение статуса зависимостей ===
get_dependencies_status() {
    echo "$DEPENDENCIES_STATUS"
}

# === Получение списка отсутствующих зависимостей ===
get_missing_dependencies() {
    printf '%s\n' "${MISSING_DEPENDENCIES[@]}"
}

# === Проверка конкретной зависимости ===
check_dependency() {
    local command="$1"
    local package="${2:-$command}"
    
    if check_command "$command" "$package"; then
        log OK "Зависимость $command найдена"
        return 0
    else
        log WARN "Зависимость $command не найдена (пакет: $package)"
        return 1
    fi
}

# === Экспорт функций ===
export -f dependencies_init check_required_dependencies check_optional_dependencies check_version_requirements ensure_required_services install_missing_dependencies check_all_dependencies get_dependencies_status get_missing_dependencies check_dependency

# Автоматическая инициализация при загрузке модуля
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Если скрипт запущен напрямую
    dependencies_init "$@"
else
    # Если скрипт загружен как модуль
    dependencies_init
fi
