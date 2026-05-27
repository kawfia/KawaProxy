# [6] Telegram Local Server

## Задача
Собрать `telegram-bot-api` из исходников и зарегистрировать systemd-сервис на порту `:8082`.

## Цель
Локальный Bot API сервер на nodeA — опциональный компонент (только если `INSTALL_TG=1`).

## Обоснование
Официальных бинарных пакетов нет — только сборка из исходников через cmake.

## Ссылки
- [telegram-bot-api GitHub](https://github.com/tdlib/telegram-bot-api)

## Детали

### Зависимости сборки (apt)
`cmake g++ make zlib1g-dev libssl-dev gperf`

### Исходники
Директория: `/opt/tg-bot-api-src`
Клонирование: `git clone --recursive https://github.com/tdlib/telegram-bot-api.git`

### Сборка (cmake)
```
cmake -DCMAKE_BUILD_TYPE=Release -S /opt/tg-bot-api-src -B /opt/tg-bot-api-src/build
cmake --build /opt/tg-bot-api-src/build --target install
```

### Бинарник
Путь после `install`: `/usr/local/bin/telegram-bot-api`

### Порты и параметры
| Параметр | Значение |
|---|---|
| Порт (внутренний, nodeA) | `:8082` |
| Аргумент порта | `--http-port=8082` |
| Аргумент режима | `--local` |
| Аргументы API | `--api-id=$TG_API_ID --api-hash=$TG_API_HASH` |

### systemd-сервис
Файл: `/etc/systemd/system/telegram-bot-api.service`

| Параметр | Значение |
|---|---|
| `User` | `nobody` |
| `Restart` | `on-failure` |
| `RestartSec` | `5` |
