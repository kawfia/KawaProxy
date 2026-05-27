#!/bin/sh
SERVER_NAME="mayhem"			# Название сервера
DOMAIN_API=""					# Домен для Caddy "API"
DOMAIN_WEB=""					# Домен для Caddy "WEB"
DOMAIN_PROXY=""					# Домен для Caddy PROXY

# Порты
SSH_PORT=22
TELEMT_HTTPS_PORT=443
TELEMT_API_PORT=8083
CADDY_HTTP_PORT=80
CADDY_HTTPS_PORT=8443
CADDY_PROXYSOCKS5_PORT=1080
CADDY_PROXYHTTP_PORT=8080
OPEN_PORTS=($SSH_PORT $TELEMT_HTTPS_PORT $CADDY_HTTP_PORT $CADDY_PROXYHTTP_PORT $CADDY_PROXYSOCKS5_PORT)

# Настройки Fail2Ban
FAIL2BAN_MAXRETRY=15			# количество попыток
FAIL2BAN_FINDTIME=300			# за какое время
FAIL2BAN_BANTIME=-1		 		# время бана

# Настройки Telemt
TELEMT_LANG=2					# 1=en, 2=ru
TELEMT_MASK_HOST="127.0.0.1"	# куда пересылать запросы
#TELEMT_MASK_PORT=8443			# на какой порт пересылать запросы
TELEMT_USERS=("kawfia" "encore")

# Настройки Caddy
CADDY_PROXY_HTTP_USER="httpUser"
CADDY_PROXY_HTTP_PASS="0837feac-e249-4bd0-943d-c9a44ddd50f4"
CADDY_PROXY_SOCKS5_USER="socks5User"
CADDY_PROXY_SOCKS5_PASS="173d1614-77ce-45d9-879a-1eb652e924d7"

LOG_FILE="/var/log/telemt_full_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Логирование начато $(date) ==="

# ============================================
# ФУНКЦИЯ ОБРАБОТКИ ОШИБОК
# ============================================
check_error() {
	if [ $? -ne 0 ]; then
		echo "[ОШИБКА] $1"
	else
		echo "[ОК] $1"
	fi
}

# ============================================
# 1. ОБНОВЛЕНИЕ СИСТЕМЫ
# ============================================
sudo apt update && sudo apt upgrade -y
check_error "Обновление пакетов"

# ============================================
# 2. ПЕРЕИМЕНОВАНИЕ СЕРВЕРА
# ============================================
sudo hostnamectl set-hostname "$SERVER_NAME"
check_error "Установка hostname"

sudo sed -i '/127\.0\.1\.1/d' /etc/hosts
echo "127.0.1.1 $SERVER_NAME" | sudo tee -a /etc/hosts > /dev/null
check_error "Обновление /etc/hosts"

# ============================================
# 3. ОТКЛЮЧЕНИЕ IPv6
# ============================================
cat > /tmp/99-disable-ipv6.conf << EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sudo mv /tmp/99-disable-ipv6.conf /etc/sysctl.d/99-disable-ipv6.conf
sudo sysctl -p /etc/sysctl.d/99-disable-ipv6.conf
check_error "Применение параметров отключения IPv6"

# ============================================
# 4. НАСТРОЙКА UFW (открытие разрешенных портов)
# ============================================
sudo apt install ufw -y
check_error "Установка ufw"
sudo ufw --force reset

sudo ufw default deny incoming
sudo ufw default allow outgoing
for port in "${OPEN_PORTS[@]}"; do
	sudo ufw allow "$port"/tcp
	check_error "Открыт порт $port/tcp"
done
sudo ufw --force enable
check_error "Включение ufw"

# ============================================
# 5. УСТАНОВКА И НАСТРОЙКА FAIL2BAN (50 попыток за 5 мин, вечный бан)
# ============================================
sudo apt install fail2ban -y
check_error "Установка fail2ban"

cat > /tmp/jail.local << EOF
[DEFAULT]
bantime = $FAIL2BAN_BANTIME
findtime = $FAIL2BAN_FINDTIME
maxretry = $FAIL2BAN_MAXRETRY

[sshd]
enabled = true
EOF
sudo mv /tmp/jail.local /etc/fail2ban/jail.local
check_error "Создание конфигурации fail2ban"

sudo systemctl restart fail2ban
sudo systemctl enable fail2ban
check_error "Запуск fail2ban"

# ============================================
# 6. УСТАНОВКА TELEMT
# ============================================
curl -fsSL https://raw.githubusercontent.com/telemt/telemt/main/install.sh | sh -s -- -l "$TELEMT_LANG" -d "$DOMAIN" -p "$TELEMT_HTTPS_PORT"
check_error "Установка Telemt"

# Останавливаем службу, если запущена
sudo systemctl stop telemt 2>/dev/null

sudo cp /etc/telemt/telemt.toml /etc/telemt/telemt.toml.bak

# Генерация секций [access.users] для пользователей прокси
ACCESS_USERS_BLOCK=""
USER_SECRETS=()
for username in "${TELEMT_USERS[@]}"; do
	# Секрет = первые 32 символа SHA-256 от имени пользователя
	secret=$(echo -n "$username" | sha256sum | cut -c1-32)
	USER_SECRETS+=("$username:$secret")
	ACCESS_USERS_BLOCK+="$username = \"$secret\"\n"
done

# Формирование конфигурационного файла telemt.toml
cat > /tmp/telemt.toml << EOF
[general]
use_middle_proxy = true
log_level = "normal"

[general.modes]
classic = false
secure = false
tls = true

[general.links]
show = "*"
public_host = "$SERVER_NAME"
public_port = $TELEMT_HTTPS_PORT

[server]
port = $TELEMT_HTTPS_PORT

[[server.listeners]]
ip = "0.0.0.0"

[server.api]
enabled = true
listen = "127.0.0.1:$TELEMT_API_PORT"
whitelist = ["127.0.0.1/32"]
minimal_runtime_enabled = true
minimal_runtime_cache_ttl_ms = 1000

[censorship]
tls_domain = "$DOMAIN"
mask = true
mask_host = "$TELEMT_MASK_HOST"
mask_port = $TELEMT_MASK_PORT
tls_emulation = true
tls_front_dir = "/var/lib/telemt/tlsfront"
unknown_sni_action = "mask"

[access.users]
$(echo -e "$ACCESS_USERS_BLOCK")
EOF

sudo mv /tmp/telemt.toml /etc/telemt/telemt.toml
check_error "Запись конфигурации /etc/telemt/telemt.toml"

sudo systemctl restart telemt
check_error "Перезапуск службы telemt"
sudo systemctl enable telemt
check_error "Включение автозапуска telemt"


# ============================================
# N. ~~~~
# ============================================

# ============================================
# 7. УСТАНОВКА CADDY
# ============================================
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
check_error "Установка зависимостей для Caddy"

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
check_error "Добавление репозитория Caddy"

sudo apt update
sudo apt install -y caddy
check_error "Установка Caddy из официального репозитория"

sudo systemctl stop caddy

# Бэкап стандартного Caddyfile
sudo cp /usr/bin/caddy /usr/bin/caddy.bak
sudo cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak 2>/dev/null || true
check_error "Бэкап /usr/bin/caddy"

# ============================================
# 7.1 ОСТАНОВКА CADDY И СБОРКА КАСТОМНОЙ ВЕРСИИ
# ============================================
# Установка Go
sudo apt install -y golang-go
check_error "Установка Golang"

export GOPATH=$HOME/go
export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin
mkdir -p $GOPATH

# Установка xcaddy
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
check_error "Установка xcaddy"

# Сборка бинарника
~/go/bin/xcaddy build \
	--with github.com/caddyserver/forwardproxy \
	--with github.com/mholt/caddy-l4
check_error "Сборка кастомного Caddy"

# Замена на новый собранный бинарник
sudo mv ./caddy /usr/bin/caddy
sudo chmod 755 /usr/bin/caddy
sudo chown root:root /usr/bin/caddy
check_error "Замена бинарника Caddy"

# ============================================
# 7.2 НАСТРОЙКА CADDYFILE ДЛЯ ПРОКСИ
# ============================================
sudo tee /etc/caddy/Caddyfile > /dev/null <<EOF
{
	auto_https disable_redirects
	layer4 {
		:1080 {
			route {
				socks5 {
					commands CONNECT ASSOCIATE
					credentials socks5User 173d1614-77ce-45d9-879a-1eb652e924d7
				}
			}
		}
	}
}

http://api.kawacore.net {
	redir https://api.kawacore.net{uri} 308
}

api.kawacore.net:8443 {
		header -Alt-Svc
		root * /usr/share/caddy
		file_server
}

:80 {
}

:8080 {
	forward_proxy {
		basic_auth httpUser 0837feac-e249-4bd0-943d-c9a44ddd50f4
		hide_ip
		hide_via
	}
}
EOF
check_error "Создание нового Caddyfile"

sudo systemctl enable caddy
sudo systemctl start caddy
sudo systemctl status caddy --no-pager || true
# ============================================
# X. ВЫВОД ССЫЛОК
# ============================================
echo "=== Ссылки для подключения (режим TLS/ee) ==="
for entry in "${USER_SECRETS[@]}"; do
	username="${entry%:*}"
	random_hex="${entry#*:}"
	domain_hex=$(printf '%s' "$DOMAIN" | xxd -p -c 1000)
	echo "$username: tg://proxy?server=$DOMAIN&port=$TELEMT_HTTPS_PORT&secret=ee${random_hex}${domain_hex}"
done
