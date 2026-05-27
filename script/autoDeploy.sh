#!/usr/bin/env bash
set -euo pipefail


##########################
##########################
###
###
###		USER PARAMS
###
###


# ── Переключатели ──────────────────────────────────────────────────────────────
# INSTALL_DOTNET  1 — установить .NET 10 backend (:8081); 0 — заглушка Caddy
# INSTALL_TG      1 — установить Telegram Local Server (:8082)
# ENABLE_IPV6     0 — отключить IPv6 через sysctl
INSTALL_DOTNET=0
INSTALL_TG=0
ENABLE_IPV6=0

# ── Идентификация ноды ─────────────────────────────────────────────────────────
# NODE_HOSTNAME  hostname сервера (hostnamectl)
# NODE_DOMAIN    полный домен ноды; LE-сертификат через Caddy ACME (:80)
NODE_HOSTNAME="my-node"
NODE_DOMAIN="node.example.com"

# ── Цепочка ────────────────────────────────────────────────────────────────────
# BACK_HOP  nodeA+DOTNET=1 → "localhost:8081" | nodeA без dotnet → "" | nodeN/Z → домен/IP предыдущей ноды
BACK_HOP=""

# ── Telegram Local Server ──────────────────────────────────────────────────────
# TG_API_ID    API ID приложения (требуется если INSTALL_TG=1)
# TG_API_HASH  API Hash приложения (требуется если INSTALL_TG=1)
TG_API_ID="00000000"
TG_API_HASH="00000000000000000000000000000000"

# ── fail2ban ───────────────────────────────────────────────────────────────────
# FAIL2BAN_MAXRETRY  максимум неудачных попыток до бана
# FAIL2BAN_FINDTIME  окно обнаружения, секунды
# FAIL2BAN_BANTIME   длительность бана (-1 = навсегда)
FAIL2BAN_MAXRETRY=15
FAIL2BAN_FINDTIME=300
FAIL2BAN_BANTIME=-1

# ── Кредентиалы ────────────────────────────────────────────────────────────────
# FP_CREDS      "user:pass" — генерация: openssl rand -base64 12 | tr -d '=/+'
# FP_EXTRA      количество дополнительных автогенерируемых FP-пользователей
# TELEMT_CREDS  "alias:32hex" — генерация: openssl rand -hex 16
# TELEMT_EXTRA  количество дополнительных автогенерируемых telemt-пользователей
FP_CREDS=(
  "username1:password1"
  "username2:password2"
)
FP_EXTRA=0

TELEMT_CREDS=(
  "alias1:00000000000000000000000000000001"
  "alias2:00000000000000000000000000000002"
)
TELEMT_EXTRA=0

###
###
##########################
##########################
##########################
###
###
###		USER PARAMS
###
###


[[ -z "$NODE_DOMAIN" ]] && { echo "[ERR] NODE_DOMAIN не заполнен"; exit 1; }

if [[ "$INSTALL_TG" == "1" ]]; then
  [[ -z "$TG_API_ID" ]]   && { echo "[ERR] INSTALL_TG=1 но TG_API_ID не заполнен";   exit 1; }
  [[ -z "$TG_API_HASH" ]] && { echo "[ERR] INSTALL_TG=1 но TG_API_HASH не заполнен"; exit 1; }
fi

for cred in "${TELEMT_CREDS[@]}"; do
  alias="${cred%%:*}"
  secret="${cred##*:}"
  [[ "$secret" =~ ^[0-9a-fA-F]{32}$ ]] || { echo "[ERR] Невалидный telemt secret: $alias"; exit 1; }
done

for cred in "${FP_CREDS[@]}"; do
  [[ "$cred" == *"REPLACE_ME"* ]] && { echo "[WARN] FP_CREDS содержит незаполненный пароль"; break; }
done

for cred in "${TELEMT_CREDS[@]}"; do
  [[ "$cred" == *"REPLACE_ME"* ]] && { echo "[WARN] TELEMT_CREDS содержит незаполненный secret"; break; }
done

echo "Будет настроено:"
echo "  [x] Base system  (hostname, ufw, fail2ban)"
echo "  [x] telemt"
echo "  [x] Caddy"
[[ "$INSTALL_DOTNET" == "1" ]] && echo "  [x] .NET 10 backend" || echo "  [ ] .NET 10 backend"
[[ "$INSTALL_TG"     == "1" ]] && echo "  [x] Telegram Local Server" || echo "  [ ] Telegram Local Server"


###
###
##########################
##########################
##########################
###
###
###		DEFAULT SETUP
###
###


