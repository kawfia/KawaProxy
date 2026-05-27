# [3] Базовая настройка сервера

## Задача
Применить базовую конфигурацию ОС: hostname, IPv6, системные пакеты, ulimits, UFW, fail2ban.

## Цель
Подготовить сервер к установке компонентов с минимальной поверхностью атаки.

## Обоснование
UFW + fail2ban — необходимый минимум безопасности для публично доступного сервера.

## Ссылки

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
