# REFERENCE.md — KawaProxy

## Версии ПО

| Компонент | Версия | Назначение |
|---|---|---|
| Ubuntu | 24.04 LTS Noble | ОС |
| ufw | 0.36.x | Firewall |
| fail2ban | 1.0.2 | Защита SSH от брутфорса |
| telemt | latest (3.3.x) | MTProto-прокси + TLS mask (ee mode) |
| Caddy | 2.11.2 (xcaddy сборка) | HTTPS / forward-proxy / SOCKS5 |
| └─ forwardproxy | latest | HTTP CONNECT forward proxy (caddy FP) |
| └─ caddy-l4 | latest | SOCKS5 / Layer4 routing |
| xcaddy | 0.4.5 | Сборщик кастомного Caddy |
| golang-go | 1.22 (apt) | Зависимость для xcaddy |
| Telegram Local Server | latest | Local bot API server (только node0) |
| .NET | 10 | Backend app (только node0) |

---

## Переменные MASTER CONFIG (deploy/env/*.env)

```sh
# --- идентификация ноды ---
NODE_HOSTNAME=""          # hostname сервера (задаётся через hostnamectl)
NODE_DOMAIN=""            # публичный FQDN ноды (нужен для LE-сертификата)

# --- роль ноды ---
NEXT_HOP=""               # пусто = node0; "host:443" = nodeN (chain)

# --- telemt пользователи ---
# секрет = 32 hex символа: openssl rand -hex 16  или  echo -n "name" | sha256sum | cut -c1-32
TELEMT_USERS=(
  "alias1"                # SHA256[:32] → секрет в config.toml
  "alias2"
  "alias3"
  "alias4"
)
TELEMT_TLS_DOMAIN=""      # SNI-домен для TLS-fronting (любой публичный TLS-домен)

# --- caddy FP (forward proxy) пользователи ---
FP_USERS=(
  "fpuser1:PASSWORD"
  "fpuser2:PASSWORD"
)

# --- caddy-l4 SOCKS5 пользователи (telemt upstream, internal) ---
SOCKS5_USERS=(
  "socks5user1:PASSWORD"
)

# --- только node0 ---
TG_API_ID=""              # Telegram App API ID
TG_API_HASH=""            # Telegram App API Hash

# --- опции ---
ENABLE_IPV6=0
FAIL2BAN_MAXRETRY=15
FAIL2BAN_FINDTIME=300
FAIL2BAN_BANTIME=-1       # -1 = permanent ban
```

---

## Генерация секретов telemt

```sh
# случайный секрет
openssl rand -hex 16

# детерминированный из имени пользователя
echo -n "username" | sha256sum | cut -c1-32
```

Секрет — ровно 32 hex символа. Используется в `[access.users]` config.toml и в MTProto-ссылке.

---

## MTProto ссылки (после запуска telemt)

```sh
journalctl -u telemt --no-pager -o cat | grep link
```

Ссылки формирует сам telemt на основе `public_host`, `public_port` и секретов пользователей.

---

## Структура файлов на ноде после деплоя

```
/etc/telemt/
├── config.toml
└── tlsfront/

/etc/caddy/
├── Caddyfile              # HTTPS :8443 (FP + RP)
└── l4.json                # SOCKS5 :8083 (internal)

/usr/bin/caddy             # кастомная сборка с плагинами
```

---

## Сервисы systemd

| Сервис | Все ноды | Только node0 |
|---|---|---|
| `telemt.service` | ✅ | |
| `caddy.service` | ✅ | |
| `telegram-bot-api.service` | | ✅ |
| (backend app) | | ✅ |

---

## UFW правила

```sh
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # Caddy ACME
ufw allow 443/tcp   # telemt
ufw enable
```

Порты `:8081`, `:8082`, `:8083`, `:8443`, `:9091` — только `127.0.0.1`, UFW не нужен.

---

## fail2ban

Защита SSH: `sshd` jail.

```ini
[sshd]
enabled  = true
maxretry = FAIL2BAN_MAXRETRY   # default 15
findtime = FAIL2BAN_FINDTIME   # default 300s
bantime  = FAIL2BAN_BANTIME    # default -1 (permanent)
```

---

## Ссылки на документацию компонентов

| Ресурс | URL |
|---|---|
| telemt репозиторий | https://github.com/telemt/telemt |
| telemt Quick Start RU | https://github.com/telemt/telemt/blob/main/docs/QUICK_START_GUIDE.ru.md |
| telemt Double Hop RU | https://github.com/telemt/telemt/blob/main/docs/VPS_DOUBLE_HOP.ru.md |
| telemt Config Params RU | https://github.com/telemt/telemt/blob/main/docs/Config_params/CONFIG_PARAMS.ru.md |
| Caddy forwardproxy | https://github.com/caddyserver/forwardproxy |
| caddy-l4 | https://github.com/mholt/caddy-l4 |
| xcaddy | https://github.com/caddyserver/xcaddy |
| Telegram Local Server | https://github.com/tdlib/telegram-bot-api |
| .NET 10 Linux | https://learn.microsoft.com/dotnet/core/install/linux-ubuntu |

---

## Статус реализации catharsis.sh

### Реализовано (v0.1)

- ✅ Шаг 1: система (hostname, timezone, apt upgrade, ulimits)
- ✅ Шаг 2: ufw (22/80/443 открыты)
- ✅ Шаг 3: fail2ban (SSH protection)
- ✅ Шаг 4: telemt (ee mode, mask → `:8443`, SOCKS5 upstream stub)
- ✅ Шаг 5: Caddy apt (стандартный, без плагинов) — отдаёт страницу на `:8443`
- ✅ Шаг 6: вывод кредов и статуса сервисов

### Не реализовано

- ❌ Caddy xcaddy сборка с плагинами (`forwardproxy` + `caddy-l4`)
- ❌ Caddy forward_proxy конфиг (caddy FP)
- ❌ caddy-l4 SOCKS5 на `:8083`
- ❌ caddy RP: `reverse_proxy` на `NEXT_HOP` или backend
- ❌ Логика ветвления node0 / nodeN в скрипте (`NEXT_HOP`)
- ❌ Telegram Local Server (только node0)
- ❌ .NET 10 установка (только node0)

---

## Примечания по безопасности

- `telemt` API слушает только `127.0.0.1:9091`, whitelist `127.0.0.0/8`
- caddy-l4 SOCKS5 слушает только `127.0.0.1:8083`
- Caddy слушает только `127.0.0.1:8443` (за telemt mask)
- `probe_resistance` в Caddy FP: без корректного auth-заголовка клиент получает обычный HTTP-ответ
- Caddy RP на nodeN использует `transport http { tls }` — трафик между нодами зашифрован
