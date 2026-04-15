#!/usr/bin/env bash

# === Переключение в активный режим ===
# Версия: 2.0.0
# Автор: Xray Gateway Installer Team

# Загрузка скрипта файрвола
FIREWALL_SCRIPT="/opt/xray/iptables/xray-iptables.sh"

if [[ -f "$FIREWALL_SCRIPT" ]]; then
    "$FIREWALL_SCRIPT" enable
    exit $?
else
    echo "ERROR: Скрипт файрвола не найден: $FIREWALL_SCRIPT"
    exit 1
fi
