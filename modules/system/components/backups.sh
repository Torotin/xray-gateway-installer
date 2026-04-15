#!/usr/bin/env bash

# === Компонент резервного копирования ===
# Версия: 2.2.0 (Рефакторинг)
# Автор: Xray Gateway Installer Team

# === Глобальные переменные компонента ===
declare -g SYSTEM_BACKUP_DIR="${SCRIPT_DIR}/backups/system"
declare -g BACKUP_RETENTION_DAYS=30
declare -g BACKUP_COMPRESSION=true

# === Инициализация компонента ===
backups_init() {
    log INFO "Инициализация компонента резервного копирования"
    
    # Создание директории для бэкапов
    if ! create_directory "$SYSTEM_BACKUP_DIR" "root" "root" "755"; then
        log ERROR "Ошибка создания директории резервных копий"
        return 1
    fi
    
    # Проверка доступности утилит
    if ! command -v tar >/dev/null 2>&1; then
        log WARN "Утилита tar не найдена, сжатие будет недоступно"
        BACKUP_COMPRESSION=false
    fi
    
    log OK "Компонент резервного копирования инициализирован"
    return 0
}

# === Создание резервных копий ===
backups_create() {
    log INFO "Создание резервных копий системных конфигураций"
    
    local timestamp
    timestamp="$(date '+%Y%m%d_%H%M%S')"
    local backup_dir="$SYSTEM_BACKUP_DIR/$timestamp"
    local backup_archive=""
    
    # Создание директории резервной копии
    if ! create_directory "$backup_dir" "root" "root" "755"; then
        log ERROR "Ошибка создания директории резервной копии"
        return 1
    fi
    
    # Создание метаданных резервной копии
    backups_create_metadata "$backup_dir"
    
    # Резервное копирование системных конфигураций
    local config_files=(
        "/etc/default/grub"
        "/etc/ssh/sshd_config"
        "/etc/sysctl.d"
    )
    
    local copied_count=0
    local skipped_count=0
    
    for config in "${config_files[@]}"; do
        if [[ -e "$config" ]]; then
            if [[ -f "$config" ]]; then
                if cp -a "$config" "$backup_dir/"; then
                    log OK "Скопирован файл: $config"
                    ((copied_count++))
                else
                    log WARN "Ошибка копирования файла: $config"
                    ((skipped_count++))
                fi
            elif [[ -d "$config" ]]; then
                if cp -a "$config" "$backup_dir/"; then
                    log OK "Скопирована директория: $config"
                    ((copied_count++))
                else
                    log WARN "Ошибка копирования директории: $config"
                    ((skipped_count++))
                fi
            fi
        else
            log DEBUG "Файл/директория не найдена: $config"
            ((skipped_count++))
        fi
    done
    
    # Создание архива если включено сжатие
    if [[ "$BACKUP_COMPRESSION" == "true" ]]; then
        backup_archive="$backup_dir.tar.gz"
        if tar -czf "$backup_archive" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")" 2>/dev/null; then
            log OK "Создан архив: $backup_archive"
            rm -rf "$backup_dir"
            backup_dir="$backup_archive"
        else
            log WARN "Ошибка создания архива, сохраняем как директорию"
        fi
    fi
    
    # Очистка старых резервных копий
    backups_cleanup_old
    
    log OK "Резервные копии созданы: $copied_count файлов/директорий скопировано, $skipped_count пропущено"
    log INFO "Расположение: $backup_dir"
    return 0
}

# === Создание метаданных резервной копии ===
backups_create_metadata() {
    local backup_dir="$1"
    local metadata_file="$backup_dir/backup_metadata.txt"
    
    cat > "$metadata_file" << EOF
# Метаданные резервной копии
Дата создания: $(date)
Версия системы: $(uname -r)
Пользователь: $(whoami)
Хост: $(hostname)
Версия компонента: 2.2.0
Тип резервной копии: системные настройки
EOF
    
    log DEBUG "Созданы метаданные резервной копии: $metadata_file"
}

# === Восстановление из резервных копий ===
backups_restore() {
    log INFO "Восстановление из резервных копий"
    
    local latest_backup
    latest_backup="$(find "$SYSTEM_BACKUP_DIR" -maxdepth 1 -type d -name "20*" | sort | tail -n1)"
    
    # Проверка архивов если директории не найдены
    if [[ -z "$latest_backup" || ! -d "$latest_backup" ]]; then
        latest_backup="$(find "$SYSTEM_BACKUP_DIR" -maxdepth 1 -name "20*.tar.gz" | sort | tail -n1)"
        if [[ -n "$latest_backup" && -f "$latest_backup" ]]; then
            log INFO "Найден архив резервной копии: $latest_backup"
            if ! backups_extract_archive "$latest_backup"; then
                log ERROR "Ошибка извлечения архива"
                return 1
            fi
            # Обновляем путь к извлеченной директории
            latest_backup="${latest_backup%.tar.gz}"
        else
            log INFO "Резервные копии не найдены, пропуск восстановления"
            return 0
        fi
    fi
    
    if [[ -z "$latest_backup" || ! -d "$latest_backup" ]]; then
        log ERROR "Не удалось найти резервную копию для восстановления"
        return 1
    fi
    
    log INFO "Восстановление из: $latest_backup"
    
    local restored_count=0
    local failed_count=0
    
    # Восстановление файлов
    if [[ -f "$latest_backup/grub" ]]; then
        if cp -a "$latest_backup/grub" "/etc/default/grub"; then
            log OK "Восстановлен файл: /etc/default/grub"
            ((restored_count++))
        else
            log WARN "Ошибка восстановления файла: /etc/default/grub"
            ((failed_count++))
        fi
    fi
    
    if [[ -f "$latest_backup/sshd_config" ]]; then
        if cp -a "$latest_backup/sshd_config" "/etc/ssh/sshd_config"; then
            log OK "Восстановлен файл: /etc/ssh/sshd_config"
            ((restored_count++))
        else
            log WARN "Ошибка восстановления файла: /etc/ssh/sshd_config"
            ((failed_count++))
        fi
    fi
    
    if [[ -d "$latest_backup/sysctl.d" ]]; then
        if [[ -d "/etc/sysctl.d" ]]; then
            rm -rf "/etc/sysctl.d"
        fi
        if cp -a "$latest_backup/sysctl.d" "/etc/"; then
            log OK "Восстановлена директория: /etc/sysctl.d"
            ((restored_count++))
        else
            log WARN "Ошибка восстановления директории: /etc/sysctl.d"
            ((failed_count++))
        fi
    fi
    
    if [[ $failed_count -gt 0 ]]; then
        log WARN "Восстановление завершено с $failed_count ошибками ($restored_count файлов восстановлено)"
        return 1
    else
        log OK "Восстановление завершено ($restored_count файлов восстановлено)"
        return 0
    fi
}

# === Извлечение архива резервной копии ===
backups_extract_archive() {
    local archive="$1"
    local extract_dir="${archive%.tar.gz}"
    
    if [[ -d "$extract_dir" ]]; then
        log DEBUG "Директория уже извлечена: $extract_dir"
        return 0
    fi
    
    if tar -xzf "$archive" -C "$(dirname "$archive")" 2>/dev/null; then
        log OK "Архив извлечен: $extract_dir"
        return 0
    else
        log ERROR "Ошибка извлечения архива: $archive"
        return 1
    fi
}

# === Очистка старых резервных копий ===
backups_cleanup_old() {
    log DEBUG "Очистка резервных копий старше $BACKUP_RETENTION_DAYS дней"
    
    local cutoff_date
    cutoff_date="$(date -d "$BACKUP_RETENTION_DAYS days ago" '+%Y%m%d' 2>/dev/null || date '+%Y%m%d')"
    
    local cleaned_count=0
    
    # Очистка директорий
    while IFS= read -r -d '' backup_dir; do
        local backup_date
        backup_date="$(basename "$backup_dir" | cut -d'_' -f1)"
        if [[ "$backup_date" < "$cutoff_date" ]]; then
            if rm -rf "$backup_dir"; then
                log DEBUG "Удалена старая резервная копия: $backup_dir"
                ((cleaned_count++))
            fi
        fi
    done < <(find "$SYSTEM_BACKUP_DIR" -maxdepth 1 -type d -name "20*" -print0 2>/dev/null)
    
    # Очистка архивов
    while IFS= read -r -d '' backup_archive; do
        local backup_date
        backup_date="$(basename "$backup_archive" | cut -d'_' -f1)"
        if [[ "$backup_date" < "$cutoff_date" ]]; then
            if rm -f "$backup_archive"; then
                log DEBUG "Удален старый архив: $backup_archive"
                ((cleaned_count++))
            fi
        fi
    done < <(find "$SYSTEM_BACKUP_DIR" -maxdepth 1 -name "20*.tar.gz" -print0 2>/dev/null)
    
    if [[ $cleaned_count -gt 0 ]]; then
        log INFO "Очищено старых резервных копий: $cleaned_count"
    fi
}

# === Статус резервных копий ===
backups_status() {
    local backup_count=0
    local archive_count=0
    local total_size=0
    
    # Подсчет директорий
    backup_count="$(find "$SYSTEM_BACKUP_DIR" -maxdepth 1 -type d -name "20*" 2>/dev/null | wc -l)"
    
    # Подсчет архивов
    archive_count="$(find "$SYSTEM_BACKUP_DIR" -maxdepth 1 -name "20*.tar.gz" 2>/dev/null | wc -l)"
    
    # Подсчет общего размера
    total_size="$(du -sh "$SYSTEM_BACKUP_DIR" 2>/dev/null | cut -f1 || echo "0")"
    
    echo "Резервные копии: $backup_count директорий, $archive_count архивов"
    echo "Общий размер: $total_size"
    
    if [[ $((backup_count + archive_count)) -gt 0 ]]; then
        local latest_backup
        latest_backup="$(find "$SYSTEM_BACKUP_DIR" -maxdepth 1 \( -type d -name "20*" -o -name "20*.tar.gz" \) | sort | tail -n1)"
        if [[ -n "$latest_backup" ]]; then
            echo "Последняя копия: $(basename "$latest_backup")"
        fi
    fi
}

# === Валидация резервных копий ===
backups_validate() {
    log INFO "Валидация резервных копий"
    
    local valid_count=0
    local invalid_count=0
    
    # Проверка директорий
    while IFS= read -r -d '' backup_dir; do
        if [[ -f "$backup_dir/backup_metadata.txt" ]]; then
            log DEBUG "Валидная резервная копия: $backup_dir"
            ((valid_count++))
        else
            log WARN "Невалидная резервная копия (нет метаданных): $backup_dir"
            ((invalid_count++))
        fi
    done < <(find "$SYSTEM_BACKUP_DIR" -maxdepth 1 -type d -name "20*" -print0 2>/dev/null)
    
    if [[ $invalid_count -gt 0 ]]; then
        log WARN "Найдено $invalid_count невалидных резервных копий"
        return 1
    else
        log OK "Все резервные копии валидны ($valid_count проверено)"
        return 0
    fi
}

# === Экспорт функций ===
export -f backups_init backups_create backups_restore backups_status backups_validate
export -f backups_create_metadata backups_extract_archive backups_cleanup_old

# Автоматическая инициализация при загрузке компонента
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Если скрипт запущен напрямую
    backups_init "$@"
else
    # Если скрипт загружен как компонент
    backups_init
fi