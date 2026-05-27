# [5] Настройка telemt

## Задача
Записать `/etc/telemt/telemt.toml` и запустить сервис.

## Цель
Настроить telemt на приём MTProto (:443), детекцию по ee-префиксу и проброс остального трафика в Caddy (:8443).

## Обоснование
`mask=true` + `tls_emulation=true` + `unknown_sni_action=mask` обеспечивают антидетект — сервер выглядит как обычный TLS-сайт.

## Ссылки
- [Config Params RU](https://github.com/telemt/telemt/blob/main/docs/Config_params/CONFIG_PARAMS.ru.md)

## Детали

> **ВАЖНО:** Имя файла — `telemt.toml`. Использование `config.toml` — частая ошибка (см. `common-mistakes.md`).

### Путь
`/etc/telemt/telemt.toml`

### Секция `[general]`
| Параметр | Значение |
|---|---|
| `use_middle_proxy` | `false` |

### Секция `[general.modes]`
| Параметр | Значение |
|---|---|
| `classic` | `false` |
| `secure` | `false` |
| `tls` | `true` |

### Секция `[general.links]`
| Параметр | Значение |
|---|---|
| `show` | `"*"` |
| `public_host` | `$NODE_DOMAIN` |
| `public_port` | `443` |

### Секция `[server]`
| Параметр | Значение |
|---|---|
| `port` | `443` |

### Секция `[server.api]`
| Параметр | Значение |
|---|---|
| `enabled` | `true` |
| `listen` | `"127.0.0.1:9091"` |
| `whitelist` | `["127.0.0.0/8"]` |

### Секция `[censorship]`
| Параметр | Значение |
|---|---|
| `tls_domain` | `$NODE_DOMAIN` |
| `unknown_sni_action` | `"mask"` |
| `mask` | `true` |
| `mask_host` | `"127.0.0.1"` |
| `mask_port` | `8443` |
| `tls_emulation` | `true` |
| `tls_front_dir` | `"/etc/telemt/tlsfront"` |

### Секция `[access.users]`
Формат: `alias = "32hexsecret"`

Пример записи MTProto-ссылки:
```
tg://proxy?server=NODE_DOMAIN&port=443&secret=ee<32hex><NODE_DOMAIN_HEX>
```

### Генерация hex-домена для ссылки
```bash
printf '%s' "$NODE_DOMAIN" | xxd -p -c 1000
```
