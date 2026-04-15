#!/usr/bin/env bash

# === Плагин управления файрволом Xray Gateway Installer ===
# Версия: 2.0.0
# Автор: Xray Gateway Installer Team

# Загрузка зависимостей
declare -g FIREWALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Инициализация логгера
if [[ -f "$FIREWALL_SCRIPT_DIR/core/02_logger.sh" ]]; then
    source "$FIREWALL_SCRIPT_DIR/core/02_logger.sh"
    # НЕ инициализируем основной логгер, только загружаем функции
fi

# Инициализация конфигурации
if [[ -f "$FIREWALL_SCRIPT_DIR/core/01_config_manager.sh" ]]; then
    source "$FIREWALL_SCRIPT_DIR/core/01_config_manager.sh"
    config_init "$FIREWALL_SCRIPT_DIR"
fi

# Инициализация утилит
if [[ -f "$FIREWALL_SCRIPT_DIR/core/03_utils.sh" ]]; then
    source "$FIREWALL_SCRIPT_DIR/core/03_utils.sh"
fi

# Глобальные переменные плагина
declare -g FIREWALL_SCRIPT_PATH=""
declare -g FIREWALL_UNIT_NAME="xray-iptables.service"
declare -g FIREWALL_RESTART_UNIT_NAME="xray-iptables-restart.service"
declare -g MARK_ID
declare -g ROUTE_TABLE_ID
declare -g TPROXY_PORT
declare -g REDIRECT_PORT
declare -g FIREWALL_DEFAULT_MODE="tcp-only"
declare -g FIREWALL_GATEWAY_MODE="inline-lan"
declare -g FIREWALL_INTERCEPT_INTERFACES=""
declare -g FIREWALL_SOURCE_CIDRS=""
declare -g FIREWALL_SOURCE_IPS=""

# === Инициализация плагина ===
plugin_firewall_init() {
    # Инициализация логирования для плагина
    plugin_logger_init "firewall" "_logs" "append"
    
    log INFO "Инициализация плагина управления файрволом"
    
    # Проверка инициализации конфигурации
    if ! declare -f config_get_constant >/dev/null 2>&1; then
        log ERROR "Конфигурация не инициализирована"
        return 1
    fi
    
    # Загрузка конфигурации
    local xray_install_path
    xray_install_path="$(config_get_constant "xray_install_path" "/opt/xray")"
    FIREWALL_SCRIPT_PATH="${xray_install_path}/iptables/xray-iptables.sh"
    MARK_ID="$(config_get_plugin "firewall" "mark_id" 2>/dev/null || config_get_constant "firewall.mark_id" 2>/dev/null || echo "0x1001")"
    ROUTE_TABLE_ID="$(config_get_plugin "firewall" "route_table_id" 2>/dev/null || config_get_constant "firewall.route_table_id" 2>/dev/null || echo "233")"
    TPROXY_PORT="$(config_get_plugin "firewall" "tproxy_port" 2>/dev/null || config_get_constant "firewall.tproxy_port" 2>/dev/null || echo "12345")"
    REDIRECT_PORT="$(config_get_plugin "firewall" "redirect_port" 2>/dev/null || config_get_constant "firewall.redirect_port" 2>/dev/null || echo "12346")"
    FIREWALL_GATEWAY_MODE="$(config_get_plugin "firewall" "gateway_mode" 2>/dev/null || echo "inline-lan")"
    FIREWALL_INTERCEPT_INTERFACES="$(config_get_plugin "firewall" "intercept_interfaces" 2>/dev/null || echo "")"
    FIREWALL_SOURCE_CIDRS="$(config_get_plugin "firewall" "source_cidrs" 2>/dev/null || echo "")"
    FIREWALL_SOURCE_IPS="$(config_get_plugin "firewall" "source_ips" 2>/dev/null || echo "")"
    XRAY_GID="$(config_get_constant "xray_gid" 2>/dev/null || echo "1001")"
    XRAY_CONFIG_DIR="$(config_get_constant "xray_configs_path" 2>/dev/null || echo "/opt/xray/configs")"
    
    log OK "Плагин управления файрволом инициализирован"
}

# === Выполнение плагина ===
plugin_firewall_execute() {
    local action="$1"
    shift
    local args=("$@")
    
    case "$action" in
        "install")
            firewall_install "${args[@]}"
            ;;
        "uninstall")
            firewall_uninstall "${args[@]}"
            ;;
        "status")
            firewall_status "${args[@]}"
            ;;
        "start")
            firewall_start "${args[@]}"
            ;;
        "stop")
            firewall_stop "${args[@]}"
            ;;
        "restart")
            firewall_restart "${args[@]}"
            ;;
        "enable")
            firewall_enable "${args[@]}"
            ;;
        "disable")
            firewall_disable "${args[@]}"
            ;;
        "diagnose")
            firewall_diagnose "${args[@]}"
            ;;
        *)
            log ERROR "Неизвестное действие: $action"
            return 1
            ;;
    esac
}

# === Статус плагина ===
plugin_firewall_status() {
    log INFO "Проверка статуса файрвола..."
    
    # Получение пути установки Xray из конфигурации
    local xray_install_path
    xray_install_path="$(config_get_constant "xray_install_path" "/opt/xray")"
    
    # Проверка наличия скрипта iptables
    local firewall_script="${xray_install_path}/iptables/xray-iptables.sh"
    if [[ -f "$firewall_script" ]]; then
        log OK "Скрипт iptables найден: $firewall_script"
    else
        log WARN "Скрипт iptables не найден: $firewall_script"
    fi
    
    # Проверка systemd юнитов
    if systemctl is-enabled xray-iptables >/dev/null 2>&1; then
        log OK "Юнит xray-iptables включен"
    else
        log WARN "Юнит xray-iptables не включен"
    fi
    
    if systemctl is-enabled xray-iptables-restart >/dev/null 2>&1; then
        log OK "Юнит xray-iptables-restart включен"
    else
        log WARN "Юнит xray-iptables-restart не включен"
    fi
    
    # Проверка правил iptables
    local xray_chain="XRAY"
    if iptables -t mangle -L "$xray_chain" >/dev/null 2>&1; then
        log OK "Цепочка iptables $xray_chain существует"
    else
        log WARN "Цепочка iptables $xray_chain не найдена"
    fi
}

# === Зависимости плагина ===
plugin_firewall_dependencies() {
    echo "network system xray"
}

# === Информация о плагине ===
plugin_firewall_info() {
    echo "Плагин управления файрволом и kill-switch функциональностью"
}

firewall_ensure_runtime_paths() {
    if [[ -n "${FIREWALL_SCRIPT_PATH:-}" ]]; then
        return 0
    fi

    local xray_install_path
    xray_install_path="$(config_get_constant "xray_install_path" "/opt/xray")"
    FIREWALL_SCRIPT_PATH="${xray_install_path}/iptables/xray-iptables.sh"
}

firewall_run_runtime_script() {
    local action="$1"

    firewall_ensure_runtime_paths

    if [[ ! -f "$FIREWALL_SCRIPT_PATH" ]]; then
        log WARN "Скрипт файрвола не найден: $FIREWALL_SCRIPT_PATH"
        return 1
    fi

    if [[ -x "$FIREWALL_SCRIPT_PATH" ]]; then
        "$FIREWALL_SCRIPT_PATH" "$action"
    else
        bash "$FIREWALL_SCRIPT_PATH" "$action"
    fi
}

# === Установка плагина ===
firewall_install() {
    log INFO "Установка плагина файрвола"
    
    # Определение сетевых интерфейсов
    detect_interfaces
    
    # Принудительное использование iptables-legacy
    firewall_force_legacy
    
    # Создание скрипта управления iptables
    firewall_create_script
    
    # Создание systemd юнитов
    firewall_create_systemd_units
    
    # Создание дополнительных systemd юнитов для kill-switch
    firewall_create_killswitch_units
    
    # Копирование скриптов переключения
    firewall_copy_switch_scripts

    if systemctl restart "$FIREWALL_UNIT_NAME"; then
        log OK "Файрвол приведён к целевому runtime-состоянию"
    else
        log WARN "Не удалось автоматически запустить $FIREWALL_UNIT_NAME"
    fi
    
    log OK "Плагин файрвола установлен"
}

# === Удаление плагина ===
firewall_uninstall() {
    log INFO "Удаление плагина файрвола"
    
    # Инициализация переменных если не была выполнена
    if [[ -z "${FIREWALL_SCRIPT_PATH:-}" ]]; then
        local xray_install_path
        xray_install_path="$(config_get_constant "xray_install_path" "/opt/xray")"
        FIREWALL_SCRIPT_PATH="${xray_install_path}/iptables/xray-iptables.sh"
    fi
    
    # Остановка скрипта файрвола
    if [[ -f "$FIREWALL_SCRIPT_PATH" ]]; then
        firewall_run_runtime_script stop 2>/dev/null || true
        log OK "Правила iptables очищены"
    fi
    
    # Полная очистка цепочек iptables
    firewall_stop
    
    # Остановка и удаление systemd юнитов
    systemctl stop "$FIREWALL_UNIT_NAME" 2>/dev/null || true
    systemctl disable "$FIREWALL_UNIT_NAME" 2>/dev/null || true
    systemctl stop "$FIREWALL_RESTART_UNIT_NAME" 2>/dev/null || true
    systemctl disable "$FIREWALL_RESTART_UNIT_NAME" 2>/dev/null || true
    systemctl stop xray-killswitch-monitor.service 2>/dev/null || true
    systemctl disable xray-killswitch-monitor.service 2>/dev/null || true
    systemctl stop xray-killswitch-watchdog.service 2>/dev/null || true
    systemctl disable xray-killswitch-watchdog.service 2>/dev/null || true
    systemctl reset-failed \
        "$FIREWALL_UNIT_NAME" \
        "$FIREWALL_RESTART_UNIT_NAME" \
        xray-killswitch-monitor.service \
        xray-killswitch-watchdog.service \
        2>/dev/null || true
    rm -f "/etc/systemd/system/$FIREWALL_UNIT_NAME"
    rm -f "/etc/systemd/system/$FIREWALL_RESTART_UNIT_NAME"
    rm -f "/etc/systemd/system/xray-killswitch-monitor.service"
    rm -f "/etc/systemd/system/xray-killswitch-watchdog.service"
    systemctl daemon-reload
    
    # Удаление скриптов и runtime-файлов
    local script_dir
    script_dir="$(dirname "$FIREWALL_SCRIPT_PATH")"
    rm -f "$FIREWALL_SCRIPT_PATH"
    rm -f "$script_dir/xray-iptables.mode"
    rm -f "$script_dir/xray-policy-iptables.interfaces"
    rm -f "$script_dir/xray-policy-iptables.cidrs"
    rm -f "$script_dir/xray-policy-iptables.ips"
    rm -f "$script_dir/xray-exclude-iptables.cidrs"
    rm -f "$script_dir/xray-exclude-iptables.ips"
    rm -f "$script_dir/xray-exclude-iptables.ports"
    rm -f "$script_dir/killswitch-watchdog.sh"
    rm -f "$script_dir/switch-to-disabled.sh"
    rm -f "$script_dir/switch-to-enabled.sh"

    if [[ -d "$script_dir" ]]; then
        rmdir "$script_dir" 2>/dev/null || true
    fi
    
    log OK "Плагин файрвола удален"
}

# === Статус плагина ===
firewall_status() {
    log INFO "Статус плагина файрвола"

    firewall_ensure_runtime_paths
    
    if [[ -f "$FIREWALL_SCRIPT_PATH" ]]; then
        log OK "Скрипт файрвола: $FIREWALL_SCRIPT_PATH"
    else
        log WARN "Скрипт файрвола не найден: $FIREWALL_SCRIPT_PATH"
    fi
    
    if systemctl is-active "$FIREWALL_UNIT_NAME" >/dev/null 2>&1; then
        log OK "Сервис файрвола активен"
    else
        log WARN "Сервис файрвола неактивен"
    fi
}

# === Запуск файрвола ===
firewall_start() {
    log INFO "Запуск файрвола"

    firewall_ensure_runtime_paths
    
    if [[ -f "$FIREWALL_SCRIPT_PATH" ]]; then
        firewall_run_runtime_script start
        systemctl start "$FIREWALL_UNIT_NAME"
        log OK "Файрвол запущен"
    else
        log ERROR "Скрипт файрвола не найден: $FIREWALL_SCRIPT_PATH"
        return 1
    fi
}

# === Остановка файрвола ===
firewall_stop() {
    log INFO "Остановка файрвола"

    firewall_ensure_runtime_paths
    
    if [[ -f "$FIREWALL_SCRIPT_PATH" ]]; then
        firewall_run_runtime_script stop
        systemctl stop "$FIREWALL_UNIT_NAME"
        log OK "Файрвол остановлен"
    else
        log WARN "Скрипт файрвола не найден: $FIREWALL_SCRIPT_PATH"
    fi
    
    # Полная очистка цепочек iptables
    log INFO "Полная очистка цепочек iptables"
    
    # Удаление цепочек XRAY из всех таблиц
    for table in mangle nat filter; do
        for chain in XRAY XRAY_SELF XRAY_ENABLED XRAY_DISABLED XRAY_PREROUTING XRAY_NAT_PREROUTING; do
            if iptables -t "$table" -L "$chain" >/dev/null 2>&1; then
                iptables -t "$table" -F "$chain" 2>/dev/null || true
                iptables -t "$table" -X "$chain" 2>/dev/null || true
                log OK "Удалена цепочка $chain из таблицы $table"
            fi
        done
    done
    
    # Удаление правил из основных цепочек
    iptables -t mangle -D PREROUTING -j XRAY_ENABLED 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j XRAY_DISABLED 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j XRAY_PREROUTING 2>/dev/null || true
    iptables -t mangle -D OUTPUT -j XRAY_SELF 2>/dev/null || true
    iptables -t nat -D PREROUTING -j XRAY 2>/dev/null || true
    iptables -t nat -D PREROUTING -j XRAY_NAT_PREROUTING 2>/dev/null || true
    
    log OK "Цепочки iptables полностью очищены"
}

# === Перезапуск файрвола ===
firewall_restart() {
    log INFO "Перезапуск файрвола"
    
    firewall_stop
    sleep 1
    firewall_start
}

# === Переключение в активный режим ===
firewall_enable() {
    log INFO "Переключение файрвола в активный режим"
    
    firewall_ensure_runtime_paths
    
    if [[ -f "$FIREWALL_SCRIPT_PATH" ]]; then
        firewall_run_runtime_script enable
        log OK "Файрвол переключен в активный режим"
    else
        log ERROR "Скрипт файрвола не найден: $FIREWALL_SCRIPT_PATH"
        return 1
    fi
}

# === Переключение в kill-switch режим ===
firewall_disable() {
    log INFO "Переключение файрвола в kill-switch режим"
    
    firewall_ensure_runtime_paths
    
    if [[ -f "$FIREWALL_SCRIPT_PATH" ]]; then
        firewall_run_runtime_script disable
        log OK "Файрвол переключен в kill-switch режим"
    else
        log ERROR "Скрипт файрвола не найден: $FIREWALL_SCRIPT_PATH"
        return 1
    fi
}

# === Диагностика файрвола ===
firewall_diagnose() {
    log INFO "Диагностика файрвола"

    firewall_ensure_runtime_paths
    
    if [[ -f "$FIREWALL_SCRIPT_PATH" ]]; then
        firewall_run_runtime_script diagnose
    else
        log ERROR "Скрипт файрвола не найден: $FIREWALL_SCRIPT_PATH"
        return 1
    fi
}

# === Принудительное использование iptables-legacy ===
firewall_force_legacy() {
    log INFO "Переключение на iptables-legacy"
    
    for tool in iptables ip6tables arptables ebtables; do
        local legacy_path="/usr/sbin/${tool}-legacy"
        if [[ -x "$legacy_path" ]]; then
            update-alternatives --install "/usr/sbin/$tool" "$tool" "$legacy_path" 100
            update-alternatives --set "$tool" "$legacy_path"
            log OK "$tool переключён на legacy-бэкенд"
        else
            log INFO "Пропуск $tool: legacy-бэкенд отсутствует"
        fi
    done
    
    # Проверка результата
    local backend
    backend=$(update-alternatives --query iptables | awk '/Value: / {print $2}')
    if [[ "$backend" != "/usr/sbin/iptables-legacy" ]]; then
        log ERROR "iptables не использует legacy-бэкенд: $backend"
        return 1
    else
        log OK "iptables работает в режиме legacy"
    fi
}

# === Создание скрипта управления iptables ===
firewall_create_script() {
    log INFO "Создание скрипта управления iptables"
    
    # Инициализация плагина если не была выполнена
    if [[ -z "${FIREWALL_SCRIPT_PATH:-}" ]]; then
        plugin_firewall_init
    fi
    
    # Создание директории для скрипта
    local script_dir="$(dirname "$FIREWALL_SCRIPT_PATH")"
    create_directory "$script_dir" "root" "root" "755"
    
    # Создание скрипта с правильной структурой
    cat > "$FIREWALL_SCRIPT_PATH" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

# === Скрипт управления iptables для Xray Gateway ===
# Этот скрипт генерируется плагином firewall

# Константы (будут заменены при генерации)
MARK_ID="__MARK_ID__"
ROUTE_TABLE_ID="__ROUTE_TABLE_ID__"
TPROXY_PORT="__TPROXY_PORT__"
REDIRECT_PORT="__REDIRECT_PORT__"
LAN_IF="__LAN_IF__"
WAN_IF="__WAN_IF__"
LOCAL_CIDRS="__LOCAL_CIDRS__"
XRAY_GID="__XRAY_GID__"
XRAY_CONFIG_DIR="__XRAY_CONFIG_DIR__"
FIREWALL_MODE="__FIREWALL_MODE__"
GATEWAY_MODE="__GATEWAY_MODE__"
INTERCEPT_INTERFACES_RAW="__INTERCEPT_INTERFACES__"
POLICY_SOURCE_CIDRS_RAW="__POLICY_SOURCE_CIDRS__"
POLICY_SOURCE_IPS_RAW="__POLICY_SOURCE_IPS__"
MODE_FILE="$(dirname "$0")/xray-iptables.mode"

# Инициализация переменных
LAN_IF="${LAN_IF:-}"
WAN_IF="${WAN_IF:-}"
LOCAL_CIDRS="${LOCAL_CIDRS:-}"
MARK_ID="${MARK_ID:-0x1001}"
ROUTE_TABLE_ID="${ROUTE_TABLE_ID:-233}"
TPROXY_PORT="${TPROXY_PORT:-}"
REDIRECT_PORT="${REDIRECT_PORT:-}"
XRAY_GID="${XRAY_GID:-1001}"
XRAY_CONFIG_DIR="${XRAY_CONFIG_DIR:-/opt/xray/configs}"
GATEWAY_MODE="${GATEWAY_MODE:-inline-lan}"
INTERCEPT_INTERFACES_RAW="${INTERCEPT_INTERFACES_RAW:-}"
POLICY_SOURCE_CIDRS_RAW="${POLICY_SOURCE_CIDRS_RAW:-}"
POLICY_SOURCE_IPS_RAW="${POLICY_SOURCE_IPS_RAW:-}"

# Имена цепочек
XRAY_CHAIN="XRAY"
XRAY_SELF_CHAIN="XRAY_SELF"
XRAY_ENABLED_CHAIN="XRAY_ENABLED"
XRAY_DISABLED_CHAIN="XRAY_DISABLED"

# Массивы для исключений
CUSTOM_BYPASS_CIDRS=()
CUSTOM_BYPASS_IPS=()
CUSTOM_BYPASS_PORTS=()
INTERCEPT_INTERFACES=()
POLICY_SOURCE_CIDRS=()
POLICY_SOURCE_IPS=()

# === Функция логирования ===
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [$level] [firewall] $message"
}

iptables() {
    command iptables -w 5 "$@"
}

append_unique() {
    local value="$1"
    shift
    local existing
    for existing in "$@"; do
        [[ "$existing" == "$value" ]] && return 0
    done
    return 1
}

parse_list_to_array() {
    local raw="$1"
    local -n out_ref="$2"
    local item

    out_ref=()
    while IFS= read -r item; do
        item="${item%%#*}"
        item="$(printf '%s' "$item" | xargs)"
        [[ -z "$item" ]] && continue
        if ! append_unique "$item" "${out_ref[@]}"; then
            out_ref+=("$item")
        fi
    done < <(printf '%s\n' "$raw" | tr ', ' '\n\n')
}

load_runtime_mode() {
    local selected_mode="${XRAY_IPTABLES_MODE:-}"

    if [[ -z "$selected_mode" && -f "$MODE_FILE" ]]; then
        selected_mode="$(tr -d '[:space:]' < "$MODE_FILE" 2>/dev/null || true)"
    fi

    if [[ -z "$selected_mode" ]]; then
        selected_mode="$FIREWALL_MODE"
    fi

    case "$selected_mode" in
        tcp-only|tcp-udp)
            FIREWALL_MODE="$selected_mode"
            ;;
        *)
            log WARN "Неизвестный режим '$selected_mode', используется tcp-only"
            FIREWALL_MODE="tcp-only"
            ;;
    esac

    log INFO "Режим файрвола: $FIREWALL_MODE"
}

# === Определение интерфейсов ===
detect_interfaces() {
    log INFO "Определение сетевых интерфейсов"
    
    # Определение WAN интерфейса
    WAN_IF=$(ip route | awk '/default/ {print $5}' | head -n1)
    if [[ -z "$WAN_IF" ]]; then
        log ERROR "Не удалось определить интерфейс с default route"
        exit 1
    else
        log OK "WAN_IF: $WAN_IF"
    fi
    
    # Определение LAN интерфейса
    if [[ -n "$LAN_IF" ]]; then
        log INFO "LAN_IF задан вручную: $LAN_IF"
    else
        LAN_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -Ev "^lo$|^$WAN_IF$" | head -n1)
        if [[ -n "$LAN_IF" ]]; then
            log OK "Обнаружен LAN_IF: $LAN_IF"
        else
            LAN_IF="$WAN_IF"
            log WARN "Второй интерфейс не найден, используется WAN_IF ($LAN_IF)"
        fi
    fi
    
    # Получение локальных CIDR
    log INFO "Получение локальных CIDR для интерфейсов $LAN_IF и $WAN_IF"
    local lan_cidrs wan_cidrs
    lan_cidrs=$(ip -o -f inet addr show "$LAN_IF" 2>/dev/null | awk '{print $4}')
    wan_cidrs=$(ip -o -f inet addr show "$WAN_IF" 2>/dev/null | awk '{print $4}')
    LOCAL_CIDRS=$(echo "$lan_cidrs $wan_cidrs" | xargs)
    
    if [[ -z "$LOCAL_CIDRS" ]]; then
        log ERROR "Не удалось получить локальные CIDR"
        exit 1
    else
        log OK "Найдены локальные подсети: $LOCAL_CIDRS"
    fi
}

# === Создание файлов исключений ===
ensure_exclusion_files_exist() {
    local base_dir="$(dirname "$0")"
    
    [[ -f "$base_dir/xray-exclude-iptables.cidrs" ]] || cat > "$base_dir/xray-exclude-iptables.cidrs" <<FIREWALL_EOF
# CIDR-сети, исключаемые из обработки
# Пример:
# 10.0.0.0/8
# 192.168.0.0/16
FIREWALL_EOF
    
    [[ -f "$base_dir/xray-exclude-iptables.ips" ]] || cat > "$base_dir/xray-exclude-iptables.ips" <<FIREWALL_EOF
# IP-адреса, исключаемые из обработки
# Пример:
# 8.8.8.8
# 1.1.1.1
FIREWALL_EOF
    
    [[ -f "$base_dir/xray-exclude-iptables.ports" ]] || cat > "$base_dir/xray-exclude-iptables.ports" <<FIREWALL_EOF
# TCP-порты, исключаемые из обработки
# Пример:
# 22     # SSH
# 443    # HTTPS
# 8080   # Локальный UI
FIREWALL_EOF
}

ensure_policy_files_exist() {
    local base_dir="$(dirname "$0")"

    [[ -f "$base_dir/xray-policy-iptables.interfaces" ]] || cat > "$base_dir/xray-policy-iptables.interfaces" <<'FIREWALL_EOF'
# Интерфейсы ingress для transparent interception
# Пример:
# eth0
# eth1
FIREWALL_EOF

    [[ -f "$base_dir/xray-policy-iptables.cidrs" ]] || cat > "$base_dir/xray-policy-iptables.cidrs" <<'FIREWALL_EOF'
# Исходные CIDR для policy-gateway
# Пример:
# 192.168.10.0/24
# 192.168.255.146/32
FIREWALL_EOF

    [[ -f "$base_dir/xray-policy-iptables.ips" ]] || cat > "$base_dir/xray-policy-iptables.ips" <<'FIREWALL_EOF'
# Исходные IP для policy-gateway
# Пример:
# 192.168.255.146
# 192.168.255.10
FIREWALL_EOF
}

load_policy_scope() {
    local base_dir="$(dirname "$0")"
    local interfaces_raw="$INTERCEPT_INTERFACES_RAW"
    local cidrs_raw="$POLICY_SOURCE_CIDRS_RAW"
    local ips_raw="$POLICY_SOURCE_IPS_RAW"

    [[ -f "$base_dir/xray-policy-iptables.interfaces" ]] && \
        interfaces_raw+=$'\n'"$(grep -vE '^\s*#|^\s*$' "$base_dir/xray-policy-iptables.interfaces" 2>/dev/null || true)"
    [[ -f "$base_dir/xray-policy-iptables.cidrs" ]] && \
        cidrs_raw+=$'\n'"$(grep -vE '^\s*#|^\s*$' "$base_dir/xray-policy-iptables.cidrs" 2>/dev/null || true)"
    [[ -f "$base_dir/xray-policy-iptables.ips" ]] && \
        ips_raw+=$'\n'"$(grep -vE '^\s*#|^\s*$' "$base_dir/xray-policy-iptables.ips" 2>/dev/null || true)"

    parse_list_to_array "$interfaces_raw" INTERCEPT_INTERFACES
    parse_list_to_array "$cidrs_raw" POLICY_SOURCE_CIDRS
    parse_list_to_array "$ips_raw" POLICY_SOURCE_IPS

    if [[ ${#INTERCEPT_INTERFACES[@]} -eq 0 ]]; then
        if [[ "$GATEWAY_MODE" == "policy-gateway" ]]; then
            INTERCEPT_INTERFACES=("$WAN_IF")
        else
            INTERCEPT_INTERFACES=("$LAN_IF")
        fi
    fi

    log INFO "Режим шлюза: $GATEWAY_MODE"
    log INFO "Ingress интерфейсы: ${INTERCEPT_INTERFACES[*]}"
    if [[ ${#POLICY_SOURCE_CIDRS[@]} -gt 0 || ${#POLICY_SOURCE_IPS[@]} -gt 0 ]]; then
        log INFO "Перехват ограничен по источникам: CIDR=${#POLICY_SOURCE_CIDRS[@]}, IP=${#POLICY_SOURCE_IPS[@]}"
    else
        log INFO "Перехват применяется ко всем источникам на ingress-интерфейсах"
    fi
}

disable_interface_redirects() {
    local iface
    local -a redirect_ifaces=()

    for iface in "$WAN_IF" "$LAN_IF" "${INTERCEPT_INTERFACES[@]}"; do
        [[ -z "$iface" ]] && continue
        if ! append_unique "$iface" "${redirect_ifaces[@]}"; then
            redirect_ifaces+=("$iface")
        fi
    done

    for iface in "${redirect_ifaces[@]}"; do
        if sysctl -w "net.ipv4.conf.${iface}.send_redirects=0" >/dev/null 2>&1; then
            log INFO "Отключён send_redirects на ${iface}"
        else
            log WARN "Не удалось отключить send_redirects на ${iface}"
        fi

        if sysctl -w "net.ipv4.conf.${iface}.accept_redirects=0" >/dev/null 2>&1; then
            log INFO "Отключён accept_redirects на ${iface}"
        else
            log WARN "Не удалось отключить accept_redirects на ${iface}"
        fi
    done
}

attach_enabled_hooks() {
    local iface source

    iptables -t mangle -N XRAY_PREROUTING 2>/dev/null || iptables -t mangle -F XRAY_PREROUTING
    iptables -t nat -N XRAY_NAT_PREROUTING 2>/dev/null || iptables -t nat -F XRAY_NAT_PREROUTING

    if [[ ${#POLICY_SOURCE_CIDRS[@]} -gt 0 || ${#POLICY_SOURCE_IPS[@]} -gt 0 ]]; then
        for source in "${POLICY_SOURCE_CIDRS[@]}"; do
            iptables -t mangle -A XRAY_PREROUTING -s "$source" -j XRAY_ENABLED
            iptables -t nat -A XRAY_NAT_PREROUTING -s "$source" -j $XRAY_CHAIN
        done
        for source in "${POLICY_SOURCE_IPS[@]}"; do
            iptables -t mangle -A XRAY_PREROUTING -s "$source" -j XRAY_ENABLED
            iptables -t nat -A XRAY_NAT_PREROUTING -s "$source" -j $XRAY_CHAIN
        done
    else
        iptables -t mangle -A XRAY_PREROUTING -j XRAY_ENABLED
        iptables -t nat -A XRAY_NAT_PREROUTING -j $XRAY_CHAIN
    fi

    for iface in "${INTERCEPT_INTERFACES[@]}"; do
        iptables -t mangle -D PREROUTING -i "$iface" -j XRAY_DISABLED 2>/dev/null || true
        iptables -t mangle -D PREROUTING -i "$iface" -j XRAY_PREROUTING 2>/dev/null || true
        iptables -t nat -D PREROUTING -i "$iface" -j XRAY_NAT_PREROUTING 2>/dev/null || true
        iptables -t mangle -A PREROUTING -i "$iface" -j XRAY_PREROUTING
        iptables -t nat -A PREROUTING -i "$iface" -j XRAY_NAT_PREROUTING
    done
}

attach_disabled_hooks() {
    local iface source

    iptables -t mangle -N XRAY_PREROUTING 2>/dev/null || iptables -t mangle -F XRAY_PREROUTING
    iptables -t nat -N XRAY_NAT_PREROUTING 2>/dev/null || iptables -t nat -F XRAY_NAT_PREROUTING
    iptables -t nat -F XRAY_NAT_PREROUTING

    if [[ ${#POLICY_SOURCE_CIDRS[@]} -gt 0 || ${#POLICY_SOURCE_IPS[@]} -gt 0 ]]; then
        for source in "${POLICY_SOURCE_CIDRS[@]}"; do
            iptables -t mangle -A XRAY_PREROUTING -s "$source" -j XRAY_DISABLED
        done
        for source in "${POLICY_SOURCE_IPS[@]}"; do
            iptables -t mangle -A XRAY_PREROUTING -s "$source" -j XRAY_DISABLED
        done
    else
        iptables -t mangle -A XRAY_PREROUTING -j XRAY_DISABLED
    fi

    for iface in "${INTERCEPT_INTERFACES[@]}"; do
        iptables -t nat -D PREROUTING -i "$iface" -j XRAY_NAT_PREROUTING 2>/dev/null || true
        iptables -t mangle -D PREROUTING -i "$iface" -j XRAY_DISABLED 2>/dev/null || true
        iptables -t mangle -D PREROUTING -i "$iface" -j XRAY_PREROUTING 2>/dev/null || true
        iptables -t mangle -A PREROUTING -i "$iface" -j XRAY_PREROUTING
    done
}

# === Загрузка исключений ===
load_custom_exclusions() {
    local base_dir="$(dirname "$0")"
    
    # Чтение из переменных окружения
    local cidrs_from_env=("${CUSTOM_BYPASS_CIDRS[@]}")
    local ips_from_env=("${CUSTOM_BYPASS_IPS[@]}")
    local ports_from_env=("${CUSTOM_BYPASS_PORTS[@]}")
    
    # Чтение из файлов
    [[ -f "$base_dir/xray-exclude-iptables.cidrs" ]] && \
        mapfile -t cidrs_from_file < <(grep -vE '^\s*#|^\s*$' "$base_dir/xray-exclude-iptables.cidrs")
    
    [[ -f "$base_dir/xray-exclude-iptables.ips" ]] && \
        mapfile -t ips_from_file < <(grep -vE '^\s*#|^\s*$' "$base_dir/xray-exclude-iptables.ips")
    
    [[ -f "$base_dir/xray-exclude-iptables.ports" ]] && \
        mapfile -t ports_from_file < <(grep -vE '^\s*#|^\s*$' "$base_dir/xray-exclude-iptables.ports")
    
    # Объединение и удаление дубликатов
    parse_list_to_array "$(printf "%s\n" "${cidrs_from_env[@]}" "${cidrs_from_file[@]}")" CUSTOM_BYPASS_CIDRS
    parse_list_to_array "$(printf "%s\n" "${ips_from_env[@]}" "${ips_from_file[@]}")" CUSTOM_BYPASS_IPS
    parse_list_to_array "$(printf "%s\n" "${ports_from_env[@]}" "${ports_from_file[@]}")" CUSTOM_BYPASS_PORTS
    
    log INFO "Загружено исключений:"
    log INFO "  ├─ CIDRs: ${#CUSTOM_BYPASS_CIDRS[@]}"
    log INFO "  ├─ IPs:   ${#CUSTOM_BYPASS_IPS[@]}"
    log INFO "  └─ Ports: ${#CUSTOM_BYPASS_PORTS[@]}"
}

# === Извлечение портов Xray ===
extract_xray_port_protocol() {
    local default_tproxy_port="${TPROXY_PORT:-}"
    local default_redirect_port="${REDIRECT_PORT:-}"
    local extracted_tproxy_port=""
    local extracted_redirect_port=""
    local dump_output=""

    if command -v /usr/local/bin/xray >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        dump_output="$(/usr/local/bin/xray run -dump -confdir "$XRAY_CONFIG_DIR" 2>/dev/null || true)"

        if [[ -n "$dump_output" ]]; then
            local python_result
            python_result="$(printf '%s' "$dump_output" | python3 -c '
import json
import sys

cfg = json.load(sys.stdin)
tproxy_port = ""
redirect_port = ""

for inbound in cfg.get("inbounds", []):
    if inbound.get("protocol") != "dokodemo-door":
        continue

    port = inbound.get("port")
    if port in (None, ""):
        continue

    network = str(inbound.get("settings", {}).get("network", "")).lower()
    tproxy_mode = inbound.get("streamSettings", {}).get("sockopt", {}).get("tproxy", "")
    tag = inbound.get("tag", "")

    if tproxy_mode == "tproxy" and "udp" in network:
        tproxy_port = str(port)
    elif tag == "redirect" and "tcp" in network:
        redirect_port = str(port)

print(f"{tproxy_port}\t{redirect_port}")
' 2>/dev/null || true)"

            if [[ -n "$python_result" ]]; then
                IFS=$'\t' read -r extracted_tproxy_port extracted_redirect_port <<< "$python_result"
            fi
        fi
    fi

    if [[ -z "$extracted_tproxy_port" || -z "$extracted_redirect_port" ]] && command -v jq >/dev/null 2>&1; then
        while IFS= read -r -d '' file; do
            while IFS= read -r entry; do
                local protocol tproxy port network tag
                protocol="$(printf '%s\n' "$entry" | jq -r '.protocol // empty')"
                tproxy="$(printf '%s\n' "$entry" | jq -r '.streamSettings.sockopt.tproxy // empty')"
                port="$(printf '%s\n' "$entry" | jq -r '.port // empty')"
                network="$(printf '%s\n' "$entry" | jq -r '.settings.network // empty' | tr '[:upper:]' '[:lower:]')"
                tag="$(printf '%s\n' "$entry" | jq -r '.tag // empty')"

                [[ -z "$port" || "$protocol" != "dokodemo-door" ]] && continue

                if [[ "$tproxy" == "tproxy" && "$network" == *udp* ]]; then
                    extracted_tproxy_port="$port"
                elif [[ -z "$tproxy" && "$network" == *tcp* && "$tag" == "redirect" ]]; then
                    extracted_redirect_port="$port"
                fi
            done < <(jq -c '.inbounds[]?' "$file" 2>/dev/null || true)
        done < <(find "$XRAY_CONFIG_DIR" -type f -name '*.json' -print0 2>/dev/null)
    fi

    TPROXY_PORT="${extracted_tproxy_port:-$default_tproxy_port}"
    REDIRECT_PORT="${extracted_redirect_port:-$default_redirect_port}"

    if [[ -n "$TPROXY_PORT" || -n "$REDIRECT_PORT" ]]; then
        log INFO "Обнаруженные порты:"
        [[ -n "$TPROXY_PORT" ]] && log INFO "  └─ TPROXY:   $TPROXY_PORT" || log INFO "  └─ TPROXY:   [не найден]"
        [[ -n "$REDIRECT_PORT" ]] && log INFO "  └─ REDIRECT: $REDIRECT_PORT" || log INFO "  └─ REDIRECT: [не найден]"
    else
        log WARN "Не удалось определить ни один порт из конфигов ($XRAY_CONFIG_DIR); используются сконфигурированные значения"
    fi
}

# === Очистка правил ===
clear_rules() {
    log INFO "Удаление ip rule и маршрутов"
    
    if ip rule del fwmark $MARK_ID table $ROUTE_TABLE_ID 2>/dev/null; then
        log OK "ip rule удалён: fwmark=$MARK_ID → table $ROUTE_TABLE_ID"
    else
        log WARN "ip rule не найден или уже удалён"
    fi
    
    if ip route flush table $ROUTE_TABLE_ID 2>/dev/null; then
        log OK "Таблица маршрутов $ROUTE_TABLE_ID очищена"
    else
        log WARN "Таблица маршрутов $ROUTE_TABLE_ID уже пуста или не существует"
    fi
    
    log INFO "Удаление XRAY цепочек из PREROUTING и OUTPUT"
    iptables -t mangle -D PREROUTING -j XRAY_ENABLED 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j XRAY_DISABLED 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j XRAY_PREROUTING 2>/dev/null || true
    iptables -t nat -D PREROUTING -j $XRAY_CHAIN 2>/dev/null || true
    iptables -t nat -D PREROUTING -j XRAY_NAT_PREROUTING 2>/dev/null || true
    local iface
    for iface in "${INTERCEPT_INTERFACES[@]}"; do
        iptables -t mangle -D PREROUTING -i "$iface" -j XRAY_ENABLED 2>/dev/null || true
        iptables -t mangle -D PREROUTING -i "$iface" -j XRAY_PREROUTING 2>/dev/null || true
        iptables -t mangle -D PREROUTING -i "$iface" -j XRAY_DISABLED 2>/dev/null || true
        iptables -t nat -D PREROUTING -i "$iface" -j $XRAY_CHAIN 2>/dev/null || true
        iptables -t nat -D PREROUTING -i "$iface" -j XRAY_NAT_PREROUTING 2>/dev/null || true
    done
    iptables -t mangle -D OUTPUT -m owner ! --gid-owner $XRAY_GID -j $XRAY_SELF_CHAIN 2>/dev/null && log OK "$XRAY_SELF_CHAIN удалена из OUTPUT" || log WARN "$XRAY_SELF_CHAIN не была подключена"
    
    # NAT и FORWARD правила для шлюза
    local nat_required=false
    for iface in "${INTERCEPT_INTERFACES[@]}"; do
        [[ "$iface" == "$WAN_IF" ]] && continue
        nat_required=true
        iptables -D FORWARD -i "$iface" -o "$WAN_IF" -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -i "$WAN_IF" -o "$iface" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    done
    $nat_required && iptables -t nat -D POSTROUTING -o "$WAN_IF" -j MASQUERADE 2>/dev/null || true
    
    log INFO "Очистка содержимого цепочек XRAY, XRAY_SELF и XRAY_ENABLED"
    iptables -t mangle -F $XRAY_CHAIN 2>/dev/null && log OK "Очищена цепочка $XRAY_CHAIN (mangle)" || log WARN "Цепочка $XRAY_CHAIN (mangle) не существует"
    iptables -t nat -F $XRAY_CHAIN 2>/dev/null && log OK "Очищена цепочка $XRAY_CHAIN (nat)" || log WARN "Цепочка $XRAY_CHAIN (nat) не существует"
    iptables -t mangle -F $XRAY_SELF_CHAIN 2>/dev/null && log OK "Очищена цепочка $XRAY_SELF_CHAIN" || log WARN "Цепочка $XRAY_SELF_CHAIN не существует"
    iptables -t mangle -F XRAY_ENABLED 2>/dev/null && log OK "Очищена цепочка XRAY_ENABLED" || log WARN "Цепочка XRAY_ENABLED не существует"
    iptables -t mangle -F XRAY_PREROUTING 2>/dev/null || true
    iptables -t nat -F XRAY_NAT_PREROUTING 2>/dev/null || true
    
    log INFO "Создание или очистка XRAY_DISABLED для DROP по умолчанию"
    iptables -t mangle -F XRAY_DISABLED 2>/dev/null || iptables -t mangle -N XRAY_DISABLED
    
    log INFO "Применение исключений в XRAY_DISABLED"
    
    # Системные CIDR
    for cidr in $LOCAL_CIDRS 127.0.0.0/8; do
        iptables -t mangle -A XRAY_DISABLED -d "$cidr" -j RETURN
    done
    
    # Исключения IP-адресов
    for ip in "${CUSTOM_BYPASS_IPS[@]}"; do
        iptables -t mangle -A XRAY_DISABLED -d "$ip" -j RETURN
    done
    
    # Исключения по CIDR
    for cidr in "${CUSTOM_BYPASS_CIDRS[@]}"; do
        iptables -t mangle -A XRAY_DISABLED -d "$cidr" -j RETURN
    done
    
    # Исключения по TCP-портам
    for port in "${CUSTOM_BYPASS_PORTS[@]}"; do
        iptables -t mangle -A XRAY_DISABLED -p tcp --dport "$port" -j RETURN
    done
    
    # По умолчанию — DROP
    iptables -t mangle -A XRAY_DISABLED -j DROP
    log OK "Добавлена цепочка XRAY_DISABLED с исключениями и DROP по умолчанию"
}

# === Применение правил ===
apply_rules() {
    log INFO "Очистка предыдущих правил"
    clear_rules

    load_runtime_mode
    disable_interface_redirects
    
    log INFO "Создание цепочки XRAY_DISABLED для kill-switch"
    iptables -t mangle -N XRAY_DISABLED 2>/dev/null || true
    
    log INFO "Установка ip rule и таблицы маршрутов"
    ip rule add fwmark $MARK_ID table $ROUTE_TABLE_ID || {
        log ERROR "Не удалось добавить ip rule"
        exit 1
    }
    
    ip route add local 0.0.0.0/0 dev lo table $ROUTE_TABLE_ID || {
        log ERROR "Не удалось добавить маршрут в таблицу $ROUTE_TABLE_ID"
        exit 1
    }
    
    log INFO "Настройка цепочек XRAY"
    iptables -t mangle -N $XRAY_CHAIN 2>/dev/null || iptables -t mangle -F $XRAY_CHAIN
    iptables -t nat -N $XRAY_CHAIN 2>/dev/null || iptables -t nat -F $XRAY_CHAIN
    iptables -t mangle -N $XRAY_SELF_CHAIN 2>/dev/null || iptables -t mangle -F $XRAY_SELF_CHAIN
    iptables -t mangle -N XRAY_ENABLED 2>/dev/null || iptables -t mangle -F XRAY_ENABLED
    iptables -t mangle -N XRAY_PREROUTING 2>/dev/null || iptables -t mangle -F XRAY_PREROUTING
    iptables -t nat -N XRAY_NAT_PREROUTING 2>/dev/null || iptables -t nat -F XRAY_NAT_PREROUTING
    
    iptables -t mangle -C XRAY_ENABLED -j $XRAY_CHAIN 2>/dev/null || \
    iptables -t mangle -A XRAY_ENABLED -j $XRAY_CHAIN
    log OK "Цепочка XRAY_ENABLED направляет трафик в XRAY"
    
    log INFO "Подключение XRAY к PREROUTING по ingress-интерфейсам и источникам"
    attach_enabled_hooks

    local nat_required=false iface
    for iface in "${INTERCEPT_INTERFACES[@]}"; do
        [[ "$iface" == "$WAN_IF" ]] && continue
        nat_required=true
        iptables -C FORWARD -i "$iface" -o "$WAN_IF" -j ACCEPT 2>/dev/null || iptables -A FORWARD -i "$iface" -o "$WAN_IF" -j ACCEPT
        iptables -C FORWARD -i "$WAN_IF" -o "$iface" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -A FORWARD -i "$WAN_IF" -o "$iface" -m state --state ESTABLISHED,RELATED -j ACCEPT
    done
    $nat_required && {
        iptables -t nat -C POSTROUTING -o "$WAN_IF" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE
        log OK "Настроен NAT на выход через $WAN_IF"
    }
    
    log INFO "Добавление системных исключений"
    for cidr in $LOCAL_CIDRS 127.0.0.0/8; do
        iptables -t mangle -A $XRAY_CHAIN -d "$cidr" -j RETURN
        iptables -t nat -A $XRAY_CHAIN -d "$cidr" -j RETURN
    done
    
    iptables -t mangle -A $XRAY_CHAIN -i lo -j RETURN
    iptables -t nat -A $XRAY_CHAIN -i lo -j RETURN
    
    log INFO "Применение кастомных исключений"
    for cidr in "${CUSTOM_BYPASS_CIDRS[@]}"; do
        iptables -t mangle -A $XRAY_CHAIN -d "$cidr" -j RETURN
        iptables -t nat -A $XRAY_CHAIN -d "$cidr" -j RETURN
    done
    
    for ip in "${CUSTOM_BYPASS_IPS[@]}"; do
        iptables -t mangle -A $XRAY_CHAIN -d "$ip" -j RETURN
        iptables -t nat -A $XRAY_CHAIN -d "$ip" -j RETURN
    done
    
    for port in "${CUSTOM_BYPASS_PORTS[@]}"; do
        iptables -t mangle -A $XRAY_CHAIN -p tcp --dport "$port" -j RETURN
        iptables -t nat -A $XRAY_CHAIN -p tcp --dport "$port" -j RETURN
    done
    
    log INFO "Добавление правил TPROXY (UDP) и REDIRECT (TCP)"
    [[ "$FIREWALL_MODE" == "tcp-udp" && -n "$TPROXY_PORT" ]] && {
        iptables -t mangle -A $XRAY_CHAIN -p udp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark $MARK_ID/0xffffffff
        log OK "Применено TPROXY для UDP на порт $TPROXY_PORT"
    }

    [[ "$FIREWALL_MODE" != "tcp-udp" ]] && log INFO "UDP TPROXY отключён в режиме $FIREWALL_MODE"
    
    [[ -n "$REDIRECT_PORT" ]] && {
        iptables -t nat -A $XRAY_CHAIN -p tcp -j REDIRECT --to-ports $REDIRECT_PORT
        log OK "Применено REDIRECT для TCP на порт $REDIRECT_PORT"
    }
    
    log INFO "Исключение трафика самого Xray (gid=$XRAY_GID)"
    iptables -t mangle -D OUTPUT -m owner ! --gid-owner $XRAY_GID -j $XRAY_SELF_CHAIN 2>/dev/null || true
    iptables -t mangle -A OUTPUT -m owner ! --gid-owner $XRAY_GID -j $XRAY_SELF_CHAIN
    iptables -t mangle -A $XRAY_SELF_CHAIN -j RETURN
    log OK "Трафик Xray исключён из обработки"
}

# === Основная функция ===
main() {
    trap 'log ERROR "Скрипт аварийно завершён на строке $LINENO"; exit 1' ERR
    
    log INFO "Ключ запуска: $1"
    detect_interfaces
    ensure_exclusion_files_exist
    ensure_policy_files_exist
    load_custom_exclusions
    load_policy_scope
    extract_xray_port_protocol
    load_runtime_mode
    
    case "$1" in
        start|apply)
            log INFO "Применение правил маршрутизации и iptables"
            apply_rules
            ;;
        stop|clear)
            log INFO "Очистка всех правил маршрутизации и iptables"
            clear_rules
            ;;
        restart|reload)
            log INFO "Перезапуск iptables правил"
            clear_rules
            apply_rules
            ;;
        enable)
            log INFO "Переключение в активный режим"
            switch_to_enabled_mode
            ;;
        disable)
            log INFO "Переключение в kill-switch режим"
            switch_to_disabled_mode
            ;;
        status)
            log INFO "Проверка статуса"
            log INFO "MODE=$FIREWALL_MODE, GATEWAY_MODE=$GATEWAY_MODE, TPROXY_PORT=${TPROXY_PORT:-не определён}, REDIRECT_PORT=${REDIRECT_PORT:-не определён}, WAN_IF=$WAN_IF, LAN_IF=$LAN_IF, INTERCEPT_IFACES=${INTERCEPT_INTERFACES[*]}"
            ;;
        diagnose)
            log INFO "Диагностика kill-switch"
            diagnose_killswitch
            ;;
        ""|--help|-h)
            echo "Usage: $0 {start|stop|restart|enable|disable|status|diagnose}"
            exit 0
            ;;
        *)
            log ERROR "Неизвестная команда: $1"
            exit 1
            ;;
    esac
    
    exit 0
}

# === Переключение в активный режим ===
switch_to_enabled_mode() {
    log INFO "Переключение в активный режим (Xray работает)"
    
    # Проверка существования цепочек
    if ! iptables -t mangle -L XRAY_ENABLED >/dev/null 2>&1; then
        log ERROR "Цепочка XRAY_ENABLED не существует. Запустите 'start' сначала."
        return 1
    fi
    
    if ! iptables -t mangle -L XRAY_DISABLED >/dev/null 2>&1; then
        log ERROR "Цепочка XRAY_DISABLED не существует. Запустите 'start' сначала."
        return 1
    fi
    
    attach_enabled_hooks
    
    log OK "Переключение в активный режим завершено"
}

# === Переключение в kill-switch режим ===
switch_to_disabled_mode() {
    log INFO "Переключение в kill-switch режим (Xray остановлен)"
    
    # Проверка существования цепочек
    if ! iptables -t mangle -L XRAY_ENABLED >/dev/null 2>&1; then
        log ERROR "Цепочка XRAY_ENABLED не существует. Запустите 'start' сначала."
        return 1
    fi
    
    if ! iptables -t mangle -L XRAY_DISABLED >/dev/null 2>&1; then
        log ERROR "Цепочка XRAY_DISABLED не существует. Запустите 'start' сначала."
        return 1
    fi
    
    attach_disabled_hooks

    log OK "Переключение в kill-switch режим завершено"
}

# === Диагностика kill-switch ===
diagnose_killswitch() {
    log SEP
    log TITLE "Диагностика Kill-Switch"
    
    # Проверка статуса Xray
    if systemctl is-active --quiet xray; then
        log OK "Xray сервис активен"
    else
        log WARN "Xray сервис неактивен"
    fi
    
    # Проверка текущего режима файрвола
    if iptables -t mangle -L PREROUTING -n | grep -q "XRAY_ENABLED"; then
        log OK "Файрвол в активном режиме (XRAY_ENABLED)"
    elif iptables -t mangle -L PREROUTING -n | grep -q "XRAY_DISABLED"; then
        log OK "Файрвол в kill-switch режиме (XRAY_DISABLED)"
    else
        log ERROR "Файрвол не настроен"
    fi
    
    # Проверка цепочек
    for chain in XRAY_ENABLED XRAY_DISABLED XRAY; do
        if iptables -t mangle -L "$chain" >/dev/null 2>&1; then
            log OK "Цепочка $chain существует"
        else
            log WARN "Цепочка $chain не найдена"
        fi
    done
    
    # Тест блокировки
    log INFO "Тестирование блокировки внешнего трафика..."
    if timeout 5 curl -s https://google.com >/dev/null 2>&1; then
        log WARN "Внешний трафик НЕ заблокирован"
    else
        log OK "Внешний трафик заблокирован"
    fi
    
    log SEP
}

# Запуск основной функции
main "$@"

EOF
    
    # Замена переменных в скрипте
    sed -i "s|__MARK_ID__|$MARK_ID|g" "$FIREWALL_SCRIPT_PATH"
    sed -i "s|__ROUTE_TABLE_ID__|$ROUTE_TABLE_ID|g" "$FIREWALL_SCRIPT_PATH"
    sed -i "s|__TPROXY_PORT__|$TPROXY_PORT|g" "$FIREWALL_SCRIPT_PATH"
    sed -i "s|__REDIRECT_PORT__|$REDIRECT_PORT|g" "$FIREWALL_SCRIPT_PATH"
    sed -i "s|__LAN_IF__|$LAN_IF|g" "$FIREWALL_SCRIPT_PATH"
    sed -i "s|__WAN_IF__|$WAN_IF|g" "$FIREWALL_SCRIPT_PATH"
    sed -i "s|__LOCAL_CIDRS__|$LOCAL_CIDRS|g" "$FIREWALL_SCRIPT_PATH"
    sed -i "s|__XRAY_GID__|$XRAY_GID|g" "$FIREWALL_SCRIPT_PATH"
    sed -i "s|__XRAY_CONFIG_DIR__|$XRAY_CONFIG_DIR|g" "$FIREWALL_SCRIPT_PATH"
    sed -i "s|__FIREWALL_MODE__|$FIREWALL_DEFAULT_MODE|g" "$FIREWALL_SCRIPT_PATH"
    sed -i "s|__GATEWAY_MODE__|$FIREWALL_GATEWAY_MODE|g" "$FIREWALL_SCRIPT_PATH"
    sed -i "s|__INTERCEPT_INTERFACES__|$FIREWALL_INTERCEPT_INTERFACES|g" "$FIREWALL_SCRIPT_PATH"
    sed -i "s|__POLICY_SOURCE_CIDRS__|$FIREWALL_SOURCE_CIDRS|g" "$FIREWALL_SCRIPT_PATH"
    sed -i "s|__POLICY_SOURCE_IPS__|$FIREWALL_SOURCE_IPS|g" "$FIREWALL_SCRIPT_PATH"

    # Установка прав на выполнение
    chmod +x "$FIREWALL_SCRIPT_PATH"

    if [[ ! -f "$script_dir/xray-iptables.mode" ]]; then
        printf '%s\n' "$FIREWALL_DEFAULT_MODE" > "$script_dir/xray-iptables.mode"
        chmod 0644 "$script_dir/xray-iptables.mode"
    fi
    
    log OK "Скрипт управления iptables создан: $FIREWALL_SCRIPT_PATH"
}

# === Определение интерфейсов ===
detect_interfaces() {
    log INFO "Определение сетевых интерфейсов"
    
    # Инициализация переменных
    LAN_IF="${LAN_IF:-}"
    WAN_IF="${WAN_IF:-}"
    LOCAL_CIDRS="${LOCAL_CIDRS:-}"
    
    # Определение WAN интерфейса
    WAN_IF=$(ip route | awk '/default/ {print $5}' | head -n1)
    if [[ -z "$WAN_IF" ]]; then
        log ERROR "Не удалось определить интерфейс с default route"
        exit 1
    else
        log OK "WAN_IF: $WAN_IF"
    fi
    
    # Определение LAN интерфейса
    if [[ -n "$LAN_IF" ]]; then
        log INFO "LAN_IF задан вручную: $LAN_IF"
    else
        LAN_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -Ev "^lo$|^$WAN_IF$" | head -n1)
        if [[ -n "$LAN_IF" ]]; then
            log OK "Обнаружен LAN_IF: $LAN_IF"
        else
            LAN_IF="$WAN_IF"
            log WARN "Второй интерфейс не найден, используется WAN_IF ($LAN_IF)"
        fi
    fi
    
    # Получение локальных CIDR
    log INFO "Получение локальных CIDR для интерфейсов $LAN_IF и $WAN_IF"
    local lan_cidrs wan_cidrs
    lan_cidrs=$(ip -o -f inet addr show "$LAN_IF" 2>/dev/null | awk '{print $4}')
    wan_cidrs=$(ip -o -f inet addr show "$WAN_IF" 2>/dev/null | awk '{print $4}')
    LOCAL_CIDRS=$(echo "$lan_cidrs $wan_cidrs" | xargs)
    
    if [[ -z "$LOCAL_CIDRS" ]]; then
        log ERROR "Не удалось получить локальные CIDR"
        exit 1
    else
        log OK "Найдены локальные подсети: $LOCAL_CIDRS"
    fi
}

# === Загрузка исключений ===
load_exclusions() {
    log INFO "Загрузка исключений из конфигурационных файлов"
    
    local base_dir="$XRAY_CONFIG_DIR"
    
    # Создание файлов исключений если их нет
    [[ -f "$base_dir/exclude_cidrs.txt" ]] || cat > "$base_dir/exclude_cidrs.txt" <<'EXCLUDE_EOF'
# CIDR-сети, исключаемые из обработки
# Пример:
# 10.0.0.0/8
# 192.168.0.0/16
EXCLUDE_EOF
    
    [[ -f "$base_dir/exclude_ips.txt" ]] || cat > "$base_dir/exclude_ips.txt" <<'EXCLUDE_EOF'
# IP-адреса, исключаемые из обработки
# Пример:
# 8.8.8.8
# 1.1.1.1
EXCLUDE_EOF
    
    [[ -f "$base_dir/exclude_ports.txt" ]] || cat > "$base_dir/exclude_ports.txt" <<'EXCLUDE_EOF'
# TCP-порты, исключаемые из обработки
# Пример:
# 22     # SSH
# 443    # HTTPS
# 8080   # Локальный UI
EXCLUDE_EOF
    
    # Загрузка исключений из файлов
    [[ -f "$base_dir/exclude_cidrs.txt" ]] && \
        mapfile -t CUSTOM_BYPASS_CIDRS < <(grep -vE '^\s*#|^\s*$' "$base_dir/exclude_cidrs.txt" 2>/dev/null || true)
    
    [[ -f "$base_dir/exclude_ips.txt" ]] && \
        mapfile -t CUSTOM_BYPASS_IPS < <(grep -vE '^\s*#|^\s*$' "$base_dir/exclude_ips.txt" 2>/dev/null || true)
    
    [[ -f "$base_dir/exclude_ports.txt" ]] && \
        mapfile -t CUSTOM_BYPASS_PORTS < <(grep -vE '^\s*#|^\s*$' "$base_dir/exclude_ports.txt" 2>/dev/null || true)
    
    log INFO "Загружено исключений: CIDRs=${#CUSTOM_BYPASS_CIDRS[@]}, IPs=${#CUSTOM_BYPASS_IPS[@]}, Ports=${#CUSTOM_BYPASS_PORTS[@]}"
}

# === Очистка правил ===
clear_rules() {
    log INFO "Очистка правил iptables"
    
    # Удаление ip rule и маршрутов
    ip rule del fwmark $MARK_ID table $ROUTE_TABLE_ID 2>/dev/null || true
    ip route flush table $ROUTE_TABLE_ID 2>/dev/null || true
    
    # Удаление цепочек из PREROUTING и OUTPUT
    iptables -t mangle -D PREROUTING -i "$LAN_IF" -j XRAY_ENABLED 2>/dev/null || true
    iptables -t mangle -D PREROUTING -i "$LAN_IF" -j $XRAY_CHAIN 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "$LAN_IF" -j $XRAY_CHAIN 2>/dev/null || true
    iptables -t mangle -D OUTPUT -m owner ! --gid-owner $XRAY_GID -j $XRAY_SELF_CHAIN 2>/dev/null || true
    
    # NAT и FORWARD правила для шлюза
    if [[ "$WAN_IF" != "$LAN_IF" ]]; then
        iptables -t nat -D POSTROUTING -o "$WAN_IF" -j MASQUERADE 2>/dev/null || true
        iptables -D FORWARD -i "$LAN_IF" -o "$WAN_IF" -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -i "$WAN_IF" -o "$LAN_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    fi
    
    # Очистка содержимого цепочек
    iptables -t mangle -F $XRAY_CHAIN 2>/dev/null || true
    iptables -t nat -F $XRAY_CHAIN 2>/dev/null || true
    iptables -t mangle -F $XRAY_SELF_CHAIN 2>/dev/null || true
    iptables -t mangle -F XRAY_ENABLED 2>/dev/null || true
    iptables -t mangle -F XRAY_DISABLED 2>/dev/null || true
    
    # Удаление цепочек
    iptables -t mangle -X $XRAY_CHAIN 2>/dev/null || true
    iptables -t nat -X $XRAY_CHAIN 2>/dev/null || true
    iptables -t mangle -X $XRAY_SELF_CHAIN 2>/dev/null || true
    iptables -t mangle -X XRAY_ENABLED 2>/dev/null || true
    iptables -t mangle -X XRAY_DISABLED 2>/dev/null || true
    
    log OK "Правила очищены"
}

# === Применение правил ===
apply_rules() {
    log INFO "Применение правил iptables"
    
    # Очистка предыдущих правил
    clear_rules
    
    # Установка ip rule и таблицы маршрутов
    ip rule add fwmark $MARK_ID table $ROUTE_TABLE_ID || {
        log ERROR "Не удалось добавить ip rule"
        exit 1
    }
    
    ip route add local 0.0.0.0/0 dev lo table $ROUTE_TABLE_ID || {
        log ERROR "Не удалось добавить маршрут в таблицу $ROUTE_TABLE_ID"
        exit 1
    }
    
    # Создание цепочек
    iptables -t mangle -N $XRAY_CHAIN 2>/dev/null || true
    iptables -t nat -N $XRAY_CHAIN 2>/dev/null || true
    iptables -t mangle -N $XRAY_SELF_CHAIN 2>/dev/null || true
    iptables -t mangle -N XRAY_ENABLED 2>/dev/null || true
    iptables -t mangle -N XRAY_DISABLED 2>/dev/null || true
    
    # Подключение к PREROUTING
    iptables -t mangle -A PREROUTING -i "$LAN_IF" -j XRAY_ENABLED
    iptables -t mangle -A XRAY_ENABLED -j $XRAY_CHAIN
    iptables -t nat -A PREROUTING -i "$LAN_IF" -j $XRAY_CHAIN
    
    # NAT и FORWARD правила для шлюза
    if [[ "$WAN_IF" != "$LAN_IF" ]]; then
        iptables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE
        iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -j ACCEPT
        iptables -A FORWARD -i "$WAN_IF" -o "$LAN_IF" -m state --state ESTABLISHED,RELATED -j ACCEPT
        log OK "Настроен NAT $LAN_IF ↔ $WAN_IF"
    fi
    
    # Системные исключения
    for cidr in $LOCAL_CIDRS 127.0.0.0/8; do
        iptables -t mangle -A $XRAY_CHAIN -d "$cidr" -j RETURN
        iptables -t nat -A $XRAY_CHAIN -d "$cidr" -j RETURN
    done
    
    iptables -t mangle -A $XRAY_CHAIN -i lo -j RETURN
    iptables -t nat -A $XRAY_CHAIN -i lo -j RETURN
    
    # Кастомные исключения
    for cidr in "${CUSTOM_BYPASS_CIDRS[@]}"; do
        iptables -t mangle -A $XRAY_CHAIN -d "$cidr" -j RETURN
        iptables -t nat -A $XRAY_CHAIN -d "$cidr" -j RETURN
    done
    
    for ip in "${CUSTOM_BYPASS_IPS[@]}"; do
        iptables -t mangle -A $XRAY_CHAIN -d "$ip" -j RETURN
        iptables -t nat -A $XRAY_CHAIN -d "$ip" -j RETURN
    done
    
    for port in "${CUSTOM_BYPASS_PORTS[@]}"; do
        iptables -t mangle -A $XRAY_CHAIN -p tcp --dport "$port" -j RETURN
        iptables -t nat -A $XRAY_CHAIN -p tcp --dport "$port" -j RETURN
    done
    
    # TPROXY и REDIRECT правила
    if [[ -n "$TPROXY_PORT" ]]; then
        iptables -t mangle -A $XRAY_CHAIN -p udp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark $MARK_ID/0xffffffff
        log OK "Применено TPROXY для UDP на порт $TPROXY_PORT"
    fi
    
    if [[ -n "$REDIRECT_PORT" ]]; then
        iptables -t nat -A $XRAY_CHAIN -p tcp -j REDIRECT --to-ports $REDIRECT_PORT
        log OK "Применено REDIRECT для TCP на порт $REDIRECT_PORT"
    fi
    
    # Исключение трафика Xray
    iptables -t mangle -A OUTPUT -m owner ! --gid-owner $XRAY_GID -j $XRAY_SELF_CHAIN
    iptables -t mangle -A $XRAY_SELF_CHAIN -j RETURN
    
    # Kill-switch: блокировка внешнего трафика при остановке Xray
    for cidr in $LOCAL_CIDRS 127.0.0.0/8; do
        iptables -t mangle -A XRAY_DISABLED -d "$cidr" -j RETURN
    done
    
    for ip in "${CUSTOM_BYPASS_IPS[@]}"; do
        iptables -t mangle -A XRAY_DISABLED -d "$ip" -j RETURN
    done
    
    for cidr in "${CUSTOM_BYPASS_CIDRS[@]}"; do
        iptables -t mangle -A XRAY_DISABLED -d "$cidr" -j RETURN
    done
    
    for port in "${CUSTOM_BYPASS_PORTS[@]}"; do
        iptables -t mangle -A XRAY_DISABLED -p tcp --dport "$port" -j RETURN
    done
    
    iptables -t mangle -A XRAY_DISABLED -j DROP
    
    log OK "Правила применены"
}

# === Создание systemd юнитов ===
firewall_create_systemd_units() {
    log INFO "Создание systemd юнитов для файрвола"
    
    # Основной юнит файрвола
    cat > "/etc/systemd/system/$FIREWALL_UNIT_NAME" <<EOF
[Unit]
Description=Xray Gateway Firewall
After=network.target
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$FIREWALL_SCRIPT_PATH start
ExecStop=$FIREWALL_SCRIPT_PATH stop
ExecReload=$FIREWALL_SCRIPT_PATH restart

[Install]
WantedBy=multi-user.target
EOF

    # Юнит для перезапуска при изменении конфигурации
    cat > "/etc/systemd/system/$FIREWALL_RESTART_UNIT_NAME" <<EOF
[Unit]
Description=Xray Gateway Firewall Restart
After=xray.service
Wants=xray.service

[Service]
Type=oneshot
ExecStart=$FIREWALL_SCRIPT_PATH restart

[Install]
WantedBy=multi-user.target
EOF

    # Перезагрузка systemd
    systemctl daemon-reload
    
    # Включение автозапуска
    systemctl enable "$FIREWALL_UNIT_NAME"
    
    log OK "Systemd юниты созданы и включены"
}

# === Создание дополнительных systemd юнитов для kill-switch ===
firewall_create_killswitch_units() {
    log INFO "Создание systemd юнитов для kill-switch"
    
    # Юнит мониторинга
    cp "$FIREWALL_SCRIPT_DIR/plugins/firewall/systemd/xray-killswitch-monitor.service" "/etc/systemd/system/"
    
    # Юнит watchdog
    cp "$FIREWALL_SCRIPT_DIR/plugins/firewall/systemd/xray-killswitch-watchdog.service" "/etc/systemd/system/"
    
    # Перезагрузка systemd
    systemctl daemon-reload
    
    log OK "Systemd юниты для kill-switch созданы"
}

# === Копирование скриптов переключения ===
firewall_copy_switch_scripts() {
    log INFO "Копирование скриптов переключения"
    
    local xray_install_path
    xray_install_path="$(config_get_constant "xray_install_path" "/opt/xray")"
    local iptables_dir="${xray_install_path}/iptables"
    
    # Создание директории если не существует
    mkdir -p "$iptables_dir"
    
    # Копирование скриптов
    cp "$FIREWALL_SCRIPT_DIR/plugins/firewall/scripts/switch-to-enabled.sh" "$iptables_dir/"
    cp "$FIREWALL_SCRIPT_DIR/plugins/firewall/scripts/switch-to-disabled.sh" "$iptables_dir/"
    cp "$FIREWALL_SCRIPT_DIR/plugins/firewall/scripts/killswitch-watchdog.sh" "$iptables_dir/"
    
    # Установка прав выполнения
    chmod +x "$iptables_dir/switch-to-enabled.sh"
    chmod +x "$iptables_dir/switch-to-disabled.sh"
    chmod +x "$iptables_dir/killswitch-watchdog.sh"
    
    log OK "Скрипты переключения скопированы в $iptables_dir"
}

# === Экспорт функций ===
export -f plugin_firewall_init plugin_firewall_execute plugin_firewall_dependencies plugin_firewall_info
export -f firewall_install firewall_uninstall firewall_status firewall_start firewall_stop firewall_restart
export -f firewall_force_legacy firewall_create_script firewall_create_systemd_units
export -f firewall_enable firewall_disable firewall_diagnose
export -f firewall_create_killswitch_units firewall_copy_switch_scripts
export -f detect_interfaces

# При загрузке как плагин НЕ вызываем plugin_firewall_init автоматически
# Инициализация будет вызвана вручную из installer.sh
