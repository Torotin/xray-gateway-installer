# Плагин Firewall для Xray Gateway Installer

## 📋 Описание

Плагин управления файрволом и kill-switch функциональностью для Xray Gateway. Обеспечивает автоматическое управление iptables правилами, переключение между активным и kill-switch режимами.

## 🏗️ Структура плагина

```
plugins/firewall/
├── firewall.sh                    # Основной файл плагина
├── README.md                      # Документация
├── scripts/                       # Исполняемые скрипты
│   ├── killswitch-watchdog.sh    # Мониторинг kill-switch
│   ├── switch-to-enabled.sh      # Переключение в активный режим
│   └── switch-to-disabled.sh     # Переключение в kill-switch режим
├── systemd/                       # Systemd юниты
│   ├── xray-killswitch-monitor.service
│   └── xray-killswitch-watchdog.service
├── configs/                       # Конфигурационные файлы
│   ├── firewall.conf             # Основная конфигурация
│   ├── exclude_cidrs.txt         # Исключения CIDR
│   ├── exclude_ips.txt           # Исключения IP
│   └── exclude_ports.txt         # Исключения портов
└── utils/                         # Утилиты
    ├── firewall-utils.sh         # Вспомогательные функции
    └── interface-detector.sh      # Детектор интерфейсов
```

## 🚀 Функциональность

### Основные возможности:
- **Управление iptables правилами** - автоматическое создание и управление правилами
- **Kill-switch режим** - блокировка внешнего трафика при остановке Xray
- **Автоматическое переключение** - мониторинг статуса Xray и переключение режимов
- **Исключения** - настраиваемые исключения для CIDR, IP и портов
- **Systemd интеграция** - автоматический запуск и управление через systemd

### Режимы работы:
1. **Активный режим** - Xray работает, трафик проходит через прокси
2. **Kill-switch режим** - Xray остановлен, внешний трафик заблокирован

## 📖 Использование

### Установка плагина:
```bash
./installer.sh install --plugin firewall
```

### Управление файрволом:
```bash
# Запуск файрвола
./installer.sh firewall start

# Остановка файрвола
./installer.sh firewall stop

# Переключение в активный режим
./installer.sh firewall enable

# Переключение в kill-switch режим
./installer.sh firewall disable

# Диагностика
./installer.sh firewall diagnose
```

### Прямое использование скриптов:
```bash
# Переключение режимов
/opt/xray/iptables/xray-iptables.sh enable
/opt/xray/iptables/xray-iptables.sh disable

# Диагностика
/opt/xray/iptables/xray-iptables.sh diagnose
```

## ⚙️ Конфигурация

### Основные настройки (firewall.conf):
```ini
[firewall]
check_interval = 5
log_level = INFO

[killswitch]
auto_killswitch = true
enable_watchdog = true

[exclusions]
system_exclusions = true
custom_exclusions = true
```

### Исключения:
- **exclude_cidrs.txt** - CIDR сети для исключения
- **exclude_ips.txt** - IP адреса для исключения  
- **exclude_ports.txt** - TCP порты для исключения

## 🔧 Утилиты

### firewall-utils.sh:
- Проверка зависимостей
- Статистика правил
- Резервное копирование
- Тестирование блокировки

### interface-detector.sh:
- Автоматическое определение интерфейсов
- Получение CIDR
- Проверка статуса интерфейсов

## 📊 Мониторинг

### Systemd юниты:
- **xray-killswitch-monitor.service** - мониторинг статуса Xray
- **xray-killswitch-watchdog.service** - автоматическое переключение

### Логи:
- Основные логи: `/var/log/xray-firewall.log`
- Watchdog логи: `/var/log/xray-killswitch-watchdog.log`
- Systemd логи: `journalctl -u xray-killswitch-*`

## 🛠️ Разработка

### Добавление новых функций:
1. Создайте функцию в `firewall.sh`
2. Добавьте обработку в `plugin_firewall_execute()`
3. Обновите документацию

### Тестирование:
```bash
# Проверка зависимостей
./utils/firewall-utils.sh check_dependencies

# Тестирование блокировки
./utils/firewall-utils.sh test_blocking

# Диагностика интерфейсов
./utils/interface-detector.sh detect
```

## 📝 Зависимости

- **iptables** - управление правилами файрвола
- **iproute2** - работа с маршрутами
- **systemd** - управление сервисами
- **jq** - парсинг JSON конфигураций
- **curl** - тестирование блокировки

## 🔒 Безопасность

- Все скрипты требуют права root
- Автоматическое создание исключений для локальных сетей
- Резервное копирование правил перед изменениями
- Graceful handling ошибок

## 📞 Поддержка

При возникновении проблем:
1. Проверьте логи: `journalctl -u xray-killswitch-*`
2. Запустите диагностику: `./installer.sh firewall diagnose`
3. Проверьте статус: `./installer.sh firewall status`
