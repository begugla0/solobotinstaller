#!/bin/bash
set -e

# Цвета
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

echo -e "${CYAN}=== Установка бота SoloNet ===${RESET}"
echo -e "${YELLOW}Автор скрипта: https://github.com/begugla0/${RESET}"

# Проверка root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Скрипт нужно запускать от root!${RESET}"
   exit 1
fi

# Переменные
read -rp "Введите домен бота (например bot.domain.com): " BOT_DOMAIN
read -rp "Введите красивый путь для подписки (например mysub): " SUB_PATH
read -rp "Введите имя пользователя PostgreSQL: " PG_USER
read -rp "Введите пароль для PostgreSQL: " PG_PASS
read -rp "Введите имя базы PostgreSQL: " PG_DB
read -rp "Введите путь до папки с ботом (например /root/Solo_bot): " BOT_DIR

# Выбор веб-сервера
echo -e "${YELLOW}Выберите веб-сервер:${RESET}"
select SERVER in "Nginx" "Caddy"; do
    case $SERVER in
        Nginx ) WEB_SERVER="nginx"; break;;
        Caddy ) WEB_SERVER="caddy"; break;;
        * ) echo "Неверный выбор";;
    esac
done
echo -e "${GREEN}Вы выбрали: $WEB_SERVER${RESET}"

# Обновление системы
DEBIAN_FRONTEND=noninteractive \
apt -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" update -y

DEBIAN_FRONTEND=noninteractive \
apt -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" upgrade -y

# Установка базовых пакетов
apt install -y \
    git curl wget nano unzip tar htop mc \
    software-properties-common build-essential pkg-config \
    python3-dev python3-pip python3-venv \
    libpq-dev libffi-dev libssl-dev zlib1g-dev libjpeg-dev libpng-dev

# Установка веб-сервера
if [[ $WEB_SERVER == "nginx" ]]; then
    apt install -y nginx certbot python3-certbot-nginx
    systemctl enable --now nginx
    certbot --nginx -d "$BOT_DOMAIN"
else
    apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update -y && apt install -y caddy
fi

# PostgreSQL
apt install -y postgresql postgresql-contrib
systemctl enable --now postgresql
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='$PG_USER'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE USER $PG_USER WITH PASSWORD '$PG_PASS';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='$PG_DB'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE $PG_DB OWNER $PG_USER;"

# Python 3.12
add-apt-repository ppa:deadsnakes/ppa -y
apt update -y
apt install -y python3.12 python3.12-venv python3.12-dev

# Скачивание бота
echo -e "${CYAN}Скачиваю Solo_bot с GitHub...${RESET}"
rm -rf "$BOT_DIR"
git clone https://github.com/Vladless/Solo_bot.git "$BOT_DIR"

# Пауза для добавления config.py и texts.py
echo -e "${YELLOW}==============================================${RESET}"
echo -e "${YELLOW}Скопируйте файл ${GREEN}config.py${YELLOW} в корень проекта:${RESET}"
echo -e "${CYAN}$BOT_DIR/config.py${RESET}"
echo -e "${YELLOW}И файл ${GREEN}texts.py${YELLOW} в папку handlers:${RESET}"
echo -e "${CYAN}$BOT_DIR/handlers/texts.py${RESET}"
echo -e "${YELLOW}После этого нажмите ${GREEN}Enter${YELLOW} для продолжения.${RESET}"
echo -e "${YELLOW}==============================================${RESET}"
read -p ""

# Виртуальное окружение
cd "$BOT_DIR"
python3.12 -m venv venv
source venv/bin/activate
curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12
pip install --upgrade pip
pip install -r requirements.txt || true
deactivate

# Systemd сервис
cat > /etc/systemd/system/bot.service <<EOF
[Unit]
Description=SoloBot Service
After=network.target

[Service]
User=root
WorkingDirectory=$BOT_DIR
ExecStart=$BOT_DIR/venv/bin/python $BOT_DIR/main.py
Restart=always
KillMode=control-group
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable bot.service
systemctl start bot.service

echo -e "${GREEN}Установка завершена!${RESET}"
echo -e "Проверить бота: ${YELLOW}systemctl status bot.service${RESET}"
echo -e "Логи: ${YELLOW}journalctl -u bot.service -f${RESET}"
