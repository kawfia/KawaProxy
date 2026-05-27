# ARCHITECTURE v2 — KawaProxy

## Легенда

### Клиент

Доверенный хост, которому выдаются креды и DNS-адреса для использования сети.

- Подключается по MTProto или HTTP forward-proxy к **любой** ноде цепочки
- Видит соединение как будто между ним и целью **всегда один сервер**
- Никогда не меняет учётные данные при смене ноды — меняется только DNS-адрес

### Роли нод

| Роль | Описание | Программный состав |
|---|---|---|
| **nodeA** | Первая (ближайшая к клиенту) нода | telemt · caddy (RP + FP) · .NET 10 minimal API · Telegram Local Server |
| **nodeN** | Любая промежуточная нода | telemt · caddy (RP + FP) |
| **nodeZ** | Конечная нода (ближайшая к цели) | telemt · caddy (RP + FP) |

> nodeA может быть одновременно nodeZ: один сервер способен форвардить MTProto
> напрямую в Telegram DC, минуя какие-либо промежуточные ноды.
> Минимальная цепочка — **1 нода (nodeA = nodeZ)**.

---

## Схема трафика

### telemt — входная точка (порт :443)

```
Входящее TLS-соединение :443
  │
  ├─ MTProto (префикс ee)  ──────────────────────────────────────────────┐
  │                                                                      │
  └─ не MTProto (TLS, HTTPS, сканер) → TCP-splice → caddy :8443          │
                                                                         │
              ┌──────────────────────────────────────────────────────────┘
              │  nodeA / nodeN
              ▼
        SOCKS5 127.0.0.1:8083  (caddy-l4, internal)
              → следующая нода (NEXT_HOP):443
              │
              │  nodeZ (или nodeA без NEXT_HOP)
              ▼
        Telegram DC напрямую
```

### Caddy — обработка не-MTProto трафика (порт :8443, internal)

```
caddy :8443
  │
  ├─ HTTP CONNECT (forward-proxy с аутентификацией)
  │       │
  │       ├─ FP_CHAIN=0  прямой выход с текущей ноды → target
  │       ├─ FP_CHAIN=1  SOCKS5 127.0.0.1:8083 → NEXT_HOP → ... → nodeZ → target  (цепочка скрыта)
  │       └─ FP_CHAIN=2  HTTPS CONNECT → NEXT_HOP FP → ... → nodeZ → target  (цепочка видна)
  │
  └─ всё остальное (GET/POST, сканеры без auth) → reverse-proxy
          │
          ├─ nodeA  → localhost:8081  (.NET 10 minimal API)
          └─ nodeN / nodeZ  → предыдущая нода в цепочке (BACK_HOP)
```

---

## Цепочка для клиента

### MTProto (Telegram)

```
Клиент
  → nodeA:443  (telemt, ee-prefix)
    → SOCKS5:8083 → caddy-l4 → nodeN:443
      → SOCKS5:8083 → caddy-l4 → nodeZ:443
        → telemt → Telegram DC
```

Клиент видит один адрес (nodeA). Секрет MTProto не меняется никогда.

### HTTP forward-proxy — режим "прямой выход" (FP_CHAIN=0)

```
Клиент → HTTP CONNECT → nodeA/nodeN/nodeZ:443
  → caddy FP → target (выход с текущей ноды)
```

### HTTP forward-proxy — режим "выход через nodeZ" (FP_CHAIN=1)

```
Клиент → HTTP CONNECT → nodeA:443
  → caddy FP → SOCKS5:8083 → nodeN:443
    → caddy FP → SOCKS5:8083 → nodeZ:443
      → caddy FP → target (цепочка скрыта)
```

### HTTP forward-proxy — режим "выход через nodeZ" (FP_CHAIN=2)

```
Клиент → HTTP CONNECT → nodeA:443
  → caddy FP (upstream = nodeN FP)
    → caddy FP (upstream = nodeZ FP)
      → caddy FP → target (цепочка видна как proxy-to-proxy)
```

Режим выхода задаётся один раз при установке ноды.

---

## Цепочка для бота/сканера (антисканерная защита)

Бот подключается к ноде без MTProto и без валидных кредов forward-proxy.

```
Бот → nodeZ:443
  telemt: нет префикса ee
    → TCP-splice → caddy RP:8443
      caddy RP (nodeZ) → предыдущая нода (nodeN):443
        telemt nodeN: снова нет ee
          → caddy RP (nodeN) → предыдущая нода (nodeA):443
            caddy RP (nodeA) → localhost:8081
              .NET 10 minimal API → обычная HTML-страница

Бот видит: легитимная веб-инфраструктура, без признаков прокси
```

Схема "бот → первая нода":

```
Бот → nodeA:443
  telemt: нет ee
    → caddy RP:8443
      → localhost:8081
        → .NET 10 → HTML-страница
```

---

## Минимальная конфигурация (1 нода, nodeA = nodeZ)

```
Клиент
  → nodeA:443 (telemt)
    ├─ MTProto → Telegram DC напрямую  (NEXT_HOP не задан)
    └─ HTTPS   → caddy:8443
        ├─ HTTP CONNECT → caddy FP → target
        └─ reverse-proxy → localhost:8081 (.NET 10)

Бот → nodeA:443 → caddy RP → .NET 10 → HTML
```

---

## Таблица портов

| Порт | Сервис | nodeA | nodeN | nodeZ | Публичный |
|---|---|---|---|---|---|
| `:80` | Caddy — ACME / LE | ✅ | ✅ | ✅ | ✅ |
| `:443` | telemt — MTProto + TLS mask | ✅ | ✅ | ✅ | ✅ |
| `:8081` | .NET 10 minimal API | ✅ | ❌ | ❌ | ❌ |
| `:8082` | Telegram Local Server | ✅ | ❌ | ❌ | ❌ |
| `:8083` | caddy-l4 SOCKS5 (telemt upstream) | ✅ | ✅ | ✅ | ❌ |
| `:8443` | Caddy HTTPS (FP + RP) | ✅ | ✅ | ✅ | ❌ |
| `:9091` | telemt API (internal) | ✅ | ✅ | ✅ | ❌ |

---

## Конфигурационные шаблоны

### telemt — telemt.toml

> Официальный путь: `/etc/telemt/telemt.toml`

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
enabled   = true
listen    = "127.0.0.1:9091"
whitelist = ["127.0.0.0/8"]

[censorship]
tls_domain         = "TELEMT_TLS_DOMAIN"
mask               = true
mask_host          = "127.0.0.1"
mask_port          = 8443
tls_emulation      = true
tls_front_dir      = "/etc/telemt/tlsfront"
unknown_sni_action = "mask"   # направить неизвестный SNI на caddy вместо дропа

# --- только для nodeA / nodeN (NEXT_HOP задан) ---
[upstream]
type = "socks5"

[upstream.socks5]
host     = "127.0.0.1"
port     = 8083
username = "SOCKS5_USER"
password = "SOCKS5_PASS"
# --- конец блока ---

[access.users]
USER_ALIAS = "32_HEX_SECRET"   # openssl rand -hex 16
```

### Caddy — Caddyfile (nodeA)

SOCKS5 для caddy-l4 задаётся прямо в глобальном блоке Caddyfile — отдельный JSON-конфиг не нужен.

```caddyfile
{
    http_port  80
    https_port 8443
    admin      off
    order forward_proxy before reverse_proxy

    layer4 {
        127.0.0.1:8083 {
            route {
                socks5 {
                    commands CONNECT ASSOCIATE
                    credentials SOCKS5_USER SOCKS5_PASS
                }
            }
        }
    }
}

NODE_DOMAIN {
    header -Server
    header -X-Powered-By

    forward_proxy {
        basic_auth FP_USER FP_PASS
        probe_resistance
        hide_ip
        hide_via
        # FP_CHAIN=1: upstream socks5://127.0.0.1:8083
        # FP_CHAIN=2: upstream https://FP_CHAIN_USER:FP_CHAIN_PASS@NEXT_HOP:443
    }

    handle {
        reverse_proxy localhost:8081
    }
}
```

### Caddy — Caddyfile (nodeN / nodeZ)

```caddyfile
{
    http_port  80
    https_port 8443
    admin      off
    order forward_proxy before reverse_proxy

    layer4 {
        127.0.0.1:8083 {
            route {
                socks5 {
                    commands CONNECT ASSOCIATE
                    credentials SOCKS5_USER SOCKS5_PASS
                }
            }
        }
    }
}

NODE_DOMAIN {
    header -Server
    header -X-Powered-By

    forward_proxy {
        basic_auth FP_USER FP_PASS
        probe_resistance
        hide_ip
        hide_via
        # FP_CHAIN=1: upstream socks5://127.0.0.1:8083
        # FP_CHAIN=2: upstream https://FP_CHAIN_USER:FP_CHAIN_PASS@NEXT_HOP:443
    }

    handle {
        # reverse_proxy → ПРЕДЫДУЩАЯ нода (антисканер)
        reverse_proxy BACK_HOP:443 {
            transport http { tls }
        }
    }
}
```

---

## Полная схема (3 ноды: nodeA → nodeN → nodeZ)

```
[Клиент]
    │  TLS :443
    ▼
╔══════════════════════╗
║  наблюдатель A       ║  видит: TLS 1.3, SNI = tls_domain
╚══════════════════════╝
    │
    ▼
┌────────────────────────────────────────────┐
│  nodeA                                     │
│                                            │
│  :443  telemt                              │
│    ├─ MTProto → :8083 SOCKS5 → nodeN:443  │
│    └─ HTTPS   → :8443 caddy               │
│        ├─ CONNECT → FP (→ target или chain)│
│        └─ else   → RP → localhost:8081    │
│                                            │
│  :8081  .NET 10 minimal API               │
│  :8082  Telegram Local Server             │
└─────────────────────┬──────────────────────┘
                      │  TLS :443
╔═════════════════════╪════════════════════╗
║  наблюдатель B      │                   ║
╚═════════════════════╪════════════════════╝
                      │
                      ▼
┌────────────────────────────────────────────┐
│  nodeN                                     │
│                                            │
│  :443  telemt                              │
│    ├─ MTProto → :8083 SOCKS5 → nodeZ:443  │
│    └─ HTTPS   → :8443 caddy               │
│        ├─ CONNECT → FP (→ target или chain)│
│        └─ else (сканер) → RP → nodeA:443  │
└─────────────────────┬──────────────────────┘
                      │  TLS :443
╔═════════════════════╪════════════════════╗
║  наблюдатель C      │                   ║
╚═════════════════════╪════════════════════╝
                      │
                      ▼
┌────────────────────────────────────────────┐
│  nodeZ                                     │
│                                            │
│  :443  telemt                              │
│    ├─ MTProto → Telegram DC напрямую      │
│    └─ HTTPS   → :8443 caddy               │
│        ├─ CONNECT → FP → target           │
│        └─ else (сканер) → RP → nodeN:443  │
└────────────────────────────────────────────┘
                      │
                      ▼
               [Telegram DC / target]
```

---

## Почему SOCKS5

telemt нативно не поддерживает форвардинг MTProto на другой telemt-инстанс.
Решение: telemt отдаёт MTProto-поток в `upstream` типа SOCKS5 → `127.0.0.1:8083`,
caddy-l4 принимает соединение и устанавливает исходящий TCP до `NEXT_HOP:443`.
Зашифрованный MTProto-поток передаётся без расшифровки на промежуточных нодах.
SOCKS5 слушает только на `127.0.0.1` — не виден снаружи.

SOCKS5 в caddy-l4 конфигурируется через блок `layer4 {}` в глобальных опциях Caddyfile —
отдельный JSON API-конфиг (`l4.json`) не требуется.

---

## Смена ноды без изменений у клиента

1. Новая нода разворачивается с тем же `NODE_DOMAIN` (или новым)
2. Клиенту передаётся новый DNS-адрес
3. Секреты MTProto и форвард-прокси не меняются
4. Ссылка MTProto пересобирается только при смене домена: `ee{secret}{domain_hex}`
