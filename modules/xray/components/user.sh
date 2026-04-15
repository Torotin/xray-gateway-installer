#!/usr/bin/env bash

# === Компонент управления пользователем Xray ===
# Версия: 2.0.0
# Автор: Xray Gateway Installer Team

# === Инициализация компонента ===
user_init() {
    log INFO "Инициализация компонента управления пользователем Xray"
    log OK "Компонент управления пользователем Xray инициализирован"
    return 0
}

# === Создание пользователя и групп ===
user_create() {
    log INFO "Создание пользователя и групп Xray"
    
    # Получение переменных конфигурации
    local xray_user xray_group xray_gid
    xray_user="$(config_get_constant "xray_user" "xray")"
    xray_group="$(config_get_constant "xray_group" "xray")"
    xray_gid="$(config_get_constant "xray_gid" "1001")"
    
    # Создание группы
    if ! getent group "$xray_group" >/dev/null 2>&1; then
        if groupadd -g "$xray_gid" "$xray_group"; then
            log OK "Создана группа: $xray_group (GID: $xray_gid)"
        else
            # Если группа с таким GID уже существует, попробуем создать без указания GID
            if groupadd "$xray_group"; then
                log OK "Создана группа: $xray_group (автоматический GID)"
            else
                log ERROR "Не удалось создать группу $xray_group"
                return 1
            fi
        fi
    else
        log OK "Группа $xray_group уже существует"
    fi
    
    # Создание пользователя
    if ! getent passwd "$xray_user" >/dev/null 2>&1; then
        if useradd -r -M -s /usr/sbin/nologin -u "$xray_gid" -g "$xray_group" "$xray_user"; then
            log OK "Создан пользователь: $xray_user (UID: $xray_gid)"
        else
            # Если UID уже существует, попробуем создать без указания UID
            if useradd -r -M -s /usr/sbin/nologin -g "$xray_group" "$xray_user"; then
                log OK "Создан пользователь: $xray_user (автоматический UID)"
            else
                log ERROR "Не удалось создать пользователя $xray_user"
                return 1
            fi
        fi
    else
        log OK "Пользователь $xray_user уже существует"
    fi
    
    # Добавление в дополнительные группы
    local extra_groups
    extra_groups="$(config_get_constant "xray_extra_groups" "")"
    if [[ -n "$extra_groups" ]]; then
        IFS=',' read -ra groups_array <<< "$extra_groups"
        if usermod -aG "$(IFS=,; echo "${groups_array[*]}")" "$xray_user"; then
            log OK "$xray_user добавлен в дополнительные группы: ${groups_array[*]}"
        else
            log WARN "Не удалось добавить $xray_user в дополнительные группы"
        fi
    fi
    
    # Проверка создания пользователя
    if ! id "$xray_user" &>/dev/null; then
        log ERROR "Пользователь $xray_user не определён после создания"
        return 1
    fi
}

# === Создание директорий ===
user_create_directories() {
    log INFO "Создание директорий Xray"
    
    # Получение переменных конфигурации
    local xray_user xray_group xray_install_path
    xray_user="$(config_get_constant "xray_user" "xray")"
    xray_group="$(config_get_constant "xray_group" "xray")"
    xray_install_path="$(config_get_constant "xray_install_path" "/opt/xray")"
    
    # Создание основных директорий
    local directories=(
        "$xray_install_path"
        "$xray_install_path/configs"
        "$xray_install_path/dat"
        "$xray_install_path/logs"
        "$xray_install_path/iptables"
    )
    
    for dir in "${directories[@]}"; do
        if create_directory "$dir" "$xray_user" "$xray_group" "755"; then
            log OK "Создана директория: $dir"
        else
            log ERROR "Не удалось создать директорию: $dir"
            return 1
        fi
    done
    
    # Символическая ссылка будет создана в core.sh после установки Xray
}

# === Удаление пользователя ===
user_remove() {
    log INFO "Удаление пользователя и групп Xray"
    
    # Получение переменных конфигурации
    local xray_user xray_group
    xray_user="$(config_get_constant "xray_user" "xray")"
    xray_group="$(config_get_constant "xray_group" "xray")"
    
    # Удаление пользователя
    if getent passwd "$xray_user" >/dev/null 2>&1; then
        # Принудительное удаление пользователя
        if userdel -f "$xray_user" 2>/dev/null; then
            log OK "Пользователь $xray_user удален"
        else
            log WARN "Не удалось удалить пользователя $xray_user (возможно, используется другими процессами)"
        fi
    else
        log INFO "Пользователь $xray_user не найден"
    fi
    
    # Удаление группы
    if getent group "$xray_group" >/dev/null 2>&1; then
        # Принудительное удаление группы
        if groupdel -f "$xray_group" 2>/dev/null; then
            log OK "Группа $xray_group удалена"
        else
            log WARN "Не удалось удалить группу $xray_group (возможно, используется другими пользователями)"
        fi
    else
        log INFO "Группа $xray_group не найдена"
    fi
}

# === Настройка прав доступа ===
user_fix_permissions() {
    log INFO "Настройка доступа к директориям Xray"
    
    # Получение переменных конфигурации
    local xray_user xray_group xray_install_path
    xray_user="$(config_get_constant "xray_user" "xray")"
    xray_group="$(config_get_constant "xray_group" "xray")"
    xray_install_path="$(config_get_constant "xray_install_path" "/opt/xray")"
    
    # Убедиться, что /opt доступен
    chmod 755 /opt 2>/dev/null || true
    
    # Установить владельца и группу
    if chown -R "$xray_user:$xray_group" "$xray_install_path"; then
        log OK "Владелец установлен: $xray_user:$xray_group"
    else
        log ERROR "Не удалось установить владельца для $xray_install_path"
        return 1
    fi
    
    # Установить права доступа с setgid
    if find "$xray_install_path" -type d -exec chmod 2775 {} \; 2>/dev/null; then
        log OK "Права на директории установлены (setgid + rwxrwxr-x)"
    else
        log WARN "Не удалось установить setgid для директорий"
    fi
    
    if find "$xray_install_path" -type f -exec chmod 664 {} \; 2>/dev/null; then
        log OK "Права на файлы установлены (rw-rw-r--)"
    else
        log WARN "Не удалось установить права для файлов"
    fi
    
    log OK "Права и владельцы установлены для $xray_install_path с общей группой $xray_group"
    log INFO "Убедись, что нужные пользователи добавлены в $xray_group"
}

# === Статус пользователя ===
user_status() {
    # Получение переменных конфигурации
    local xray_user xray_group
    xray_user="$(config_get_constant "xray_user" "xray")"
    xray_group="$(config_get_constant "xray_group" "xray")"
    
    if getent passwd "$xray_user" >/dev/null 2>&1; then
        echo "Пользователь: $xray_user (найден)"
        echo "  UID: $(id -u "$xray_user")"
        echo "  GID: $(id -g "$xray_user")"
        echo "  Группы: $(id -Gn "$xray_user")"
    else
        echo "Пользователь: $xray_user (не найден)"
    fi
    
    if getent group "$xray_group" >/dev/null 2>&1; then
        echo "Группа: $xray_group (найдена)"
        echo "  GID: $(getent group "$xray_group" | cut -d: -f3)"
    else
        echo "Группа: $xray_group (не найдена)"
    fi
}

# === Экспорт функций ===
export -f user_init user_create user_create_directories user_remove user_status user_fix_permissions

# Автоматическая инициализация при загрузке компонента
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Если скрипт запущен напрямую
    user_init "$@"
else
    # Если скрипт загружен как компонент
    user_init
fi
