# [9] Настройка Caddy

## Задача
Записать `/etc/caddy/Caddyfile` с forward_proxy, probe_resistance и reverse_proxy, затем запустить сервис.

## Цель
Caddy принимает трафик от telemt (:8443), обслуживает HTTP CONNECT для клиентов и возвращает легитимный сайт сканерам.

## Обоснование
`probe_resistance` без аутентификации возвращает `200 OK` и страницу сайта вместо `407` — прокси не детектируется. Caddy получает LE-сертификат сам через ACME (:80).

## Предусловия
- Caddy установлен (задача 8)
- telemt настроен и проксирует на `:8443` (задача 5)
- `NODE_DOMAIN`, `FP_CREDS`, `BACK_HOP` заданы (задача 1)

## Результат
- `/etc/caddy/Caddyfile` записан
- `systemctl is-active caddy` → `active`
- `:8443` отвечает (telemt → caddy работает)

## Ссылки
- [Caddy forwardproxy](https://github.com/caddyserver/forwardproxy)

## Связанные задачи
| Задача | Параметры |
|---|---|
| [1 — Переменные](1-variables.md) | `NODE_DOMAIN`, `FP_CREDS`, `FP_EXTRA`, `BACK_HOP`, `INSTALL_DOTNET` |
| [8 — Установка Caddy](8-caddy-install.md) | расположение бинарника `/usr/bin/caddy` |

## Детали

### Порты
| Порт | Назначение | Видимость |
|---|---|---|
| `:80` | Caddy ACME HTTP-challenge | Публичный |
| `:8443` | HTTPS (FP + RP), принимает от telemt | Внутренний |

### Глобальные параметры (`{ }`)
| Параметр | Значение |
|---|---|
| `http_port` | `80` |
| `https_port` | `8443` |
| `admin` | `off` |
| `order` | `forward_proxy before reverse_proxy` |

### Директива `forward_proxy`
| Параметр | Значение |
|---|---|
| `basic_auth user pass` | По одному на каждую пару из `$FP_CREDS` |
| `probe_resistance` | Без аргументов |
| `hide_ip` | Включено |
| `hide_via` | Включено |

### Блок `handle` (reverse proxy / backend)
| Условие | Конфигурация |
|---|---|
| `INSTALL_DOTNET=1` | `reverse_proxy localhost:8081` |
| `INSTALL_DOTNET=0` и `BACK_HOP` задан | `reverse_proxy BACK_HOP` (nodeN/nodeZ) |
| `INSTALL_DOTNET=0` и `BACK_HOP` пуст | `file_server` со стандартной страницей-заглушкой Caddy |

> **Важно:** При `file_server` использовать только стандартные возможности Caddy. Самописная HTML и сторонние движки — запрещены.

### Конфигурация домена
Сертификат: Caddy получает LE автоматически для `$NODE_DOMAIN` через ACME (:80).
