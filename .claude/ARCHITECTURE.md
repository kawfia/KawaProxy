# ARCHITECTURE.md — KawaProxy

## Концепция

Цепочка Ubuntu-нод (Ubuntu 24.04), где каждая нода технически идентична по ПО.
Роль ноды определяется только конфигурационной переменной `NEXT_HOP`:

- **`NEXT_HOP=""`** → **node0** (exit): MTProto уходит на Telegram DC, REST — на backend `:8081`
- **`NEXT_HOP="host:443"`** → **nodeN** (chain): весь трафик пробрасывается на следующую ноду

Клиент может подключиться к любой ноде в цепочке — цепочка просто станет короче.

---

## Схема трафика на каждой ноде

```
client
  │  TLS 1.3 :443
  ▼
telemt  (ee mode — TLS-fronting, неотличим от HTTPS)
  │
  ├─ MTProto-пакет
  │       └─→  SOCKS5 127.0.0.1:8083  (caddy-l4, internal)
  │                     │
  │                     ├─ nodeN: → NEXT_HOP:443  (следующий telemt)
  │                     └─ node0: → Telegram DC напрямую
  │
  └─ non-MTProto TLS  (TCP-splice, TLS не терминируется telemt)
          └─→  127.0.0.1:8443  [Caddy]
                    │  (Caddy сам терминирует TLS, LE-сертификат)
                    │
                    ├─ HTTP CONNECT  →  caddy FP (forward proxy)
                    │                    ├─ nodeN: upstream = NEXT_HOP:443
                    │                    └─ node0: upstream = открытый интернет
                    │
                    └─ GET / POST    →  caddy RP (reverse proxy)
                                         ├─ nodeN: NEXT_HOP:443
                                         └─ node0: localhost:8081 (backend)
```

---

## Почему один порт :443

- Клиент всегда подключается только к `:443`
- telemt мультиплексирует: MTProto → SOCKS5, всё остальное → TCP-splice на Caddy `:8443`
- Снаружи всё выглядит как TLS 1.3 (SNI = `tls_domain` из конфига telemt)
- UFW открывает только `:22`, `:80`, `:443`

---

## Почему MTProto chaining через SOCKS5

telemt нативно не поддерживает пересылку MTProto на другой telemt.  
Официальный double-hop требует HAProxy + AmneziaWG — избыточно.

Наш подход:
```
telemt [upstream] type = "socks5"  →  127.0.0.1:8083
caddy-l4 SOCKS5 :8083  →  NEXT_HOP:443
```

caddy-l4 на `:8083` слушает только на `127.0.0.1` — снаружи не доступен.

---

## Таблица портов

| Порт | Сервис | Все ноды | Только node0 | Снаружи |
|---|---|---|---|---|
| `:80` | Caddy — ACME / LE cert | ✅ | | ✅ |
| `:443` | telemt — MTProto + TLS mask | ✅ | | ✅ |
| `:8081` | backend (.NET 10) | | ✅ | ❌ |
| `:8082` | Telegram Local Server | | ✅ | ❌ |
| `:8083` | caddy-l4 SOCKS5 (telemt upstream) | ✅ | | ❌ |
| `:8443` | Caddy HTTPS (FP + RP) | ✅ | | ❌ |
| `:9091` | telemt API | ✅ | | ❌ |

---

## Конфигурационные шаблоны

### telemt — config.toml

```toml
[general]
use_middle_proxy = false

[general.modes]
classic = false
secure  = false
tls     = true

[general.links]
show        = "*"
public_host = "NODE_DOMAIN"
public_port = 443

[server]
port = 443

[server.api]
enabled  = true
listen   = "127.0.0.1:9091"
whitelist = ["127.0.0.0/8"]

[censorship]
tls_domain    = "TELEMT_TLS_DOMAIN"   # SNI-домен для TLS-fronting
mask          = true
mask_host     = "127.0.0.1"
mask_port     = 8443                   # non-MTProto → Caddy
tls_emulation = true
tls_front_dir = "/etc/telemt/tlsfront"

# --- только для nodeN (NEXT_HOP != "") ---
[upstream]
type = "socks5"

[upstream.socks5]
host     = "127.0.0.1"
port     = 8083
username = "SOCKS5_USER"
password = "SOCKS5_PASS"
# --- конец блока nodeN ---

[access.users]
# ключ — 32 hex символа (openssl rand -hex 16 или SHA256(name)[:32])
USER_ALIAS = "32_HEX_SECRET"
```

### Caddy — Caddyfile (nodeN)

```caddyfile
{
    http_port  80
    https_port 8443
    admin      off
}

NODE_DOMAIN {
    forward_proxy {
        basicauth FP_USER1 FP_PASS1
        basicauth FP_USER2 FP_PASS2
        probe_resistance         # без auth выглядит как обычный сайт
    }
    reverse_proxy NEXT_HOP:443 {
        transport http { tls }
    }
}
```

### Caddy — Caddyfile (node0)

```caddyfile
{
    http_port  80
    https_port 8443
    admin      off
}

NODE_DOMAIN {
    forward_proxy {
        basicauth FP_USER1 FP_PASS1
        probe_resistance
    }
    reverse_proxy localhost:8081
}
```

### caddy-l4 — SOCKS5 config (все ноды, :8083, internal)

```json
{
  "apps": {
    "layer4": {
      "servers": {
        "socks5": {
          "listen": ["127.0.0.1:8083"],
          "routes": [{
            "handle": [{
              "handler": "socks5",
              "credentials": {
                "SOCKS5_USER": "SOCKS5_PASS"
              }
            }]
          }]
        }
      }
    }
  }
}
```

---

## Цепочка из двух нод (пример)

```
[client / MS SQL]
      │  HTTPS :443
      ▼
╔════════════════════╗
║  observer A        ║  видит: TLS 1.3 :443, SNI = tls_domain
╚════════════════════╝
      │
      ▼
┌──────────────────────────────────┐
│  nodeN                           │
│                                  │
│  :443  telemt                    │
│    ├─ MTProto  → :8083 SOCKS5    │
│    └─ HTTPS   → :8443 Caddy      │
│         ├─ CONNECT → caddy FP    │
│         └─ REST    → caddy RP    │
│              → NEXT_HOP:443      │
└─────────────────┬────────────────┘
                  │  HTTPS :443
╔═════════════════╪══════════════╗
║  observer B     │              ║
╚═════════════════╪══════════════╝
                  │
                  ▼
┌──────────────────────────────────┐
│  node0                           │
│                                  │
│  :443  telemt                    │
│    ├─ MTProto  → Telegram DC     │
│    └─ HTTPS   → :8443 Caddy      │
│         ├─ CONNECT → caddy FP    │
│         └─ REST    → :8081 .NET  │
│                                  │
│  :8081  backend (.NET 10)        │
│  :8082  Telegram Local Server    │
└──────────────────────────────────┘
```

---

## Сборка Caddy (xcaddy)

Caddy собирается через `xcaddy` с двумя плагинами:

```sh
xcaddy build \
  --with github.com/caddyserver/forwardproxy \
  --with github.com/mholt/caddy-l4
```

Стандартный `apt install caddy` не содержит этих плагинов.  
Сборка происходит в `services/caddy/build.sh`.

---

## LE-сертификат

Caddy автоматически получает сертификат от Let's Encrypt через ACME HTTP-01 challenge на `:80`.  
telemt не терминирует TLS — он делает TCP-splice на Caddy `:8443`, Caddy сам держит LE-сертификат.

---

## Смена ноды без изменений у клиента

1. Новая нода разворачивается с тем же `NODE_DOMAIN`
2. DNS-запись обновляется на IP новой ноды
3. Клиент автоматически переходит на новую ноду
4. Старая нода выводится из эксплуатации
