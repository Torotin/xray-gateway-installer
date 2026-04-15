#!/usr/bin/env bash

# === Компонент конфигурации Xray ===
# Версия: 2.0.0
# Автор: Xray Gateway Installer Team

# === Инициализация компонента ===
config_init() {
    log INFO "Инициализация компонента конфигурации Xray"
    log OK "Компонент конфигурации Xray инициализирован"
    return 0
}

config_get_template_dir() {
    echo "${SCRIPT_DIR}/templates/xray-base"
}

config_render_template_file() {
    local template_path="$1"
    local destination_path="$2"
    shift 2

    [[ -f "$template_path" ]] || return 1

    local temp_file
    temp_file="$(mktemp)"
    cp "$template_path" "$temp_file"

    local replacement
    for replacement in "$@"; do
        sed -i "$replacement" "$temp_file"
    done

    mv "$temp_file" "$destination_path"
}

config_has_xray_unit() {
    if systemctl list-unit-files xray.service --no-legend >/dev/null 2>&1; then
        return 0
    fi

    local fragment_path=""
    fragment_path="$(systemctl show -p FragmentPath --value xray.service 2>/dev/null || true)"
    [[ -n "$fragment_path" ]]
}

# === Очистка логов xray.service ===
config_clear_logs() {
    log INFO "Очистка логов xray.service"
    
    if config_has_xray_unit; then
        # Очистка systemd журнала
        journalctl --unit=xray.service --rotate 2>/dev/null || true
        journalctl --unit=xray.service --vacuum-time=1s 2>/dev/null || true
        
        # Очистка логов из /var/log
        rm -f /var/log/xray*.log 2>/dev/null || true
        rm -f /var/log/xray/*.log 2>/dev/null || true
        
        # Очистка логов из директории установки
        local xray_install_path
        xray_install_path="$(config_get_constant "xray_install_path" "/opt/xray")"
        rm -f "$xray_install_path/logs/*.log" 2>/dev/null || true
        rm -f "$xray_install_path/*.log" 2>/dev/null || true
        
        log OK "Логи xray.service очищены"
    fi
}

# === Создание базовых конфигураций ===
config_create_base() {
    log INFO "Создание базовых конфигураций Xray"
    
    # Получение переменных конфигурации
    local xray_install_path xray_user xray_group xray_log_path xray_configs_path
    xray_install_path="$(config_get_constant "xray_install_path" "/opt/xray")"
    xray_user="$(config_get_constant "xray_user" "xray")"
    xray_group="$(config_get_constant "xray_group" "xray")"
    xray_log_path="$(config_get_constant "xray_log_path" "$xray_install_path/logs")"
    xray_configs_path="$(config_get_constant "xray_configs_path" "$xray_install_path/configs")"
    
    log DEBUG "Переменные конфигурации: user=$xray_user, group=$xray_group, log_path=$xray_log_path, configs_path=$xray_configs_path"
    
    # Убедимся, что директория существует
    if [[ ! -d "$xray_configs_path" ]]; then
        log ERROR "Директория конфигураций отсутствует: $xray_configs_path"
        log INFO "Попытка создания директории конфигураций"
        if ! mkdir -p "$xray_configs_path" 2>/dev/null; then
            log ERROR "Не удалось создать директорию конфигураций: $xray_configs_path"
            return 1
        fi
        log OK "Директория конфигураций создана: $xray_configs_path"
    fi

    local existing_json_files=()
    while IFS= read -r -d '' json_file; do
        existing_json_files+=("$json_file")
    done < <(find "$xray_configs_path" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null)

    if [[ ${#existing_json_files[@]} -gt 0 ]]; then
        local backup_dir="${xray_install_path}/config-backups/preserved-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"

        local existing_json
        for existing_json in "${existing_json_files[@]}"; do
            cp -p "$existing_json" "$backup_dir/"
        done

        chown "$xray_user:$xray_group" "${existing_json_files[@]}"
        chmod 644 "${existing_json_files[@]}"

        log WARN "Найдены существующие JSON-конфиги Xray: ${#existing_json_files[@]} шт."
        log WARN "Оригинальные конфиги сохранены без изменений; snapshot-копия создана в: $backup_dir"
        log INFO "Генерация базовых конфигов пропущена, так как пользовательские конфиги уже присутствуют"
        return 0
    fi
    
    local tproxy_port redirect_port template_dir
    tproxy_port="$(config_get_constant "firewall.tproxy_port" "12345")"
    redirect_port="$(config_get_constant "firewall.redirect_port" "12346")"
    template_dir="$(config_get_template_dir)"

    # Создание API-конфига
    local json_api="$xray_configs_path/00_api.json"
    if [[ -f "$template_dir/00_api.template.json" ]]; then
        if ! config_render_template_file "$template_dir/00_api.template.json" "$json_api"; then
            log ERROR "Ошибка рендеринга шаблона: $template_dir/00_api.template.json"
            return 1
        fi
    elif ! cat > "$json_api" <<EOF
{}
EOF
    then
        log ERROR "Ошибка записи в файл: $json_api"
        return 1
    fi

    if [[ -f "$json_api" ]]; then
        log OK "Конфигурационный файл создан: $json_api"
    else
        log ERROR "Файл $json_api не был создан"
        return 1
    fi

    # Создание лог-конфига
    local json_log="$xray_configs_path/01_log.json"
    if [[ -f "$template_dir/01_log.template.json" ]]; then
        if ! config_render_template_file \
            "$template_dir/01_log.template.json" \
            "$json_log" \
            "s|__XRAY_LOG_PATH__|$xray_log_path|g"
        then
            log ERROR "Ошибка рендеринга шаблона: $template_dir/01_log.template.json"
            return 1
        fi
    elif ! cat > "$json_log" <<EOF
{
    "log": {
        "access": "$xray_log_path/access.log",
        "error": "$xray_log_path/error.log",
        "loglevel": "info",
        "dnsLog": true,
        "maskAddress": "quarter"
    }
}
EOF
    then
        log ERROR "Ошибка записи в файл: $json_log"
        return 1
    fi
    
    if [[ -f "$json_log" ]]; then
        log OK "Конфигурационный файл создан: $json_log"
    else
        log ERROR "Файл $json_log не был создан"
        return 1
    fi
    
    # Создание базового DNS-конфига
    local json_dns="$xray_configs_path/02_dns.json"
    if [[ -f "$template_dir/02_dns.template.json" ]]; then
        if ! config_render_template_file "$template_dir/02_dns.template.json" "$json_dns"; then
            log ERROR "Ошибка рендеринга шаблона: $template_dir/02_dns.template.json"
            return 1
        fi
    elif ! cat > "$json_dns" <<EOF
{
    "dns": {
        "servers": [
            "https+local://1.1.1.1/dns-query",
            "https+local://1.0.0.1/dns-query",
            "https+local://8.8.8.8/dns-query",
            "https+local://8.8.4.4/dns-query"
        ],
        "queryStrategy": "UseIPv4",
        "disableFallbackIfMatch": true
    }
}
EOF
    then
        log ERROR "Ошибка записи в файл: $json_dns"
        return 1
    fi

    if [[ -f "$json_dns" ]]; then
        log OK "Конфигурационный файл создан: $json_dns"
    else
        log ERROR "Файл $json_dns не был создан"
        return 1
    fi

    # Создание политик
    local json_policy="$xray_configs_path/07_policy.json"
    if [[ -f "$template_dir/07_policy.template.json" ]]; then
        if ! config_render_template_file "$template_dir/07_policy.template.json" "$json_policy"; then
            log ERROR "Ошибка рендеринга шаблона: $template_dir/07_policy.template.json"
            return 1
        fi
    elif ! cat > "$json_policy" <<EOF
{
        "policy": {
        "levels": {
            "0": {
                "handshake": 4,
                "connIdle": 300,
                "uplinkOnly": 0,
                "downlinkOnly": 0,
                "statsUserUplink": false,
                "statsUserDownlink": false,
                "statsUserOnline": false
            }
        },
        "system": {
            "statsInboundUplink": false,
            "statsInboundDownlink": false,
            "statsOutboundUplink": false,
            "statsOutboundDownlink": false
        }
    }
}
EOF
    then
        log ERROR "Ошибка записи в файл: $json_policy"
        return 1
    fi
    
    if [[ -f "$json_policy" ]]; then
        log OK "Конфигурационный файл создан: $json_policy"
    else
        log ERROR "Файл $json_policy не был создан"
        return 1
    fi
    
    # Создание inbounds для TProxy и Redirect
    local json_inbounds="$xray_configs_path/03_inbounds.json"
    if [[ -f "$template_dir/03_inbounds.template.json" ]]; then
        if ! config_render_template_file \
            "$template_dir/03_inbounds.template.json" \
            "$json_inbounds" \
            "s|__TPROXY_PORT__|$tproxy_port|g" \
            "s|__REDIRECT_PORT__|$redirect_port|g"
        then
            log ERROR "Ошибка рендеринга шаблона: $template_dir/03_inbounds.template.json"
            return 1
        fi
    elif ! cat > "$json_inbounds" <<EOF
{
    "inbounds": [
        {
            "port": $tproxy_port,
            "protocol": "dokodemo-door",
            "settings": {
                "network": "udp",
                "followRedirect": true
            },
            "streamSettings": {
                "sockopt": {
                    "tproxy": "tproxy",
                    "mark": 1
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ]
            },
            "tag": "tproxy"
        },
        {
            "port": $redirect_port,
            "protocol": "dokodemo-door",
            "settings": {
                "network": "tcp",
                "followRedirect": true
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls"
                ]
            },
            "tag": "redirect"
        }
    ]
}
EOF
    then
        log ERROR "Ошибка записи в файл: $json_inbounds"
        return 1
    fi
    
    if [[ -f "$json_inbounds" ]]; then
        log OK "Конфигурационный файл создан: $json_inbounds"
    else
        log ERROR "Файл $json_inbounds не был создан"
        return 1
    fi

    # Создание outbounds
    local json_outbounds="$xray_configs_path/04_outbounds.json"
    if [[ -f "$template_dir/04_outbounds.template.json" ]]; then
        if ! config_render_template_file "$template_dir/04_outbounds.template.json" "$json_outbounds"; then
            log ERROR "Ошибка рендеринга шаблона: $template_dir/04_outbounds.template.json"
            return 1
        fi
    elif ! cat > "$json_outbounds" <<EOF
{
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {},
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "settings": {},
            "tag": "block"
        },
        {
            "protocol": "dns",
            "tag": "dns-out"
        }
    ]
}
EOF
    then
        log ERROR "Ошибка записи в файл: $json_outbounds"
        return 1
    fi

    if [[ -f "$json_outbounds" ]]; then
        log OK "Конфигурационный файл создан: $json_outbounds"
    else
        log ERROR "Файл $json_outbounds не был создан"
        return 1
    fi

    # Создание routing
    local json_routing="$xray_configs_path/05_routing.json"
    if [[ -f "$template_dir/05_routing.template.json" ]]; then
        if ! config_render_template_file "$template_dir/05_routing.template.json" "$json_routing"; then
            log ERROR "Ошибка рендеринга шаблона: $template_dir/05_routing.template.json"
            return 1
        fi
    elif ! cat > "$json_routing" <<EOF
{
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "inboundTag": [
                    "dns-in"
                ],
                "outboundTag": "dns-out"
            },
            {
                "type": "field",
                "ip": [
                    "geoip:private"
                ],
                "outboundTag": "direct"
            },
            {
                "type": "field",
                "domain": [
                    "geosite:private"
                ],
                "outboundTag": "direct"
            }
        ]
    }
}
EOF
    then
        log ERROR "Ошибка записи в файл: $json_routing"
        return 1
    fi

    if [[ -f "$json_routing" ]]; then
        log OK "Конфигурационный файл создан: $json_routing"
    else
        log ERROR "Файл $json_routing не был создан"
        return 1
    fi

    # Создание observatory-конфига
    local json_observatory="$xray_configs_path/06_observatory.json"
    if [[ -f "$template_dir/06_observatory.template.json" ]]; then
        if ! config_render_template_file "$template_dir/06_observatory.template.json" "$json_observatory"; then
            log ERROR "Ошибка рендеринга шаблона: $template_dir/06_observatory.template.json"
            return 1
        fi
    elif ! cat > "$json_observatory" <<EOF
{}
EOF
    then
        log ERROR "Ошибка записи в файл: $json_observatory"
        return 1
    fi

    if [[ -f "$json_observatory" ]]; then
        log OK "Конфигурационный файл создан: $json_observatory"
    else
        log ERROR "Файл $json_observatory не был создан"
        return 1
    fi
    
    # Установка прав доступа
    chown "$xray_user:$xray_group" "$xray_configs_path"/*.json
    chmod 644 "$xray_configs_path"/*.json
    
    log OK "Базовые конфигурации созданы"
}

# === Настройка логирования ===
config_setup_logging() {
    log INFO "Создание пустых лог-файлов и очистка systemd-журналов"
    
    # Получение переменных конфигурации
    local xray_install_path xray_user xray_group xray_log_path
    xray_install_path="$(config_get_constant "xray_install_path" "/opt/xray")"
    xray_user="$(config_get_constant "xray_user" "xray")"
    xray_group="$(config_get_constant "xray_group" "xray")"
    xray_log_path="$(config_get_constant "xray_log_path" "$xray_install_path/logs")"
    
    local access_log="$xray_log_path/access.log"
    local error_log="$xray_log_path/error.log"
    
    # Создание лог-файлов
    if command install -o "$xray_user" -g "$xray_group" -m 640 /dev/null "$access_log" && \
       command install -o "$xray_user" -g "$xray_group" -m 640 /dev/null "$error_log"; then
        log OK "Лог-файлы созданы: $access_log, $error_log"
    else
        log ERROR "Не удалось создать лог-файлы в $xray_log_path"
        return 1
    fi
    
    # Очистка systemd-журнала (если сервис существует)
    if config_has_xray_unit; then
        log INFO "Очистка systemd журнала для xray.service"
        if journalctl --unit=xray.service --rotate 2>/dev/null && \
           journalctl --unit=xray.service --vacuum-time=1s 2>/dev/null; then
            log OK "Журналы systemd очищены"
        else
            log WARN "Не удалось очистить systemd journal для xray (сервис может не существовать)"
        fi
    fi
}

# === Валидация конфигурации Xray ===
config_validate_xray() {
    log INFO "Проверка конфигурации Xray"
    
    # Получение переменных конфигурации
    local xray_bin="/usr/local/bin/xray"
    local xray_configs_path
    xray_configs_path="$(config_get_constant "xray_configs_path" "/opt/xray/configs")"
    
    if [[ ! -x "$xray_bin" ]]; then
        log ERROR "Не найден бинарник Xray: $xray_bin"
        return 1
    fi
    
    if [[ ! -d "$xray_configs_path" ]]; then
        log ERROR "Каталог конфигурации не найден: $xray_configs_path"
        return 1
    fi
    
    log INFO "Проверка конфигурации через $xray_bin -test -confdir $xray_configs_path"
    
    if "$xray_bin" run -test -confdir "$xray_configs_path" &> >(tee /tmp/xray-test.log); then
        log OK "Конфигурация Xray прошла проверку успешно"
        return 0
    else
        log ERROR "Xray обнаружил ошибки в конфигурации:"
        sed 's/^/    └─ /' /tmp/xray-test.log
        return 1
    fi
}

# === Включение и запуск сервиса ===
config_enable_service() {
    log INFO "Активация и запуск xray.service"
    
    # Получение переменных конфигурации
    local xray_install_path
    xray_install_path="$(config_get_constant "xray_install_path" "/opt/xray")"
    
    # Валидация конфигурации перед запуском
    if ! config_validate_xray; then
        log ERROR "Валидация конфигурации Xray не прошла"
        return 1
    fi
    
    log INFO "Проверка владельца каталога конфигурации"
    ls -ld "$xray_install_path"
    
    log INFO "Перезапуск systemd-демонов"
    systemctl daemon-reexec && systemctl daemon-reload && log OK "Systemd перезапущен" || {
        log ERROR "Не удалось перезапустить systemd"
        return 1
    }
    
    log INFO "Включение автозапуска Xray"
    systemctl enable xray.service && log OK "Xray добавлен в автозагрузку" || {
        log ERROR "Не удалось включить автозапуск Xray"
        return 1
    }
    
    # Очистка логов перед запуском
    config_clear_logs
    
    log INFO "Запуск Xray"
    if systemctl restart xray.service; then
        log OK "Xray запущен"
    else
        log ERROR "Ошибка запуска Xray"
        journalctl --no-pager -xeu xray.service
        systemctl status xray.service --no-pager
        return 1
    fi
    
    log INFO "Проверка статуса xray.service"
    if systemctl is-active --quiet xray.service; then
        log OK "Xray работает корректно"
    else
        log ERROR "Xray не активен после запуска"
        return 1
    fi
}

# === Удаление конфигураций ===
config_remove() {
    log INFO "Удаление конфигураций Xray"
    
    # Получение переменных конфигурации
    local xray_install_path
    xray_install_path="$(config_get_constant "xray_install_path" "/opt/xray")"
    
    # Остановка сервиса
    systemctl stop xray 2>/dev/null || true
    
    # Удаление конфигураций
    if [[ -d "$xray_install_path/configs" ]]; then
        rm -rf "$xray_install_path/configs"
        log OK "Конфигурации удалены"
    fi
    
    if [[ -d "$xray_install_path/logs" ]]; then
        rm -rf "$xray_install_path/logs"
        log OK "Логи удалены"
    fi
}

# === Статус конфигураций ===
config_status() {
    # Получение переменных конфигурации
    local xray_install_path
    xray_install_path="$(config_get_constant "xray_install_path" "/opt/xray")"
    
    echo "=== Статус Xray ==="
    
    # Проверка исполняемого файла
    if [[ -x "/usr/local/bin/xray" ]]; then
        echo "Исполняемый файл: /usr/local/bin/xray (найден)"
        echo "  Размер: $(du -h /usr/local/bin/xray | cut -f1)"
        echo "  Права: $(ls -l /usr/local/bin/xray | awk '{print $1}')"
        echo "  Владелец: $(ls -l /usr/local/bin/xray | awk '{print $3":"$4}')"
        echo "  Версия: $(/usr/local/bin/xray version 2>/dev/null | head -1 || echo "неизвестна")"
    else
        echo "Исполняемый файл: /usr/local/bin/xray (не найден)"
    fi
    
    echo
    
    # Проверка конфигураций
    local config_files=(
        "$xray_install_path/configs/00_api.json"
        "$xray_install_path/configs/01_log.json"
        "$xray_install_path/configs/02_dns.json"
        "$xray_install_path/configs/03_inbounds.json"
        "$xray_install_path/configs/04_outbounds.json"
        "$xray_install_path/configs/05_routing.json"
        "$xray_install_path/configs/06_observatory.json"
        "$xray_install_path/configs/07_policy.json"
    )
    
    echo "Конфигурационные файлы:"
    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
            echo "  ✅ $(basename "$config_file") - $(du -h "$config_file" | cut -f1)"
        else
            echo "  ❌ $(basename "$config_file") - отсутствует"
        fi
    done
    
    echo
    
    # Проверка символической ссылки
    if [[ -L "/usr/local/share/xray" ]]; then
        echo "Символическая ссылка: /usr/local/share/xray → $(readlink /usr/local/share/xray)"
    else
        echo "Символическая ссылка: /usr/local/share/xray (отсутствует)"
    fi
    
    echo
    
    # Проверка сервиса
    if systemctl is-active xray >/dev/null 2>&1; then
        echo "Сервис: активен (PID: $(systemctl show xray --property=MainPID --value))"
        echo "  Время запуска: $(systemctl show xray --property=ActiveEnterTimestamp --value)"
        echo "  Память: $(systemctl show xray --property=MemoryCurrent --value 2>/dev/null | numfmt --to=iec || echo "неизвестно")"
    else
        echo "Сервис: неактивен"
        if systemctl is-failed xray >/dev/null 2>&1; then
            echo "  Статус: failed"
        fi
    fi
    
    echo
    
    # Проверка логов
    local log_files=(
        "$xray_install_path/logs/access.log"
        "$xray_install_path/logs/error.log"
    )
    
    echo "Лог-файлы:"
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            echo "  📄 $(basename "$log_file") - $(du -h "$log_file" | cut -f1) ($(wc -l < "$log_file") строк)"
        else
            echo "  📄 $(basename "$log_file") - отсутствует"
        fi
    done
}

# === Экспорт функций ===
export -f config_init config_render_template_file config_has_xray_unit config_clear_logs config_create_base config_setup_logging config_validate_xray config_enable_service config_remove config_status

# Автоматическая инициализация при загрузке компонента
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Если скрипт запущен напрямую
    config_init "$@"
else
    # Если скрипт загружен как компонент
    config_init
fi
