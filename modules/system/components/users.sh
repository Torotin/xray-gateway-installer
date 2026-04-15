#!/usr/bin/env bash

# === Компонент управления пользователями ===
# Версия: 2.2.0 (Рефакторинг)
# Автор: Xray Gateway Installer Team

# === Глобальные переменные компонента ===
declare -g ADMIN_USER=""
declare -g ADMIN_SSH_KEY=""
declare -g ADMIN_PASSWORD=""
declare -g update_user=false
declare -g ROOT_ACCESS_DISABLED=false

# === Инициализация компонента ===
users_init() {
    log INFO "Инициализация компонента управления пользователями"
    
    # Проверка доступности утилит
    if ! command -v useradd >/dev/null 2>&1; then
        log ERROR "useradd не найден, управление пользователями недоступно"
        return 1
    fi
    
    if ! command -v passwd >/dev/null 2>&1; then
        log ERROR "passwd не найден, управление паролями недоступно"
        return 1
    fi
    
    # Проверка прав доступа
    if [[ "$EUID" -ne 0 ]]; then
        log ERROR "Недостаточно прав для управления пользователями"
        return 1
    fi
    
    log OK "Компонент управления пользователями инициализирован"
    return 0
}

# === Создание административного пользователя ===
users_create_admin() {
    log INFO "Настройка безопасной учётной записи администратора"
    
    # Проверка переменной SKIP_ADMIN_USER_SETUP
    ask_and_execute "system" "skip_admin_user_setup" "Пропустить создание административного пользователя?" "false" "users_skip_admin_setup" "y/N"
}

# === Пропуск создания администратора ===
users_skip_admin_setup() {
    log INFO "Пропуск создания/настройки пользователя (skip_admin_user_setup=true)"
    return 0
}

# === Создание административного пользователя (основная логика) ===
users_create_admin_impl() {
    # Интерактивное предложение создания администратора
    echo
    read -rp "Создать/настроить администратора (рекомендуется)? [Y/n]: " confirm
    confirm="${confirm,,}" # to lowercase
    
    if [[ "$confirm" == "n" || "$confirm" == "no" ]]; then
        log WARN "Создание пользователя администратора пропущено по выбору пользователя"
        return 0
    fi
    
    # Получение имени пользователя
    if [[ -z "$ADMIN_USER" ]]; then
        read -rp "Введите имя нового администратора [adminuser]: " input_user
        ADMIN_USER="${input_user:-adminuser}"
    fi
    
    # Валидация имени пользователя
    if ! users_validate_username "$ADMIN_USER"; then
        log ERROR "Некорректное имя пользователя: $ADMIN_USER"
        return 1
    fi
    
    # Создание или обновление пользователя
    if ! users_create_or_update_admin_user; then
        log ERROR "Ошибка создания/обновления пользователя"
        return 1
    fi
    
    # Настройка пароля
    if ! users_set_admin_password; then
        log WARN "Ошибка настройки пароля"
    fi
    
    # Настройка SSH-ключа
    if ! users_set_admin_ssh_key; then
        log WARN "Ошибка настройки SSH-ключа"
    fi
    
    # Настройка sudo-прав
    if ! users_set_admin_sudo_rights; then
        log ERROR "Ошибка настройки sudo-прав"
        return 1
    fi
    
    log OK "Пользователь $ADMIN_USER настроен"
    return 0
}

# === Валидация имени пользователя ===
users_validate_username() {
    local username="$1"
    
    # Проверка длины
    if [[ ${#username} -lt 3 || ${#username} -gt 32 ]]; then
        log ERROR "Имя пользователя должно быть от 3 до 32 символов"
        return 1
    fi
    
    # Проверка символов
    if [[ ! "$username" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        log ERROR "Имя пользователя может содержать только строчные буквы, цифры, дефисы и подчеркивания"
        return 1
    fi
    
    # Проверка зарезервированных имен
    local reserved_names=("root" "daemon" "bin" "sys" "sync" "games" "man" "mail" "news" "uucp" "proxy" "www-data" "backup" "list" "irc" "gnats" "nobody" "systemd-timesync" "systemd-network" "systemd-resolve" "systemd-bus-proxy" "messagebus" "syslog" "_apt" "uuidd" "tcpdump" "tss" "landscape" "pollinate" "sshd" "systemd-coredump" "systemd-oom" "systemd-journal" "systemd-network" "systemd-resolve" "systemd-timesync" "systemd-bus-proxy" "messagebus" "syslog" "_apt" "uuidd" "tcpdump" "tss" "landscape" "pollinate" "sshd" "systemd-coredump" "systemd-oom" "systemd-journal")
    
    for reserved in "${reserved_names[@]}"; do
        if [[ "$username" == "$reserved" ]]; then
            log ERROR "Имя пользователя '$username' зарезервировано системой"
            return 1
        fi
    done
    
    return 0
}

# === Создание или обновление административного пользователя ===
users_create_or_update_admin_user() {
    log INFO "Создание или обновление административного пользователя: $ADMIN_USER"
    
    # Получение дополнительных групп из конфигурации
    local extra_groups
    extra_groups="$(config_get_module "system" "admin_extra_groups" "sudo,adm,nogroup")"
    
    # Создание групп если они не существуют
    if ! users_ensure_groups_exist "$extra_groups"; then
        log ERROR "Ошибка создания групп"
        return 1
    fi
    
    # Проверка существования пользователя
    if id "$ADMIN_USER" &>/dev/null; then
        log OK "Пользователь $ADMIN_USER уже существует"
        
        # Предложение обновления
        echo
        read -rp "Обновить пароль и SSH-ключ пользователя $ADMIN_USER? [y/N]: " answer
        case "$answer" in
            [Yy]*) 
                update_user=true
                log INFO "Пользователь $ADMIN_USER будет обновлен"
                ;;
            [Nn]*|"") 
                log INFO "Пропуск настройки $ADMIN_USER"
                return 0
                ;;
            *) 
                echo "Пожалуйста, ответьте y или n."
                return 1
                ;;
        esac
        
        # Добавление групп
        if ! usermod -aG "$extra_groups" "$ADMIN_USER"; then
            log WARN "Ошибка добавления групп для пользователя $ADMIN_USER"
        fi
    else
        # Создание нового пользователя
        if ! useradd -m -s /bin/bash -G "$extra_groups" "$ADMIN_USER"; then
            log ERROR "Ошибка создания пользователя $ADMIN_USER"
            return 1
        fi
        
        log OK "Пользователь $ADMIN_USER создан"
    fi
    
    return 0
}

# === Создание групп ===
users_ensure_groups_exist() {
    local groups="$1"
    local IFS=','
    
    for group in $groups; do
        group="$(echo "$group" | xargs)" # убираем пробелы
        
        if ! getent group "$group" >/dev/null 2>&1; then
            if groupadd "$group" 2>/dev/null; then
                log OK "Группа $group создана"
            else
                log WARN "Не удалось создать группу $group"
            fi
        else
            log DEBUG "Группа $group уже существует"
        fi
    done
    
    return 0
}

# === Настройка пароля администратора ===
users_set_admin_password() {
    log INFO "Настройка пароля для пользователя $ADMIN_USER"
    
    if [[ "$update_user" == "true" ]]; then
        echo "Введите новый пароль для пользователя $ADMIN_USER:"
    else
        echo "Введите пароль для пользователя $ADMIN_USER:"
    fi
    
    # Получение пароля
    read -rsp "Пароль: " password
    echo
    read -rsp "Подтвердите пароль: " password_confirm
    echo
    
    if [[ "$password" != "$password_confirm" ]]; then
        log ERROR "Пароли не совпадают"
        return 1
    fi
    
    if [[ ${#password} -lt 8 ]]; then
        log ERROR "Пароль должен содержать минимум 8 символов"
        return 1
    fi
    
    # Установка пароля
    if echo "$ADMIN_USER:$password" | chpasswd; then
        log OK "Пароль для пользователя $ADMIN_USER установлен"
        ADMIN_PASSWORD="$password"
        return 0
    else
        log ERROR "Ошибка установки пароля для пользователя $ADMIN_USER"
        return 1
    fi
}

# === Настройка SSH-ключа администратора ===
users_set_admin_ssh_key() {
    log INFO "Настройка SSH-ключа для пользователя $ADMIN_USER"
    
    echo "Введите SSH-ключ для пользователя $ADMIN_USER (или нажмите Enter для пропуска):"
    read -r ssh_key
    
    if [[ -z "$ssh_key" ]]; then
        log INFO "SSH-ключ не указан, пропуск настройки"
        return 0
    fi
    
    # Валидация SSH-ключа
    if ! users_validate_ssh_key "$ssh_key"; then
        log ERROR "Некорректный SSH-ключ"
        return 1
    fi
    
    # Создание директории .ssh
    local ssh_dir="/home/$ADMIN_USER/.ssh"
    if ! mkdir -p "$ssh_dir"; then
        log ERROR "Ошибка создания директории $ssh_dir"
        return 1
    fi
    
    # Установка прав доступа
    chmod 700 "$ssh_dir"
    chown "$ADMIN_USER:$ADMIN_USER" "$ssh_dir"
    
    # Запись SSH-ключа
    if echo "$ssh_key" > "$ssh_dir/authorized_keys"; then
        chmod 600 "$ssh_dir/authorized_keys"
        chown "$ADMIN_USER:$ADMIN_USER" "$ssh_dir/authorized_keys"
        log OK "SSH-ключ для пользователя $ADMIN_USER настроен"
        ADMIN_SSH_KEY="$ssh_key"
        return 0
    else
        log ERROR "Ошибка записи SSH-ключа"
        return 1
    fi
}

# === Валидация SSH-ключа ===
users_validate_ssh_key() {
    local ssh_key="$1"
    
    # Проверка формата SSH-ключа
    if [[ ! "$ssh_key" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)\s+[A-Za-z0-9+/]+=*\s*.*$ ]]; then
        log ERROR "Некорректный формат SSH-ключа"
        return 1
    fi
    
    return 0
}

# === Настройка sudo-прав администратора ===
users_set_admin_sudo_rights() {
    log INFO "Настройка sudo-прав для пользователя $ADMIN_USER"
    
    local sudoers_file="/etc/sudoers.d/$ADMIN_USER"
    
    # Создание sudoers файла
    cat > "$sudoers_file" << EOF
# Sudo права для пользователя $ADMIN_USER
# Создано: $(date)

$ADMIN_USER ALL=(ALL:ALL) NOPASSWD:ALL
EOF
    
    # Установка прав доступа
    chmod 440 "$sudoers_file"
    
    # Валидация sudoers файла
    if visudo -c -f "$sudoers_file" >/dev/null 2>&1; then
        log OK "Sudo-права настроены для $ADMIN_USER"
        return 0
    else
        log ERROR "Ошибка в конфигурации sudoers для $ADMIN_USER"
        rm -f "$sudoers_file"
        return 1
    fi
}

# === Отключение root-доступа ===
users_disable_root_login() {
    log INFO "Отключение root-доступа и shell"
    
    # Интерактивное подтверждение отключения root
    echo
    read -rp "Отключить root-доступ (рекомендуется для безопасности)? [Y/n]: " confirm
    confirm="${confirm,,}" # to lowercase
    
    if [[ "$confirm" == "n" || "$confirm" == "no" ]]; then
        log WARN "Отключение root-доступа пропущено по выбору пользователя"
        return 0
    fi
    
    # Блокировка пароля root
    if passwd -l root; then
        log OK "Пароль root заблокирован"
    else
        log WARN "Ошибка блокировки пароля root"
    fi
    
    # Отключение shell для root
    if usermod -s /usr/sbin/nologin root; then
        log OK "Shell для root отключен"
    else
        log WARN "Ошибка отключения shell для root"
    fi
    
    # Настройка SSH для отключения root-доступа
    if users_disable_root_ssh_access; then
        log OK "Root-доступ в SSH отключен"
    else
        log WARN "Ошибка отключения root-доступа в SSH"
    fi
    
    ROOT_ACCESS_DISABLED=true
    log OK "Root-доступ отключён, root заблокирован"
    return 0
}

# === Отключение root-доступа в SSH ===
users_disable_root_ssh_access() {
    local sshd_config="/etc/ssh/sshd_config"
    
    if [[ ! -f "$sshd_config" ]]; then
        log WARN "Файл SSH конфигурации не найден: $sshd_config"
        return 1
    fi
    
    # Создание резервной копии
    if ! cp -a "$sshd_config" "$sshd_config.backup.$(date +%Y%m%d_%H%M%S)"; then
        log WARN "Ошибка создания резервной копии SSH конфигурации"
    fi
    
    # Отключение root-доступа в SSH
    if grep -q '^#\?PermitRootLogin' "$sshd_config"; then
        if sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$sshd_config"; then
            log OK "Настройка PermitRootLogin обновлена"
        else
            log WARN "Ошибка обновления настройки PermitRootLogin"
            return 1
        fi
    else
        if echo "PermitRootLogin no" >> "$sshd_config"; then
            log OK "Настройка PermitRootLogin добавлена"
        else
            log WARN "Ошибка добавления настройки PermitRootLogin"
            return 1
        fi
    fi
    
    # Перезапуск SSH
    if systemctl restart ssh >/dev/null 2>&1; then
        log OK "SSH сервис перезапущен"
        return 0
    else
        log WARN "Ошибка перезапуска SSH сервиса"
        return 1
    fi
}

# === Восстановление пользователей ===
users_restore() {
    log INFO "Восстановление пользователей и прав доступа"
    
    local restored_count=0
    local errors=0
    
    # Восстановление root-доступа
    if users_restore_root_access; then
        log OK "Root-доступ восстановлен"
        ((restored_count++))
    else
        log WARN "Ошибка восстановления root-доступа"
        ((errors++))
    fi
    
    # Удаление sudoers файла администратора
    if [[ -n "$ADMIN_USER" ]]; then
        local sudoers_file="/etc/sudoers.d/$ADMIN_USER"
        if [[ -f "$sudoers_file" ]]; then
            if rm -f "$sudoers_file"; then
                log OK "Удален sudoers файл: $sudoers_file"
                ((restored_count++))
            else
                log WARN "Ошибка удаления sudoers файла"
                ((errors++))
            fi
        fi
        
        # Предложение удаления административного пользователя
        if [[ -n "${NONINTERACTIVE:-}" ]]; then
            log INFO "Неинтерактивный режим: пропускаем удаление административного пользователя"
            log INFO "Пользователь $ADMIN_USER сохранен"
        else
            echo
            read -rp "Удалить административного пользователя $ADMIN_USER? [y/N]: " answer
            case "$answer" in
                [Yy]*)
                    if userdel -r "$ADMIN_USER" 2>/dev/null; then
                        log OK "Пользователь $ADMIN_USER удален"
                        ((restored_count++))
                    else
                        log WARN "Не удалось удалить пользователя $ADMIN_USER"
                        ((errors++))
                    fi
                    ;;
                [Nn]*|"")
                    log INFO "Пользователь $ADMIN_USER сохранен"
                    ;;
            esac
        fi
    fi
    
    if [[ $errors -gt 0 ]]; then
        log WARN "Восстановление завершено с $errors ошибками ($restored_count операций выполнено)"
        # Не возвращаем ошибку для некритичных проблем
        return 0
    else
        log OK "Восстановление завершено ($restored_count операций выполнено)"
        return 0
    fi
}

# === Восстановление root-доступа ===
users_restore_root_access() {
    # Разблокировка пароля root
    if passwd -u root 2>/dev/null; then
        log OK "Пароль root разблокирован"
    else
        log WARN "Ошибка разблокировки пароля root"
    fi
    
    # Восстановление shell для root
    if usermod -s /bin/bash root; then
        log OK "Shell для root восстановлен"
    else
        log WARN "Ошибка восстановления shell для root"
    fi
    
    # Восстановление SSH конфигурации
    local sshd_config="/etc/ssh/sshd_config"
    if [[ -f "$sshd_config" ]]; then
        # Восстановление из резервной копии
        local backup_file
        backup_file="$(find "${SCRIPT_DIR}/backups/system" -name "sshd_config*" | sort | tail -n1)"
        if [[ -n "$backup_file" && -f "$backup_file" ]]; then
            if cp -a "$backup_file" "$sshd_config"; then
                log OK "Восстановлена SSH конфигурация из: $backup_file"
            else
                log WARN "Ошибка восстановления SSH конфигурации"
            fi
        else
            # Удаление настройки PermitRootLogin
            if sed -i '/^PermitRootLogin no/d' "$sshd_config"; then
                log OK "Удалена настройка PermitRootLogin из SSH"
            else
                log WARN "Ошибка удаления настройки PermitRootLogin"
            fi
        fi
        
        # Перезапуск SSH
        if systemctl restart ssh >/dev/null 2>&1; then
            log OK "SSH сервис перезапущен"
        else
            log WARN "Ошибка перезапуска SSH сервиса"
        fi
    fi
    
    ROOT_ACCESS_DISABLED=false
    return 0
}

# === Статус пользователей ===
users_status() {
    echo "=== Статус пользователей ==="
    echo "Административный пользователь: ${ADMIN_USER:-не создан}"
    
    if [[ -n "$ADMIN_USER" ]]; then
        if id "$ADMIN_USER" &>/dev/null; then
            echo "  Статус: существует"
            echo "  Группы: $(groups "$ADMIN_USER" 2>/dev/null || echo "неизвестно")"
            echo "  Shell: $(getent passwd "$ADMIN_USER" | cut -d: -f7)"
            echo "  Домашняя директория: $(getent passwd "$ADMIN_USER" | cut -d: -f6)"
        else
            echo "  Статус: не существует"
        fi
    fi
    
    echo "Root-доступ: $(users_is_root_access_enabled && echo "включён" || echo "отключён")"
}

# === Проверка включенности root-доступа ===
users_is_root_access_enabled() {
    # Проверка блокировки пароля
    if passwd -S root 2>/dev/null | grep -q "L "; then
        return 1  # Пароль заблокирован
    fi
    
    # Проверка shell
    local root_shell
    root_shell="$(getent passwd root | cut -d: -f7)"
    if [[ "$root_shell" == "/usr/sbin/nologin" || "$root_shell" == "/bin/false" ]]; then
        return 1  # Shell отключен
    fi
    
    # Проверка SSH конфигурации
    if [[ -f "/etc/ssh/sshd_config" ]]; then
        if grep -q "^PermitRootLogin no" "/etc/ssh/sshd_config"; then
            return 1  # Root-доступ в SSH отключен
        fi
    fi
    
    return 0  # Root-доступ включен
}

# === Валидация пользователей ===
users_validate() {
    log INFO "Валидация управления пользователями"
    
    local errors=0
    local warnings=0
    
    # Проверка утилит
    if ! command -v useradd >/dev/null 2>&1; then
        log ERROR "useradd не найден"
        ((errors++))
    fi
    
    if ! command -v passwd >/dev/null 2>&1; then
        log ERROR "passwd не найден"
        ((errors++))
    fi
    
    # Проверка прав доступа
    if [[ "$EUID" -ne 0 ]]; then
        log ERROR "Недостаточно прав для управления пользователями"
        ((errors++))
    fi
    
    # Проверка административного пользователя
    if [[ -n "$ADMIN_USER" ]]; then
        if ! id "$ADMIN_USER" &>/dev/null; then
            log WARN "Административный пользователь $ADMIN_USER не существует"
            ((warnings++))
        fi
    fi
    
    if [[ $errors -gt 0 ]]; then
        log ERROR "Валидация завершена с $errors ошибками и $warnings предупреждениями"
        return 1
    elif [[ $warnings -gt 0 ]]; then
        log WARN "Валидация завершена с $warnings предупреждениями"
        return 0
    else
        log OK "Валидация завершена успешно"
        return 0
    fi
}

# === Получение информации о пользователях ===
users_info() {
    echo "=== Информация о пользователях ==="
    echo "Административный пользователь: ${ADMIN_USER:-не установлен}"
    echo "Root-доступ отключен: $ROOT_ACCESS_DISABLED"
    
    if [[ -n "$ADMIN_USER" ]]; then
        echo "SSH-ключ настроен: $([ -n "$ADMIN_SSH_KEY" ] && echo "да" || echo "нет")"
        echo "Пароль настроен: $([ -n "$ADMIN_PASSWORD" ] && echo "да" || echo "нет")"
    fi
}

# === Экспорт функций ===
export -f users_init users_create_admin users_skip_admin_setup users_create_admin_impl
export -f users_create_or_update_admin_user users_ensure_groups_exist users_set_admin_password
export -f users_set_admin_ssh_key users_set_admin_sudo_rights users_disable_root_login
export -f users_restore users_status users_validate users_info
export -f users_validate_username users_validate_ssh_key users_disable_root_ssh_access
export -f users_restore_root_access users_is_root_access_enabled

# Автоматическая инициализация при загрузке компонента
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Если скрипт запущен напрямую
    users_init "$@"
else
    # Если скрипт загружен как компонент
    users_init
fi