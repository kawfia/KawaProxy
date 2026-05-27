# [3] Базовая настройка сервера

## Задача
Применить базовую конфигурацию ОС: hostname, IPv6, системные пакеты, ulimits, UFW, fail2ban.

## Цель
Подготовить сервер к установке компонентов с минимальной поверхностью атаки.

## Обоснование
UFW + fail2ban — необходимый минимум безопасности для публично доступного сервера.

## Предусловия
- Переменные объявлены (задача 1)
- Валидация добавлена (задача 2)

## Результат
- hostname применён, `/etc/hosts` обновлён
- IPv6 отключён (если `ENABLE_IPV6=0`)
- Пакеты установлены, ulimits применены
- UFW: порты `:22`, `:80`, `:443` открыты
- fail2ban настроен и запущен
- **Не устанавливает**: telemt, Caddy, .NET, Telegram Local Server

## Ссылки

## Связанные задачи
| Задача | Параметры |
|---|---|
| [1 — Переменные](1-variables.md) | `NODE_HOSTNAME`, `NODE_DOMAIN`, `ENABLE_IPV6`, `FAIL2BAN_MAXRETRY`, `FAIL2BAN_FINDTIME`, `FAIL2BAN_BANTIME` |

## Детали

### Hostname
- `hostnamectl set-hostname $NODE_HOSTNAME`
- Добавить `127.0.1.1 $NODE_HOSTNAME` в `/etc/hosts` (если отсутствует)

### IPv6 (если `ENABLE_IPV6=0`)
Файл: `/etc/sysctl.d/99-no-ipv6.conf`

| Параметр | Значение |
|---|---|
| `net.ipv6.conf.all.disable_ipv6` | `1` |
| `net.ipv6.conf.default.disable_ipv6` | `1` |
| `net.ipv6.conf.lo.disable_ipv6` | `1` |

Применить: `sysctl --system`

### Системные пакеты (apt)
`curl wget git ca-certificates gnupg ufw fail2ban openssl xxd debian-keyring debian-archive-keyring apt-transport-https`

### ulimits
Файл: `/etc/security/limits.conf`

| Параметр | Значение |
|---|---|
| `* soft nofile` | `65535` |
| `* hard nofile` | `65535` |

### UFW
| Правило | Значение |
|---|---|
| Default incoming | `deny` |
| Default outgoing | `allow` |
| Открыть порты | `:22/tcp`, `:80/tcp`, `:443/tcp` |

### fail2ban
Файл: `/etc/fail2ban/jail.local`

| Параметр | Переменная |
|---|---|
| `[sshd] enabled` | `true` |
| `maxretry` | `$FAIL2BAN_MAXRETRY` |
| `findtime` | `$FAIL2BAN_FINDTIME` |
| `bantime` | `$FAIL2BAN_BANTIME` |
