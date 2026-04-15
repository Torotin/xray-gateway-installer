#!/usr/bin/env bash

# === Общие утилиты Xray Gateway Installer ===
# Версия: 2.0.0
# Автор: Xray Gateway Installer Team

# === Проверка прав root ===
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log ERROR "Скрипт должен быть запущен с правами root!"
        exit 1
    fi
    [[ -t 1 ]] && clear
    log OK "Проверка прав root — пройдена"
}

# === Проверка версии ОС ===
check_os_version() {
    local id version
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        id="$ID"
        version="${VERSION_ID%%.*}"
    else
        log ERROR "Невозможно определить версию ОС (отсутствует /etc/os-release)"
        exit 1
    fi

    # Проверка поддерживаемых ОС
    local supported_os
    supported_os="$(config_get "installer.supported_os" "debian,ubuntu")"
    local os_supported=false
    
    for os in $(echo "$supported_os" | tr ',' ' '); do
        if [[ "$id" == "$os" ]]; then
            os_supported=true
            break
        fi
    done
    
    if [[ "$os_supported" == "false" ]]; then
        log ERROR "Поддерживаются только: $supported_os. Обнаружено: $id"
        exit 1
    fi

    # Проверка минимальной версии
    local min_version
    if [[ "$id" == "debian" ]]; then
        min_version="$(config_get "installer.min_debian_version" "12")"
    elif [[ "$id" == "ubuntu" ]]; then
        min_version="$(config_get "installer.min_ubuntu_version" "22.04")"
    else
        min_version="0"
    fi

    if (( version < min_version )); then
        log ERROR "Минимально поддерживаемая версия $id — $min_version. Обнаружено: $VERSION_ID"
        exit 1
    fi

    log OK "Проверка ОС — $id $VERSION_ID"
}

# === Проверка системных требований ===
check_system_requirements() {
    log INFO "Проверка системных требований..."
    
    local min_ram_mb min_disk_gb required_interfaces
    min_ram_mb="$(config_get "installer.requirements.min_ram_mb" "512")"
    min_disk_gb="$(config_get "installer.requirements.min_disk_gb" "2")"
    required_interfaces="$(config_get "installer.requirements.required_interfaces" "2")"
    
    # Проверка RAM
    local total_ram_mb
    total_ram_mb="$(free -m | awk '/^Mem:/{print $2}')"
    if [[ $total_ram_mb -lt $min_ram_mb ]]; then
        log ERROR "Недостаточно RAM: требуется $min_ram_mb MB, доступно $total_ram_mb MB"
        exit 1
    fi
    log OK "RAM: $total_ram_mb MB (требуется: $min_ram_mb MB)"
    
    # Проверка дискового пространства
    local available_disk_gb
    available_disk_gb="$(df / | awk 'NR==2{print int($4/1024/1024)}')"
    if [[ $available_disk_gb -lt $min_disk_gb ]]; then
        log ERROR "Недостаточно дискового пространства: требуется $min_disk_gb GB, доступно $available_disk_gb GB"
        exit 1
    fi
    log OK "Дисковое пространство: $available_disk_gb GB (требуется: $min_disk_gb GB)"
    
    # Проверка сетевых интерфейсов
    local interface_count
    interface_count="$(ip -o link show | wc -l)"
    if [[ $interface_count -lt $required_interfaces ]]; then
        log ERROR "Недостаточно сетевых интерфейсов: требуется $required_interfaces, доступно $interface_count"
        exit 1
    fi
    log OK "Сетевые интерфейсы: $interface_count (требуется: $required_interfaces)"
}

# === Установка системных пакетов ===
install_system_packages() {
    log INFO "Установка необходимых системных пакетов..."
    
    if ! command -v apt >/dev/null 2>&1; then
        log ERROR "apt не найден. Скрипт поддерживает только Debian-подобные системы с APT"
        exit 1
    fi

    # Бэкап resolv.conf
    local resolv_backup
    resolv_backup="$(mktemp /tmp/resolv.conf.backup.XXXXXX)"
    if [[ -e /etc/resolv.conf ]]; then
        cp -a /etc/resolv.conf "$resolv_backup"
    else
        : > "$resolv_backup"
    fi

    export DEBIAN_FRONTEND=noninteractive
    apt update -y && apt upgrade -y && apt install -y \
        ca-certificates curl iproute2 iptables nftables iputils-ping \
        resolvconf net-tools jq cron ipset nano mc sudo libssl-dev \
        conntrack tcpdump arptables ebtables \
        openssh-server openssh-client openssh-sftp-server \
        yq && \
        apt autoremove -y

    # Восстановление resolv.conf
    if [[ -s "$resolv_backup" || -L "$resolv_backup" ]]; then
        cp -aT "$resolv_backup" /etc/resolv.conf
    fi
    rm -f "$resolv_backup"

    # Обновление конфигурации резолвера
    if command -v resolvconf >/dev/null 2>&1; then
        resolvconf -u || true
    else
        systemctl restart networking 2>/dev/null || true
    fi

    log OK "Системные пакеты установлены"
}

# === Создание резервной копии ===
create_backup() {
    local source_path="$1"
    local backup_name="${2:-$(basename "$source_path")}"
    local backup_dir="${3:-${SCRIPT_DIR}/backups}"
    
    # Создание директории для бэкапов
    mkdir -p "$backup_dir"
    
    local timestamp
    timestamp="$(date '+%Y%m%d_%H%M%S')"
    local backup_path="$backup_dir/${backup_name}.backup.${timestamp}"
    
    if [[ -f "$source_path" ]]; then
        cp -a "$source_path" "$backup_path"
        log OK "Создана резервная копия: $backup_path"
    elif [[ -d "$source_path" ]]; then
        cp -a "$source_path" "$backup_path"
        log OK "Создана резервная копия директории: $backup_path"
    else
        log WARN "Источник для резервного копирования не найден: $source_path"
        return 1
    fi
    
    echo "$backup_path"
}

# === Восстановление из резервной копии ===
restore_backup() {
    local backup_path="$1"
    local target_path="$2"
    
    if [[ ! -f "$backup_path" && ! -d "$backup_path" ]]; then
        log ERROR "Резервная копия не найдена: $backup_path"
        return 1
    fi
    
    # Создание резервной копии текущего файла
    if [[ -e "$target_path" ]]; then
        create_backup "$target_path" "$(basename "$target_path").current"
    fi
    
    # Восстановление
    if [[ -f "$backup_path" ]]; then
        cp -a "$backup_path" "$target_path"
    elif [[ -d "$backup_path" ]]; then
        rm -rf "$target_path"
        cp -a "$backup_path" "$target_path"
    fi
    
    log OK "Восстановлено из резервной копии: $backup_path -> $target_path"
}

# === Проверка доступности команды ===
command_exists() {
    local command="$1"
    command -v "$command" >/dev/null 2>&1
}

# === Проверка доступности порта ===
port_available() {
    local port="$1"
    local protocol="${2:-tcp}"
    
    if command_exists netstat; then
        ! netstat -ln | grep -q ":$port " 2>/dev/null
    elif command_exists ss; then
        ! ss -ln | grep -q ":$port " 2>/dev/null
    else
        log WARN "Не удалось проверить доступность порта $port"
        return 0
    fi
}

# === Получение IP-адреса интерфейса ===
get_interface_ip() {
    local interface="$1"
    local family="${2:-inet}"
    
    ip -f "$family" addr show "$interface" | awk '/inet/ {print $2}' | head -n1
}

# === Получение MAC-адреса интерфейса ===
get_interface_mac() {
    local interface="$1"
    
    cat "/sys/class/net/$interface/address" 2>/dev/null || echo ""
}

# === Проверка активности сервиса ===
is_service_active() {
    local service="$1"
    
    if command_exists systemctl; then
        systemctl is-active --quiet "$service" 2>/dev/null
    else
        log WARN "systemctl недоступен, не удалось проверить статус сервиса: $service"
        return 1
    fi
}

# === Включение сервиса ===
enable_service() {
    local service="$1"
    
    if command_exists systemctl; then
        systemctl enable "$service" && log OK "Сервис $service включён"
    else
        log WARN "systemctl недоступен, не удалось включить сервис: $service"
        return 1
    fi
}

# === Запуск сервиса ===
start_service() {
    local service="$1"
    
    if command_exists systemctl; then
        systemctl start "$service" && log OK "Сервис $service запущен"
    else
        log WARN "systemctl недоступен, не удалось запустить сервис: $service"
        return 1
    fi
}

# === Остановка сервиса ===
stop_service() {
    local service="$1"
    
    if command_exists systemctl; then
        systemctl stop "$service" && log OK "Сервис $service остановлен"
    else
        log WARN "systemctl недоступен, не удалось остановить сервис: $service"
        return 1
    fi
}

# === Перезапуск сервиса ===
restart_service() {
    local service="$1"
    
    if command_exists systemctl; then
        systemctl restart "$service" && log OK "Сервис $service перезапущен"
    else
        log WARN "systemctl недоступен, не удалось перезапустить сервис: $service"
        return 1
    fi
}

# === Создание пользователя ===
create_user() {
    local username="$1"
    local uid="${2:-}"
    local gid="${3:-}"
    local groups="${4:-}"
    local shell="${5:-/usr/sbin/nologin}"
    local home="${6:-}"
    local system_user="${7:-true}"
    
    # Проверка существования пользователя
    if getent passwd "$username" >/dev/null 2>&1; then
        log INFO "Пользователь $username уже существует"
        return 0
    fi
    
    # Создание группы, если указана
    if [[ -n "$gid" ]]; then
        if ! getent group "$username" >/dev/null 2>&1; then
            if [[ "$system_user" == "true" ]]; then
                groupadd -r -g "$gid" "$username" || {
                    log ERROR "Не удалось создать группу $username"
                    return 1
                }
            else
                groupadd -g "$gid" "$username" || {
                    log ERROR "Не удалось создать группу $username"
                    return 1
                }
            fi
            log OK "Группа $username создана"
        fi
    fi
    
    # Создание пользователя
    local useradd_args=()
    [[ -n "$uid" ]] && useradd_args+=("-u" "$uid")
    [[ -n "$gid" ]] && useradd_args+=("-g" "$gid")
    [[ -n "$groups" ]] && useradd_args+=("-G" "$groups")
    [[ -n "$shell" ]] && useradd_args+=("-s" "$shell")
    [[ -n "$home" ]] && useradd_args+=("-d" "$home")
    [[ "$system_user" == "true" ]] && useradd_args+=("-r" "-M")
    
    if useradd "${useradd_args[@]}" "$username"; then
        log OK "Пользователь $username создан"
    else
        log ERROR "Не удалось создать пользователя $username"
        return 1
    fi
}

# === Создание директории с правами ===
create_directory() {
    local path="$1"
    local owner="${2:-}"
    local group="${3:-}"
    local mode="${4:-755}"
    
    if [[ ! -d "$path" ]]; then
        if mkdir -p "$path"; then
            log OK "Директория создана: $path"
        else
            log ERROR "Не удалось создать директорию: $path"
            return 1
        fi
    fi
    
    # Установка прав доступа
    if [[ -n "$owner" && -n "$group" ]]; then
        chown "$owner:$group" "$path" || {
            log WARN "Не удалось изменить владельца директории: $path"
        }
    fi
    
    chmod "$mode" "$path" || {
        log WARN "Не удалось изменить права доступа к директории: $path"
    }
}

# === Загрузка файла с проверкой ===
download_file() {
    local url="$1"
    local output="$2"
    local checksum="${3:-}"
    local timeout="${4:-60}"
    
    log INFO "Загрузка файла: $url"
    
    if curl -fsSL --connect-timeout 10 --max-time "$timeout" -o "$output" "$url"; then
        log OK "Файл загружен: $output"
        
        # Проверка контрольной суммы, если указана
        if [[ -n "$checksum" ]]; then
            local file_checksum
            file_checksum="$(sha256sum "$output" | cut -d' ' -f1)"
            if [[ "$file_checksum" == "$checksum" ]]; then
                log OK "Контрольная сумма файла совпадает"
            else
                log ERROR "Контрольная сумма файла не совпадает"
                rm -f "$output"
                return 1
            fi
        fi
        
        return 0
    else
        log ERROR "Не удалось загрузить файл: $url"
        return 1
    fi
}

# === Генерация случайного пароля ===
generate_password() {
    local length="${1:-16}"
    
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-"$length"
}

# === Генерация случайного ключа ===
generate_key() {
    local length="${1:-32}"
    
    openssl rand -hex "$length"
}

# === Проверка целостности файла ===
verify_file_integrity() {
    local file="$1"
    local expected_checksum="$2"
    
    if [[ ! -f "$file" ]]; then
        log ERROR "Файл не найден: $file"
        return 1
    fi
    
    local actual_checksum
    actual_checksum="$(sha256sum "$file" | cut -d' ' -f1)"
    
    if [[ "$actual_checksum" == "$expected_checksum" ]]; then
        log OK "Целостность файла подтверждена: $file"
        return 0
    else
        log ERROR "Целостность файла нарушена: $file"
        log ERROR "Ожидалось: $expected_checksum"
        log ERROR "Получено: $actual_checksum"
        return 1
    fi
}

# === Очистка временных файлов ===
cleanup_temp_files() {
    local temp_dir="${1:-/tmp}"
    local pattern="${2:-xray-installer-*}"
    
    find "$temp_dir" -name "$pattern" -type f -mtime +1 -delete 2>/dev/null || true
    log DEBUG "Временные файлы очищены"
}

# === Экспорт функций ===
export -f check_root check_os_version check_system_requirements install_system_packages
export -f create_backup restore_backup command_exists port_available
export -f get_interface_ip get_interface_mac is_service_active enable_service start_service stop_service restart_service
export -f create_user create_directory download_file generate_password generate_key verify_file_integrity cleanup_temp_files
