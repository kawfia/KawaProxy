#!/usr/bin/env bash
set -uo pipefail

[[ $EUID -ne 0 ]] && { echo "Run as root"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# [ПЕРЕКЛЮЧАТЕЛИ]
# ─────────────────────────────────────────────────────────────────────────────

# 0 = сервировать стандартную HTML-страницу  |  1 = установить .NET 10
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

# ─────────────────────────────────────────────────────────────────────────────
# [ИДЕНТИФИКАЦИЯ]
# ─────────────────────────────────────────────────────────────────────────────
NODE_HOSTNAME="nodeA"
# полный домен; на него выписывается LE-сертификат
NODE_DOMAIN="example.com"

# ─────────────────────────────────────────────────────────────────────────────
# [TELEGRAM LOCAL SERVER]  — заполнить если INSTALL_TG=1
# ─────────────────────────────────────────────────────────────────────────────
TG_API_ID=""
TG_API_HASH=""

# ─────────────────────────────────────────────────────────────────────────────
# [FAIL2BAN]
# ─────────────────────────────────────────────────────────────────────────────
FAIL2BAN_MAXRETRY=15
FAIL2BAN_FINDTIME=300
FAIL2BAN_BANTIME=-1       # -1 = бан навсегда

# ─────────────────────────────────────────────────────────────────────────────
# [STATIC] — предгенерированные кредентиалы
# ─────────────────────────────────────────────────────────────────────────────

# forward-proxy: openssl rand -base64 12 | tr -d '=/+'
FP_CREDS=(
  "httpproxy_service1:REPLACE_ME"
  "httpproxy_service2:REPLACE_ME"
  "httpproxy_user1:REPLACE_ME"
  "httpproxy_user2:REPLACE_ME"
)
FP_EXTRA=0

# FP_CHAIN=2: кредентиалы FP следующей ноды (NEXT_HOP)
FP_CHAIN_UPSTREAM_USER="REPLACE_ME"
FP_CHAIN_UPSTREAM_PASS="REPLACE_ME"

# SOCKS5 (внутренний транспорт telemt): openssl rand -base64 12 | tr -d '=/+'
SOCKS5_CREDS=(
  "socks5_service1:REPLACE_ME"
  "socks5_service2:REPLACE_ME"
  "socks5_user1:REPLACE_ME"
  "socks5_user2:REPLACE_ME"
)

# telemt: openssl rand -hex 16  (ровно 32 hex символа)
TELEMT_CREDS=(
  "telemt_user1:REPLACE_ME_32_HEX"
  "telemt_user2:REPLACE_ME_32_HEX"
  "telemt_user3:REPLACE_ME_32_HEX"
  "telemt_user4:REPLACE_ME_32_HEX"
)
TELEMT_EXTRA=0

# ─────────────────────────────────────────────────────────────────────────────
# [DERIVED]
# ─────────────────────────────────────────────────────────────────────────────
TELEMT_TLS_DOMAIN="${NODE_DOMAIN}"

# ─────────────────────────────────────────────────────────────────────────────
# [VALIDATION]
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${INSTALL_TG}" -eq 1 && ( -z "${TG_API_ID}" || -z "${TG_API_HASH}" ) ]]; then
  echo "[ERR] INSTALL_TG=1 но TG_API_ID или TG_API_HASH не заполнены"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# [DYNAMIC] — доп. кредентиалы
# ─────────────────────────────────────────────────────────────────────────────
_rand()  { openssl rand -base64 12 | tr -d '=/+'; }
_hex32() { openssl rand -hex 16; }

for i in $(seq 1 "${FP_EXTRA}"); do
  FP_CREDS+=("fp_extra${i}:$(_rand)")
done
for i in $(seq 1 "${TELEMT_EXTRA}"); do
  TELEMT_CREDS+=("telemt_extra${i}:$(_hex32)")
done

# ─────────────────────────────────────────────────────────────────────────────
# Логгирование
# ─────────────────────────────────────────────────────────────────────────────
LOG_FILE="/var/log/kawaproxy_nodeA.log"
mkdir -p "$(dirname "${LOG_FILE}")"
exec > >(tee -a "${LOG_FILE}") 2>&1

log() { echo "[$(date '+%H:%M:%S')] $*"; }
ok()  { echo "  [OK]  $1"; }
die() { echo "  [ERR] $1"; exit 1; }
chk() { local rc=$?; [[ $rc -eq 0 ]] && ok "$1" || die "$1 (exit ${rc})"; }

log "=== KawaProxy nodeA ==="
log "hostname=${NODE_HOSTNAME}  domain=${NODE_DOMAIN}  next_hop=${NEXT_HOP:-exit}"
log "fp_chain=${FP_CHAIN}  install_dotnet=${INSTALL_DOTNET}  install_tg=${INSTALL_TG}"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Система
# ─────────────────────────────────────────────────────────────────────────────
log "--- [1/5] system ---"

hostnamectl set-hostname "${NODE_HOSTNAME}"
chk "hostname"

grep -q "${NODE_HOSTNAME}" /etc/hosts || echo "127.0.1.1 ${NODE_HOSTNAME}" >> /etc/hosts
ok "hosts"

if [[ "${ENABLE_IPV6}" -eq 0 ]]; then
  cat > /etc/sysctl.d/99-no-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6     = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6      = 1
EOF
  sysctl --system -q
  ok "ipv6 disabled"
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  curl wget git ca-certificates gnupg \
  ufw fail2ban openssl xxd \
  debian-keyring debian-archive-keyring apt-transport-https
chk "apt base packages"

cat >> /etc/security/limits.conf <<'EOF'
* soft nofile 65535
* hard nofile 65535
EOF
ok "ulimits"

# ─────────────────────────────────────────────────────────────────────────────
# 2. UFW
# ─────────────────────────────────────────────────────────────────────────────
log "--- [2/5] ufw ---"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
chk "ufw"

# ─────────────────────────────────────────────────────────────────────────────
# 3. fail2ban
# ─────────────────────────────────────────────────────────────────────────────
log "--- [3/5] fail2ban ---"

cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled  = true
maxretry = ${FAIL2BAN_MAXRETRY}
findtime = ${FAIL2BAN_FINDTIME}
bantime  = ${FAIL2BAN_BANTIME}
EOF

systemctl enable fail2ban --now
chk "fail2ban"

# ─────────────────────────────────────────────────────────────────────────────
# 4. Caddy (xcaddy + forwardproxy + caddy-l4)
# ─────────────────────────────────────────────────────────────────────────────
log "--- [4/5] caddy ---"

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  > /etc/apt/sources.list.d/caddy-stable.list
apt-get update -qq
apt-get install -y -qq caddy
chk "caddy apt"

systemctl stop caddy 2>/dev/null || true

apt-get install -y -qq golang-go
chk "golang"

export GOPATH="/root/go"
go install github.com/caddyserver/xcaddy/cmd/xcaddy@v0.4.5
chk "xcaddy install"

log "xcaddy build (2-5 min)..."
BUILD_DIR="$(mktemp -d)"
"${GOPATH}/bin/xcaddy" build \
  --with github.com/caddyserver/forwardproxy@caddy2 \
  --with github.com/mholt/caddy-l4 \
  --output "${BUILD_DIR}/caddy"
chk "xcaddy build"

install -m 755 "${BUILD_DIR}/caddy" /usr/bin/caddy
setcap cap_net_bind_service=+ep /usr/bin/caddy
rm -rf "${BUILD_DIR}"
ok "caddy binary"

# Caddyfile: FP auth block
FP_AUTH_BLOCK=""
for entry in "${FP_CREDS[@]}"; do
  u="${entry%%:*}"
  p="${entry#*:}"
  FP_AUTH_BLOCK+="        basic_auth ${u} ${p}"$'\n'
done

# Caddyfile: FP upstream по FP_CHAIN
FP_UPSTREAM_LINE=""
if [[ -n "${NEXT_HOP}" ]]; then
  case "${FP_CHAIN}" in
    1)
      _S5U="${SOCKS5_CREDS[0]%%:*}"
      _S5P="${SOCKS5_CREDS[0]#*:}"
      FP_UPSTREAM_LINE="        upstream socks5://${_S5U}:${_S5P}@127.0.0.1:8083"$'\n'
      ;;
    2)
      FP_UPSTREAM_LINE="        upstream https://${FP_CHAIN_UPSTREAM_USER}:${FP_CHAIN_UPSTREAM_PASS}@${NEXT_HOP}:443"$'\n'
      ;;
  esac
fi

# Caddyfile: RP block
if [[ "${INSTALL_DOTNET}" -eq 1 ]]; then
  RP_BLOCK="        reverse_proxy localhost:8081"
else
  mkdir -p /var/www/html
  cat > /var/www/html/index.html <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>Welcome</title>
<style>body{font-family:sans-serif;max-width:480px;margin:4rem auto;color:#555}</style>
</head><body><h2>Welcome</h2><p>Service is running.</p></body></html>
HTMLEOF
  RP_BLOCK="        root * /var/www/html
        file_server"
fi

# Caddyfile: SOCKS5 credentials block для layer4
_S5_CREDS_BLOCK=""
for entry in "${SOCKS5_CREDS[@]}"; do
  u="${entry%%:*}"
  p="${entry#*:}"
  _S5_CREDS_BLOCK+="                credentials ${u} ${p}"$'\n'
done

cat > /etc/caddy/Caddyfile <<EOF
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
${_S5_CREDS_BLOCK}                }
            }
        }
    }
}

${NODE_DOMAIN} {
    header -Server
    header -X-Powered-By

    forward_proxy {
${FP_AUTH_BLOCK}${FP_UPSTREAM_LINE}        probe_resistance
        hide_ip
        hide_via
    }

    handle {
${RP_BLOCK}
    }
}
EOF
chk "Caddyfile"

systemctl daemon-reload
systemctl enable caddy --now
chk "caddy service"

# ─────────────────────────────────────────────────────────────────────────────
# 5. telemt
# ─────────────────────────────────────────────────────────────────────────────
log "--- [5/5] telemt ---"

curl -fsSL https://raw.githubusercontent.com/telemt/telemt/main/install.sh \
  -o /tmp/telemt-install.sh
chk "telemt download"
bash /tmp/telemt-install.sh
chk "telemt install"

systemctl stop telemt 2>/dev/null || true

mkdir -p /etc/telemt/tlsfront

TELEMT_USERS_TOML=""
for entry in "${TELEMT_CREDS[@]}"; do
  alias="${entry%%:*}"
  secret="${entry#*:}"
  TELEMT_USERS_TOML+="${alias} = \"${secret}\""$'\n'
done

if [[ -n "${NEXT_HOP}" ]]; then
  _S5U="${SOCKS5_CREDS[0]%%:*}"
  _S5P="${SOCKS5_CREDS[0]#*:}"
  UPSTREAM_BLOCK="
[upstream]
type = \"socks5\"

[upstream.socks5]
host     = \"127.0.0.1\"
port     = 8083
username = \"${_S5U}\"
password = \"${_S5P}\""
else
  UPSTREAM_BLOCK=""
fi

cat > /etc/telemt/config.toml <<EOF
[general]
use_middle_proxy = false

[general.modes]
classic = false
secure  = false
tls     = true

[general.links]
show        = "*"
public_host = "${NODE_DOMAIN}"
public_port = 443

[server]
port = 443

[server.api]
enabled   = true
listen    = "127.0.0.1:9091"
whitelist = ["127.0.0.0/8"]

[censorship]
tls_domain         = "${TELEMT_TLS_DOMAIN}"
unknown_sni_action = "mask"
mask               = true
mask_host          = "127.0.0.1"
mask_port          = 8443
tls_emulation      = true
tls_front_dir      = "/etc/telemt/tlsfront"
${UPSTREAM_BLOCK}
[access.users]
${TELEMT_USERS_TOML}
EOF
chk "telemt config.toml"

systemctl enable telemt --now
chk "telemt service"

# ─────────────────────────────────────────────────────────────────────────────
# [+] .NET 10
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${INSTALL_DOTNET}" -eq 1 ]]; then
  log "--- [+] .NET 10 ---"
  wget -q https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb \
    -O /tmp/ms-prod.deb
  dpkg -i /tmp/ms-prod.deb
  apt-get update -qq
  apt-get install -y -qq dotnet-sdk-10.0
  chk ".NET 10"
else
  log "--- [+] INSTALL_DOTNET=0 --- skip"
fi

# ─────────────────────────────────────────────────────────────────────────────
# [+] Telegram Local Server
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${INSTALL_TG}" -eq 1 ]]; then
  log "--- [+] Telegram Local Server (build ~10 min) ---"
  apt-get install -y -qq cmake g++ make zlib1g-dev libssl-dev gperf
  chk "tg-bot-api build deps"
  git clone --recursive https://github.com/tdlib/telegram-bot-api.git /opt/tg-bot-api-src
  cmake -DCMAKE_BUILD_TYPE=Release \
        -S /opt/tg-bot-api-src \
        -B /opt/tg-bot-api-src/build
  cmake --build /opt/tg-bot-api-src/build --target install -j"$(nproc)"
  chk "telegram-bot-api build"

  cat > /etc/systemd/system/telegram-bot-api.service <<EOF
[Unit]
Description=Telegram Bot API
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/telegram-bot-api \
  --api-id=${TG_API_ID} \
  --api-hash=${TG_API_HASH} \
  --http-port=8082 \
  --local
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable telegram-bot-api --now
  chk "telegram-bot-api service"
else
  log "--- [+] INSTALL_TG=0 --- skip"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Финальный вывод
# ─────────────────────────────────────────────────────────────────────────────
DOMAIN_HEX=$(printf '%s' "${NODE_DOMAIN}" | xxd -p -c 1000)

echo ""
echo "==============================="
echo "  FORWARD PROXY"
echo "==============================="
echo "  Host:     ${NODE_DOMAIN}:443"
echo "  FP_CHAIN: ${FP_CHAIN}  (0=direct 1=socks5 2=https-connect)"
echo ""
for entry in "${FP_CREDS[@]}"; do
  printf "  %-32s %s\n" "${entry%%:*}" "${entry#*:}"
done

echo ""
echo "==============================="
echo "  SOCKS5  (internal :8083)"
echo "==============================="
for entry in "${SOCKS5_CREDS[@]}"; do
  printf "  %-32s %s\n" "${entry%%:*}" "${entry#*:}"
done

echo ""
echo "==============================="
echo "  MTPROTO LINKS"
echo "==============================="
for entry in "${TELEMT_CREDS[@]}"; do
  alias="${entry%%:*}"
  secret="${entry#*:}"
  echo "  ${alias}:"
  echo "  tg://proxy?server=${NODE_DOMAIN}&port=443&secret=ee${secret}${DOMAIN_HEX}"
  echo ""
done

echo "==============================="
echo "  SERVICES"
echo "==============================="
for svc in caddy telemt fail2ban; do
  systemctl is-active --quiet "${svc}" \
    && printf "  %-24s active\n" "${svc}" \
    || printf "  %-24s FAILED\n" "${svc}"
done
[[ "${INSTALL_DOTNET}" -eq 1 ]] && printf "  %-24s installed\n" "dotnet"
[[ "${INSTALL_TG}" -eq 1 ]] && {
  systemctl is-active --quiet telegram-bot-api \
    && printf "  %-24s active\n" "telegram-bot-api" \
    || printf "  %-24s FAILED\n" "telegram-bot-api"
}
echo ""
echo "  LOG: ${LOG_FILE}"
echo "==============================="
