# [8] Установка Caddy

## Задача
Собрать кастомный бинарник Caddy с плагином `forwardproxy` через `xcaddy`.

## Цель
Caddy с поддержкой HTTP CONNECT forward proxy.

## Обоснование
Стандартный пакет Caddy из apt не поддерживает сторонние плагины — xcaddy компилирует бинарник с нужным модулем.

## Предусловия
- Базовая ОС готова (задача 3)
- Пакеты `golang-go`, `curl` установлены

## Результат
- `/usr/bin/caddy` собран с плагином `forwardproxy`
- `setcap cap_net_bind_service=+ep /usr/bin/caddy` применён
- Systemd-сервис зарегистрирован и **остановлен**
- **Не создаёт**: `/etc/caddy/Caddyfile` — это задача 9

## Ссылки
- [xcaddy](https://github.com/caddyserver/xcaddy)
- [Caddy forwardproxy](https://github.com/caddyserver/forwardproxy)

## Связанные задачи
| Задача | Роль |
|---|---|
| [9 — Настройка Caddy](9-caddy-config.md) | конфигурация после установки бинарника |

## Детали

### Зависимости
| Пакет | Назначение |
|---|---|
| `golang-go` | Компилятор Go (apt) |

### xcaddy
| Параметр | Значение |
|---|---|
| Установка | `go install github.com/caddyserver/xcaddy/cmd/xcaddy@v0.4.5` |
| GOPATH | `/root/go` |
| Бинарник | `${GOPATH}/bin/xcaddy` |

### Сборка Caddy
Плагины:
- `github.com/caddyserver/forwardproxy@caddy2`

Примерная длительность сборки: 2–5 минут.

### Бинарник
| Параметр | Значение |
|---|---|
| Путь | `/usr/bin/caddy` |
| Права | `cap_net_bind_service=+ep` (setcap, для привязки к :80) |

### Порядок установки
1. Установить пакет `caddy` из apt (для получения unit-файла systemd)
2. Остановить `caddy.service`
3. Собрать кастомный бинарник через xcaddy
4. Заменить `/usr/bin/caddy` собранным бинарником
