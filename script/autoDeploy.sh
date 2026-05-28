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
###		CHECK PARAMS
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


echo "[1/5] Hostname..."
hostnamectl set-hostname "$NODE_HOSTNAME"
grep -qF "127.0.1.1 $NODE_HOSTNAME" /etc/hosts \
  || echo "127.0.1.1 $NODE_HOSTNAME" >> /etc/hosts

echo "[2/5] IPv6..."
if [[ "$ENABLE_IPV6" == "0" ]]; then
  cat > /etc/sysctl.d/99-no-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
else
  rm -f /etc/sysctl.d/99-no-ipv6.conf
fi
sysctl --system

echo "[3/5] Packages..."
apt-get update -q
apt-get install -y --no-install-recommends \
  curl wget git ca-certificates gnupg ufw fail2ban openssl xxd \
  debian-keyring debian-archive-keyring apt-transport-https

echo "[4/5] ulimits..."
grep -qxF '* soft nofile 65535' /etc/security/limits.conf \
  || echo '* soft nofile 65535' >> /etc/security/limits.conf
grep -qxF '* hard nofile 65535' /etc/security/limits.conf \
  || echo '* hard nofile 65535' >> /etc/security/limits.conf

echo "[5/5] UFW + fail2ban..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled  = true
maxretry = $FAIL2BAN_MAXRETRY
findtime = $FAIL2BAN_FINDTIME
bantime  = $FAIL2BAN_BANTIME
EOF
systemctl enable fail2ban
systemctl restart fail2ban


###
###
##########################
##########################
##########################
###
###
###		SETUP telemt
###
###


echo "[telemt] Installing..."
curl -fsSL https://raw.githubusercontent.com/telemt/telemt/main/install.sh | sh
systemctl stop telemt


###
###
##########################
##########################
##########################
###
###
###		CONFIG telemt
###


echo "[telemt] Writing config..."

USERS_BLOCK=""
for cred in "${TELEMT_CREDS[@]}"; do
  _alias="${cred%%:*}"
  _secret="${cred##*:}"
  USERS_BLOCK+="${_alias} = \"${_secret}\""$'\n'
done

for (( i=1; i<=TELEMT_EXTRA; i++ )); do
  _alias="extra${i}"
  _secret="$(openssl rand -hex 16)"
  USERS_BLOCK+="${_alias} = \"${_secret}\""$'\n'
done

cat > /etc/telemt/telemt.toml <<EOF
[general]
use_middle_proxy = false

[general.modes]
classic = false
secure  = false
tls     = true

[general.links]
show        = "*"
public_host = "$NODE_DOMAIN"
public_port = 443

[server]
port = 443

[server.api]
enabled   = true
listen    = "127.0.0.1:9091"
whitelist = ["127.0.0.0/8"]

[censorship]
tls_domain         = "$NODE_DOMAIN"
unknown_sni_action = "mask"
mask               = true
mask_host          = "127.0.0.1"
mask_port          = 8443
tls_emulation      = true
tls_front_dir      = "/etc/telemt/tlsfront"

[access.users]
${USERS_BLOCK}
EOF

systemctl enable telemt
systemctl restart telemt


###
###
##########################
##########################
##########################
###
###
###		SETUP Telegram LS
###
###


if [[ "$INSTALL_TG" == "1" ]]; then

  echo "[telegram-bot-api] Installing build deps..."
  apt-get install -y cmake g++ make zlib1g-dev libssl-dev gperf

  echo "[telegram-bot-api] Cloning sources..."
  [[ ! -d /opt/tg-bot-api-src ]] && \
    git clone --recursive https://github.com/tdlib/telegram-bot-api.git /opt/tg-bot-api-src

  echo "[telegram-bot-api] Building..."
  cmake -DCMAKE_BUILD_TYPE=Release \
    -S /opt/tg-bot-api-src \
    -B /opt/tg-bot-api-src/build
  cmake --build /opt/tg-bot-api-src/build --target install

  mkdir -p /var/lib/telegram-bot-api
  chown nobody:nogroup /var/lib/telegram-bot-api

  cat > /etc/systemd/system/telegram-bot-api.service <<EOF
[Unit]
Description=Telegram Bot API Server
After=network.target

[Service]
User=nobody
WorkingDirectory=/var/lib/telegram-bot-api
ExecStart=/usr/local/bin/telegram-bot-api --local --http-port=8082 --api-id=${TG_API_ID} --api-hash=${TG_API_HASH}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable telegram-bot-api
  systemctl restart telegram-bot-api

fi


###
###
##########################
##########################
##########################
###
###
###		SETUP .NET 10
###
###


if [[ "$INSTALL_DOTNET" == "1" ]]; then

  echo "[dotnet] Installing .NET 10 SDK..."
  wget -O /tmp/packages-microsoft-prod.deb \
    https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb
  dpkg -i /tmp/packages-microsoft-prod.deb
  apt-get update
  apt-get install -y dotnet-sdk-10.0

fi


###
###
##########################
##########################
##########################
###
###
###     SETUP Caddy
###
###


echo "[caddy] Installing golang-go..."
apt-get install -y golang-go

echo "[caddy] Adding apt repository..."
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update
apt-get install -y caddy

systemctl stop caddy

echo "[caddy] Installing xcaddy..."
GOPATH=/root/go go install github.com/caddyserver/xcaddy/cmd/xcaddy@v0.4.5

echo "[caddy] Building with forwardproxy (2-5 min)..."
GOPATH=/root/go /root/go/bin/xcaddy build \
  --output /usr/bin/caddy \
  --with github.com/caddyserver/forwardproxy@caddy2

setcap cap_net_bind_service=+ep /usr/bin/caddy


###
###
##########################
##########################
##########################
###
###
###     CONFIG Caddy
###
###


echo "[caddy] Writing Caddyfile..."

FP_AUTH_BLOCK=""
for cred in "${FP_CREDS[@]}"; do
  _user="${cred%%:*}"
  _pass="${cred##*:}"
  FP_AUTH_BLOCK+="    basic_auth ${_user} ${_pass}"$'\n'
done

for (( i=1; i<=FP_EXTRA; i++ )); do
  _user="extra${i}"
  _pass="$(openssl rand -base64 12 | tr -d '=/+')"
  FP_AUTH_BLOCK+="    basic_auth ${_user} ${_pass}"$'\n'
done

if [[ "$INSTALL_DOTNET" == "1" ]]; then
  _handle="reverse_proxy localhost:8081"
elif [[ -n "$BACK_HOP" ]]; then
  _handle="reverse_proxy ${BACK_HOP}"
else
  _handle="file_server"
fi

cat > /etc/caddy/Caddyfile <<EOF
{
  http_port  80
  https_port 8443
  admin      off
  order forward_proxy before reverse_proxy
}

${NODE_DOMAIN} {
  forward_proxy {
${FP_AUTH_BLOCK}    probe_resistance ${NODE_DOMAIN}
    hide_ip
    hide_via
  }

  handle {
    ${_handle}
  }
}
EOF

systemctl enable caddy
systemctl restart caddy