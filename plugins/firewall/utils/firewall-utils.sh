#!/usr/bin/env bash

# === Утилиты для плагина Firewall ===
# Версия: 2.0.0
# Автор: Xray Gateway Installer Team
# Описание: Вспомогательные функции для работы с файрволом

# === Проверка зависимостей ===
check_firewall_dependencies() {
    local missing_deps=()
    
    # Проверка iptables
    if ! command -v iptables >/dev/null 2>&1; then
        missing_deps+=("iptables")
    fi
    
    # Проверка ip
    if ! command -v ip >/dev/null 2>&1; then
        missing_deps+=("iproute2")
    fi
    
    # Проверка systemctl
    if ! command -v systemctl >/dev/null 2>&1; then
        missing_deps+=("systemd")
    fi
    
    # Проверка jq
    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "ERROR: Отсутствуют зависимости: ${missing_deps[*]}"
        return 1
    fi
    
    echo "OK: Все зависимости найдены"
    return 0
}

# === Проверка прав root ===
check_root_permissions() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: Требуются права root для работы с файрволом"
        return 1
    fi
    return 0
}

# === Проверка статуса iptables ===
check_iptables_status() {
    if iptables -L >/dev/null 2>&1; then
        echo "OK: iptables работает"
        return 0
    else
        echo "ERROR: iptables недоступен"
        return 1
    fi
}

# === Получение статистики правил ===
get_firewall_stats() {
    echo "=== Статистика файрвола ==="
    
    # Подсчет правил в основных цепочках
    local prerouting_rules=$(iptables -t mangle -L PREROUTING -n | wc -l)
    local output_rules=$(iptables -t mangle -L OUTPUT -n | wc -l)
    local nat_rules=$(iptables -t nat -L PREROUTING -n | wc -l)
    
    echo "PREROUTING (mangle): $((prerouting_rules - 2)) правил"
    echo "OUTPUT (mangle): $((output_rules - 2)) правил"
    echo "PREROUTING (nat): $((nat_rules - 2)) правил"
    
    # Проверка цепочек Xray
    for chain in XRAY XRAY_ENABLED XRAY_DISABLED XRAY_SELF; do
        if iptables -t mangle -L "$chain" >/dev/null 2>&1; then
            local chain_rules=$(iptables -t mangle -L "$chain" -n | wc -l)
            echo "$chain: $((chain_rules - 2)) правил"
        fi
    done
}

# === Очистка временных файлов ===
cleanup_temp_files() {
    local temp_dir="/tmp/xray-firewall"
    
    if [[ -d "$temp_dir" ]]; then
        rm -rf "$temp_dir"
        echo "OK: Временные файлы очищены"
    fi
}

# === Создание резервной копии правил ===
backup_iptables_rules() {
    local backup_dir="/opt/xray/backups"
    local backup_file="$backup_dir/iptables-backup-$(date +%Y%m%d-%H%M%S).txt"
    
    mkdir -p "$backup_dir"
    
    # Сохранение всех правил
    {
        echo "# === Резервная копия правил iptables ==="
        echo "# Дата: $(date)"
        echo ""
        echo "# Mangle table:"
        iptables -t mangle -S
        echo ""
        echo "# NAT table:"
        iptables -t nat -S
        echo ""
        echo "# Filter table:"
        iptables -t filter -S
    } > "$backup_file"
    
    echo "OK: Резервная копия создана: $backup_file"
}

# === Восстановление правил из резервной копии ===
restore_iptables_rules() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        echo "ERROR: Файл резервной копии не найден: $backup_file"
        return 1
    fi
    
    # Очистка текущих правил
    iptables -t mangle -F
    iptables -t nat -F
    iptables -t filter -F
    
    # Восстановление из файла
    while IFS= read -r line; do
        if [[ "$line" =~ ^iptables ]]; then
            eval "$line"
        fi
    done < "$backup_file"
    
    echo "OK: Правила восстановлены из: $backup_file"
}

# === Тестирование блокировки ===
test_firewall_blocking() {
    local test_url="${1:-https://google.com}"
    local timeout="${2:-5}"
    
    echo "Тестирование блокировки: $test_url"
    
    if timeout "$timeout" curl -s "$test_url" >/dev/null 2>&1; then
        echo "WARN: Внешний трафик НЕ заблокирован"
        return 1
    else
        echo "OK: Внешний трафик заблокирован"
        return 0
    fi
}

# === Экспорт функций ===
export -f check_firewall_dependencies check_root_permissions check_iptables_status
export -f get_firewall_stats cleanup_temp_files backup_iptables_rules
export -f restore_iptables_rules test_firewall_blocking
