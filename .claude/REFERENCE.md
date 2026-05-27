# REFERENCE.md — KawaProxy

---

## Ссылки и инструкции по установке

| Компонент | Репозиторий / Документация |
|---|---|
| telemt | https://github.com/telemt/telemt |
| telemt Quick Start RU | https://github.com/telemt/telemt/blob/main/docs/Quick_start/QUICK_START_GUIDE.ru.md |
| telemt Config Params RU | https://github.com/telemt/telemt/blob/main/docs/Config_params/CONFIG_PARAMS.ru.md |
| Caddy forwardproxy | https://github.com/caddyserver/forwardproxy |
| xcaddy | https://github.com/caddyserver/xcaddy |
| Telegram Bot API (Local Server) | https://github.com/tdlib/telegram-bot-api |
| .NET 10 Linux install | https://learn.microsoft.com/dotnet/core/install/linux-ubuntu |

---

## Задачи приложений

| Приложение | Задача |
|---|---|
| **telemt** | Слушает :443. Детектирует MTProto (префикс `ee`) и направляет напрямую в Telegram DC. Всё остальное TCP-splice → caddy :8443. `unknown_sni_action = "mask"` — неизвестный SNI уходит на caddy, не дропается. |
| **caddy forward-proxy** | HTTP CONNECT для клиентов. Прямой выход в интернет. |
| **caddy reverse-proxy** | Антисканерная защита. Трафик без валидного FP auth уходит на BACK_HOP: nodeN/nodeZ → предыдущая нода или nodeA, nodeA → localhost:8081. Клиент всегда видит легитимный сайт. |
| **.NET 10 minimal API** | Backend Part 1 на nodeA (:8081). Принимает веб-запросы от caddy RP. Всегда возвращает валидный ответ. Опциональный компонент (замена - стандартная страница-заглушка Caddy, ничего самописного)|
| **Telegram Local Server** | Локальный Bot API сервер на nodeA (:8082). Опциональный компонент. |

---