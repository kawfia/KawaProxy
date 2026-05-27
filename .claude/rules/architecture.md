# ARCHITECTURE — KawaProxy

---

## Роли нод

| Роль | Описание | Состав |
|---|---|---|
| **nodeA** | Первая нода. Единственная нода с реальным бэкендом | telemt · caddy · backend (Part 1) · Telegram Local Server (опц.) |
| **nodeN** | Промежуточная нода | telemt · caddy |
| **nodeZ** | Конечная нода | telemt · caddy |

> Минимальная цепочка — **1 нода (nodeA = nodeZ)**. BACK_HOP не задаётся.
> Каждая нода соединяется с Telegram DC **независимо и напрямую**.

---

## Переменные цепочки

| Переменная | Где задаётся | Значение |
|---|---|---|
| `BACK_HOP` | все ноды кроме nodeA | Адрес предыдущей ноды или nodeA напрямую |
| `BACK_HOP` | nodeA | `localhost:8081` (Part 1 бэкенда) |
| `FP_CHAIN` | все ноды | `0` = выход напрямую · `1` = HTTPS CONNECT цепочка |

---

## Схема трафика — порт :443

```
Входящее соединение :443
  │
  ├─ MTProto (префикс ee)
  │     └─ Telegram DC напрямую  (каждая нода независима)
  │
  └─ не MTProto → TCP-splice → caddy :8443
```

---

## Схема трафика — caddy :8443

```
caddy :8443
  │
  ├─ HTTP CONNECT + валидный Basic Auth → forward-proxy
  │     ├─ FP_CHAIN=0  → target напрямую с текущей ноды
  │     └─ FP_CHAIN=2  → HTTPS CONNECT → NEXT FP → ... → target
  │
  ├─ HTTP CONNECT без auth → probe_resistance
  │     └─ 200 OK + HTML (запрос падает в reverse-proxy, прокси не детектируется)
  │
  └─ GET / POST / HEAD (веб-запрос) → reverse_proxy BACK_HOP
        ├─ nodeN / nodeZ  → BACK_HOP = предыдущая нода или nodeA напрямую
        └─ nodeA          → BACK_HOP = localhost:8081 (Part 1)
```

---

## Бэкенд (nodeA)

Part 1 живёт на nodeA (:8081). Принимает сырой веб-запрос от caddy RP.
Всегда возвращает валидный ответ — Part 2 опциональна и управляется внутри Part 1.

```
caddy RP (nodeA) → localhost:8081 → Part 1  →  ответ клиенту
                                      └──→  Part 2 (опционально, internal)
```

- Part 1 видит **реальный IP клиента** через `X-Forwarded-For`
- Бэкенд упал → **500** клиенту через всю цепочку
- Редирект (301/302) → **пробрасывается клиенту как есть** (caddy RP не следует)

---

## Что видит бот/сканер

```
Бот → nodeZ:443
  telemt: нет ee → caddy RP → BACK_HOP (nodeN или nodeA):443
    ... → caddy RP (nodeA) → localhost:8081
      Part 1 → веб-ответ

Бот видит: обычный веб-сайт.
CONNECT без auth → 200 OK + тот же сайт (probe_resistance).
Признаков прокси нет.
```

**Host-заголовок:** оригинальный (домен ноды, с которой пришёл запрос) сохраняется через всю цепочку. Part 1 видит домен входной ноды.

---

## Таблица портов

| Порт | Сервис | nodeA | nodeN | nodeZ | Публичный |
|---|---|---|---|---|---|
| `:80` | Caddy ACME | ✅ | ✅ | ✅ | ✅ |
| `:443` | telemt | ✅ | ✅ | ✅ | ✅ |
| `:8081` | backend Part 1 (internal) | ✅ | ❌ | ❌ | ❌ |
| `:8082` | Telegram Local Server (опц.) | ✅ | ❌ | ❌ | ❌ |
| `:8443` | caddy HTTPS (FP + RP) | ✅ | ✅ | ✅ | ❌ |
| `:9091` | telemt API (internal) | ✅ | ✅ | ✅ | ❌ |

---

## Мультинод

- Каждая нода — **свой домен**, свой LE-сертификат (caddy ACME через :80)
- Порядок деплоя **не важен** — BACK_HOP обрабатывает запрос как обычный REST
- nodeN/Z может смотреть BACK_HOP как на предыдущую ноду, так и напрямую на nodeA

---

## Антидетект

- `probe_resistance` — CONNECT без auth получает 200+HTML (сайт), не 407
- `mask=true`, `tls_emulation=true` в telemt — маскирует под обычный TLS-сервер
- `unknown_sni_action=mask` — неизвестный SNI уходит на caddy, не дропается
- Caddy получает LE для каждой ноды.
- telemt - транслирует сырой запрос без обработки к Caddy:8443
- Приневалидном секрете (к telemt) сырой запрос уходит в Caddy:8443

---
