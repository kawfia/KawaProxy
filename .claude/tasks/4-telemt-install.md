# [4] Установка telemt

## Задача
Загрузить и запустить официальный установщик telemt.

## Цель
Установить бинарник telemt и зарегистрировать systemd-сервис.

## Обоснование
Официальный installer из репозитория самостоятельно определяет архитектуру, скачивает бинарник и регистрирует сервис — ручная сборка не требуется.

## Ссылки
- [telemt GitHub](https://github.com/telemt/telemt)
- [Quick Start RU](https://github.com/telemt/telemt/blob/main/docs/Quick_start/QUICK_START_GUIDE.ru.md)

## Детали

### Установщик
URL: `https://raw.githubusercontent.com/telemt/telemt/main/install.sh`

Команда: `curl -fsSL <url> | sh`

Для конкретной версии: `curl -fsSL <url> | sh -s -- <version>`

### После установки
- Остановить сервис (`systemctl stop telemt`) — конфиг ещё не написан
- Установщик создаёт директорию `/etc/telemt/`

### Порты и пути
| Параметр | Значение |
|---|---|
| Конфиг | `/etc/telemt/telemt.toml` |
| TLS front dir | `/etc/telemt/tlsfront/` |
| Порт (публичный) | `:443` |
| API (внутренний) | `127.0.0.1:9091` |
