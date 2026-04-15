#!/usr/bin/env bash

# === Компонент установки Xray Core ===
# Версия: 2.0.0
# Автор: Xray Gateway Installer Team

# === Инициализация компонента ===
core_init() {
    log INFO "Инициализация компонента установки Xray Core"
    log OK "Компонент установки Xray Core инициализирован"
    return 0
}

core_ensure_geo_aliases() {
    local xray_dat_path
    xray_dat_path="$(config_get_constant "xray_data_path" "/opt/xray/dat")"

    local -a alias_specs=(
        "geoip_v2fly.dat|$xray_dat_path/geoip.dat|/usr/local/bin/geoip.dat"
        "geosite_v2fly.dat|$xray_dat_path/geosite.dat|/usr/local/bin/geosite.dat"
        "geoip_zkeen.dat|$xray_dat_path/geoip_zkeenip.dat|/usr/local/bin/geoip_zkeenip.dat"
    )

    local spec source_name dat_alias bin_alias source_file
    for spec in "${alias_specs[@]}"; do
        IFS='|' read -r source_name dat_alias bin_alias <<< "$spec"
        source_file="$xray_dat_path/$source_name"

        [[ -f "$source_file" ]] || continue

        ln -sfn "$source_file" "$dat_alias"
        ln -sfn "$source_file" "$bin_alias"
        log OK "Созданы compatibility-alias: $dat_alias и $bin_alias -> $source_file"
    done
}

# === Установка Xray Core ===
core_install() {
    log INFO "Установка Xray Core"
    
    # Получение переменных конфигурации
    local xray_user xray_group xray_install_path xray_dat_path xray_installer_url xray_installer_path installer_json_path
    xray_user="$(config_get_constant "xray_user" "xray")"
    xray_group="$(config_get_constant "xray_group" "xray")"
    xray_install_path="$(config_get_constant "xray_install_path" "/opt/xray")"
    xray_dat_path="$(config_get_constant "xray_data_path" "/opt/xray/dat")"
    xray_installer_url="$(config_get_constant "xray_installer_url" "https://github.com/XTLS/Xray-install/raw/main/install-release.sh")"
    xray_installer_path="$(mktemp)"
    installer_json_path="/usr/local/etc/xray"
    
    log INFO "Скачивание Xray-инсталлятора: $xray_installer_url"
    
    if curl -fsSL "$xray_installer_url" -o "$xray_installer_path"; then
        log OK "Инсталлятор загружен в $xray_installer_path"
    else
        log ERROR "Не удалось загрузить Xray-инсталлятор"
        return 1
    fi
    
    if chmod +x "$xray_installer_path"; then
        log OK "Права на выполнение даны для $xray_installer_path"
    else
        log ERROR "Не удалось задать права на $xray_installer_path"
        return 1
    fi
    
    local installer_command_log
    installer_command_log="$(mktemp)"

    log INFO "Удаление предыдущей установки Xray (если была)"
    if TERM="${TERM:-dumb}" DAT_PATH="$xray_dat_path" JSON_PATH="$installer_json_path" bash "$xray_installer_path" remove >"$installer_command_log" 2>&1; then
        log OK "Старая установка удалена (или не обнаружена)"
    else
        log WARN "Удаление завершилось с ошибкой, возможно Xray не был установлен"
        tail -n 20 "$installer_command_log" | sed 's/^/    └─ /'
    fi

    log INFO "Установка Xray от пользователя $xray_user"
    if TERM="${TERM:-dumb}" DAT_PATH="$xray_dat_path" JSON_PATH="$installer_json_path" bash "$xray_installer_path" install -u "$xray_user" >"$installer_command_log" 2>&1; then
        log OK "Xray успешно установлен"
    else
        log ERROR "Установка завершилась с ошибкой"
        tail -n 50 "$installer_command_log" | sed 's/^/    └─ /'
        rm -f "$installer_command_log"
        return 1
    fi
    
    # Загрузка Geo данных
    log INFO "Загрузка Geo данных"
    if TERM="${TERM:-dumb}" DAT_PATH="$xray_dat_path" JSON_PATH="$installer_json_path" bash "$xray_installer_path" install-geodata >"$installer_command_log" 2>&1; then
        log OK "Geo данные загружены"
    else
        log WARN "Не удалось загрузить Geo данные через инсталлятор, попытка ручной загрузки"
        tail -n 30 "$installer_command_log" | sed 's/^/    └─ /'
        
        # Ручная загрузка Geo данных
        local geo_data_dir="/usr/local/share/xray"
        local geoip_url="https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"
        local geosite_url="https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"
        
        # Создание директории для Geo данных
        if mkdir -p "$geo_data_dir"; then
            log OK "Директория для Geo данных создана: $geo_data_dir"
        else
            log ERROR "Не удалось создать директорию: $geo_data_dir"
            return 1
        fi
        
        # Загрузка geoip.dat
        log INFO "Загрузка geoip.dat"
        if curl -fsSL "$geoip_url" -o "$geo_data_dir/geoip.dat"; then
            log OK "geoip.dat загружен"
        else
            log WARN "Не удалось загрузить geoip.dat"
        fi
        
        # Загрузка geosite.dat
        log INFO "Загрузка geosite.dat"
        if curl -fsSL "$geosite_url" -o "$geo_data_dir/geosite.dat"; then
            log OK "geosite.dat загружен"
        else
            log WARN "Не удалось загрузить geosite.dat"
        fi
        
        # Установка прав доступа
        if chown -R "$xray_user:$xray_group" "$geo_data_dir"; then
            log OK "Права доступа для Geo данных установлены"
        else
            log WARN "Не удалось установить права доступа для Geo данных"
        fi
    fi

    if systemctl is-active --quiet xray.service 2>/dev/null; then
        log INFO "Остановка временно запущенного xray.service до применения нашего override"
        systemctl stop xray.service 2>/dev/null || true
    fi

    rm -f "$installer_command_log"
    
    log INFO "Удаление инсталлятора"
    if rm -f "$xray_installer_path"; then
        log OK "Инсталлятор удалён"
    else
        log ERROR "Не удалось удалить $xray_installer_path"
        return 1
    fi
    
    log INFO "Удаление конфликтующих systemd drop-in конфигураций"
    for dir in /etc/systemd/system/xray.service.d /etc/systemd/system/xray@.service.d; do
        if [[ -d "$dir" ]]; then
            if rm -rf "$dir"; then
                log OK "Удалён каталог с конфигурациями: $dir"
            else
                log ERROR "Не удалось удалить $dir"
                return 1
            fi
        else
            log INFO "Каталог $dir не найден — пропуск"
        fi
    done
    
    log INFO "Создание символической ссылки для данных Xray"
    if [[ -L /usr/local/share/xray ]]; then
        if rm -f /usr/local/share/xray; then
            log OK "Удалена старая символическая ссылка /usr/local/share/xray"
        else
            log ERROR "Не удалось удалить символическую ссылку /usr/local/share/xray"
            return 1
        fi
    elif [[ -e /usr/local/share/xray ]]; then
        log ERROR "Путь /usr/local/share/xray уже существует и не является символической ссылкой; требуется ручная проверка"
        return 1
    else
        log INFO "Символическая ссылка /usr/local/share/xray отсутствует — пропуск удаления"
    fi
    
    if ln -s "$xray_dat_path" /usr/local/share/xray; then
        log OK "Создана новая ссылка: /usr/local/share/xray → $xray_dat_path"
    else
        log ERROR "Не удалось создать символическую ссылку /usr/local/share/xray"
        return 1
    fi

    core_ensure_geo_aliases
    
    log OK "Установка Xray Core завершена"
}

# === Настройка systemd сервиса ===
core_setup_systemd() {
    log INFO "Создание override-конфигурации systemd для xray"
    
    # Получение переменных конфигурации
    local xray_user xray_group xray_install_path xray_log_path xray_configs_path
    xray_user="$(config_get_constant "xray_user" "xray")"
    xray_group="$(config_get_constant "xray_group" "xray")"
    xray_install_path="$(config_get_constant "xray_install_path" "/opt/xray")"
    xray_log_path="$(config_get_constant "xray_log_path" "$xray_install_path/logs")"
    xray_configs_path="$(config_get_constant "xray_configs_path" "$xray_install_path/configs")"
    
    [[ -z "$xray_user" || -z "$xray_log_path" || -z "$xray_configs_path" ]] && {
        log ERROR "Одна из обязательных переменных (xray_user, xray_log_path, xray_configs_path) не задана"
        return 1
    }
    
    [[ ! -x "/usr/local/bin/xray" ]] && {
        log ERROR "Xray не найден в /usr/local/bin/xray"
        return 1
    }
    
    [[ ! -d "$xray_configs_path" ]] && {
        log ERROR "Каталог конфигурации не существует: $xray_configs_path"
        return 1
    }
    
    local override_dir="/etc/systemd/system/xray.service.d"
    local override_file="$override_dir/z90-custom-override.conf"
    
    mkdir -p "$override_dir" && log OK "Каталог override создан: $override_dir"
    
    cat > "$override_file" <<EOF
[Service]
ExecStart=
User=$xray_user
Group=$xray_group
ExecStartPre=/usr/local/bin/xray run -test -confdir $xray_configs_path
ExecStart=/usr/local/bin/xray run -confdir $xray_configs_path
ExecStartPost=+/bin/sh -c 'if [ -x "$xray_install_path/iptables/xray-iptables.sh" ]; then exec "$xray_install_path/iptables/xray-iptables.sh" restart; fi'
Restart=on-failure
RestartSec=5s
WorkingDirectory=$xray_install_path
SuccessExitStatus=0
StandardOutput=journal
StandardError=journal
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
EOF
    
    if [[ -f "$override_file" ]]; then
        log OK "Override-файл создан: $override_file"
    else
        log ERROR "Override-файл не был создан"
        return 1
    fi
    
    log INFO "Перезагрузка systemd-демонов"
    systemctl daemon-reexec && systemctl daemon-reload \
        && log OK "Systemd перезагружен" \
        || { log ERROR "Не удалось перезагрузить systemd"; return 1; }
}

# === Удаление Xray Core ===
core_remove() {
    log INFO "Удаление Xray Core"
    
    # Получение переменных конфигурации
    local xray_install_path
    xray_install_path="$(config_get_constant "xray_install_path" "/opt/xray")"
    
    # Остановка сервиса
    systemctl stop xray 2>/dev/null || true
    systemctl disable xray 2>/dev/null || true
    
    # Удаление файлов
    if [[ -f "$xray_install_path/xray" ]]; then
        rm -f "$xray_install_path/xray"
        log OK "Xray Core удален"
    fi
    
    # Удаление systemd сервисов
    if [[ -f "/etc/systemd/system/xray.service" ]]; then
        rm -f "/etc/systemd/system/xray.service"
        log OK "Systemd сервис xray.service удален"
    fi
    
    if [[ -f "/etc/systemd/system/xray@.service" ]]; then
        rm -f "/etc/systemd/system/xray@.service"
        log OK "Systemd сервис xray@.service удален"
    fi

    if [[ -d "/etc/systemd/system/xray.service.d" ]]; then
        rm -rf "/etc/systemd/system/xray.service.d"
        log OK "Каталог override /etc/systemd/system/xray.service.d удален"
    fi

    if [[ -d "/etc/systemd/system/xray@.service.d" ]]; then
        rm -rf "/etc/systemd/system/xray@.service.d"
        log OK "Каталог override /etc/systemd/system/xray@.service.d удален"
    fi
    
    # Удаление исполняемого файла
    if [[ -f "/usr/local/bin/xray" ]]; then
        rm -f "/usr/local/bin/xray"
        log OK "Исполняемый файл /usr/local/bin/xray удален"
    fi

    # Удаление compatibility-alias для GeoIP/GeoSite
    local alias_path
    for alias_path in \
        "/usr/local/bin/geoip.dat" \
        "/usr/local/bin/geosite.dat" \
        "/usr/local/bin/geoip_zkeenip.dat"
    do
        if [[ -L "$alias_path" || -f "$alias_path" ]]; then
            rm -f "$alias_path"
            log OK "Compatibility-alias удалён: $alias_path"
        fi
    done

    # Удаление символической ссылки
    if [[ -L "/usr/local/share/xray" ]]; then
        rm -f "/usr/local/share/xray"
        log OK "Символическая ссылка /usr/local/share/xray удалена"
    fi
    
    # Удаление директории Xray
    if [[ -d "$xray_install_path" ]]; then
        rm -rf "$xray_install_path"
        log OK "Директория $xray_install_path удалена"
    fi
    
    systemctl daemon-reload
}

# === Статус Xray Core ===
core_status() {
    # Получение переменных конфигурации
    local xray_install_path
    xray_install_path="$(config_get_constant "xray_install_path" "/opt/xray")"
    
    if [[ -f "$xray_install_path/xray" ]]; then
        local version
        version="$("$xray_install_path/xray" version | head -n1 | awk '{print $2}')"
        echo "Xray Core: $version (установлен)"
    else
        echo "Xray Core: не установлен"
    fi
    
    if systemctl is-enabled xray >/dev/null 2>&1; then
        echo "Systemd сервис: включен"
    else
        echo "Systemd сервис: отключен"
    fi
}

# === Экспорт функций ===
export -f core_init core_install core_setup_systemd core_remove core_status

# Автоматическая инициализация при загрузке компонента
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Если скрипт запущен напрямую
    core_init "$@"
else
    # Если скрипт загружен как компонент
    core_init
fi
