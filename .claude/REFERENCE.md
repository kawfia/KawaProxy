# REFERENCE.md — KawaProxy

---

## Ссылки и инструкции по установке

| Компонент | Репозиторий / Документация |
|---|---|
| telemt | https://github.com/telemt/telemt |
| telemt Quick Start RU | https://github.com/telemt/telemt/blob/main/docs/QUICK_START_GUIDE.ru.md |
| telemt Double Hop RU | https://github.com/telemt/telemt/blob/main/docs/VPS_DOUBLE_HOP.ru.md |
| telemt Config Params RU | https://github.com/telemt/telemt/blob/main/docs/Config_params/CONFIG_PARAMS.ru.md |
| Caddy forwardproxy | https://github.com/caddyserver/forwardproxy |
| caddy-l4 | https://github.com/mholt/caddy-l4 |
| xcaddy | https://github.com/caddyserver/xcaddy |
| Telegram Bot API (Local Server) | https://github.com/tdlib/telegram-bot-api |
| .NET 10 Linux install | https://learn.microsoft.com/dotnet/core/install/linux-ubuntu |

---

## Задачи приложений

| Приложение | Задача |
|---|---|
| **telemt** | Слушает :443. Пропускает MTProto (префикс `ee`) вперёд по цепочке или напрямую в Telegram DC. Всё остальное TCP-splice → caddy :8443. |
| **caddy forward-proxy** | HTTP CONNECT для клиентов. Выход — с текущей ноды или через nodeZ (задаётся при установке). |
| **caddy reverse-proxy** | Антисканерная защита. Отдаёт трафик без валидного auth обратно: nodeA → .NET 10, nodeN/nodeZ → предыдущая нода. |
| **caddy-l4 SOCKS5** | Внутренний транспорт (:8083, только 127.0.0.1). Принимает MTProto от telemt и отправляет на NEXT_HOP:443. |
| **.NET 10 minimal API** | Backend на nodeA. Отдаёт легитимный ответ сканерам через caddy RP. |
| **Telegram Local Server** | Локальный Bot API сервер на nodeA (:8082). |

---

## Переменные — nodeA

```sh
# --- переключатели ---
# 0 = стандартная HTML-страница Caddy  |  1 = установить .NET 10
INSTALL_DOTNET=0

# 0 = не устанавливать  |  1 = установить (требует TG_API_ID и TG_API_HASH)
INSTALL_TG=0

# 0 = отключить IPv6  |  1 = оставить включённым
ENABLE_IPV6=0

# пусто = nodeA является nodeZ (MTProto → Telegram DC напрямую)
# задан = nodeA форвардит MTProto дальше по цепочке
NEXT_HOP=""

# forward-proxy режим выхода:
# 0 = с текущей ноды напрямую
# 1 = SOCKS5 → NEXT_HOP → ... → nodeZ  (цепочка скрыта за SOCKS5)
# 2 = HTTPS CONNECT → NEXT_HOP FP напрямую  (цепочка видна как proxy-to-proxy)
FP_CHAIN=0

# --- идентификация ---
NODE_HOSTNAME=""
NODE_DOMAIN=""

# --- Telegram Local Server (заполнить если INSTALL_TG=1) ---
TG_API_ID=""
TG_API_HASH=""

# --- fail2ban ---
FAIL2BAN_MAXRETRY=15
FAIL2BAN_FINDTIME=300
FAIL2BAN_BANTIME=-1       # -1 = бан навсегда

# --- forward-proxy ---
FP_CREDS=(
  "httpproxy_user1:PASSWORD"
  "httpproxy_user2:PASSWORD"
)
FP_EXTRA=0
# FP_CHAIN=2: кредентиалы FP следующей ноды
FP_CHAIN_UPSTREAM_USER=""
FP_CHAIN_UPSTREAM_PASS=""

# --- SOCKS5 (внутренний транспорт telemt) ---
SOCKS5_CREDS=(
  "socks5_service1:PASSWORD"
  "socks5_service2:PASSWORD"
)

# --- telemt ---
TELEMT_CREDS=(
  "telemt_user1:32_HEX_SECRET"
  "telemt_user2:32_HEX_SECRET"
)
TELEMT_EXTRA=0
```

---

## Переменные — nodeN

```sh
# --- идентификация ---
NODE_HOSTNAME=""          # hostname сервера
NODE_DOMAIN=""            # публичный FQDN (на него выписывается LE-сертификат)

# --- роль ноды ---
# пусто = нода является nodeZ (выход напрямую в Telegram DC)
# задан = нода форвардит MTProto дальше по цепочке
NEXT_HOP=""

# --- предыдущая нода (для caddy reverse-proxy антисканер) ---
# всегда задан: сканер уходит на предыдущую ноду → ... → nodeA → .NET 10
BACK_HOP=""

# --- forward-proxy режим выхода ---
# 0 = выход с текущей ноды  |  1 = выход через nodeZ (конец цепочки)
FP_CHAIN=0

# --- кредентиалы ---
FP_CREDS=(
  "httpproxy_user1:PASSWORD"
  "httpproxy_user2:PASSWORD"
)
FP_EXTRA=0

SOCKS5_CREDS=(
  "socks5_service1:PASSWORD"
  "socks5_service2:PASSWORD"
)

TELEMT_CREDS=(
  "telemt_user1:32_HEX_SECRET"
  "telemt_user2:32_HEX_SECRET"
)
TELEMT_EXTRA=0

# --- fail2ban ---
FAIL2BAN_MAXRETRY=15
FAIL2BAN_FINDTIME=300
FAIL2BAN_BANTIME=-1

# --- сеть ---
ENABLE_IPV6=0
```
