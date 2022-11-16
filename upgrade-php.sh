#!/bin/bash

shopt -s inherit_errexit nullglob
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
WARN="${DGN}⚠${CL}"
DEBIAN_FRONTEND=noninteractive

function getIni() {
    startsection="$1"
    endsection="$2"
    output="$(awk "/$startsection/{ f = 1; next } /$endsection/{ f = 0 } f" "${CONFIG_FILE}")"
}

function backupConfigs() {
    cp -pr --archive "$1" "$1"-COPY-"$(date +"%m-%d-%Y")" >/dev/null 2>&1
}

function msg_info() {
    local msg="$1"
    echo -ne " ${HOLD} ${YW}${msg}..."
}

function msg_ok() {
    local msg="$1"
    echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

function msg_warn() {
    local msg="$1"
    echo -e "${BFR} ${WARN} ${DGN}${msg}${CL}"
}

function msg_error() {
    local msg="$1"
    echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

function errorhandler() {
    msg_error "$1"
    exit 1
}

function header_info {
    clear
    echo -e "${RD}
                                                   
 _____ _____ _____    _____                   _     
|  _  |  |  |  _  |  |  |  |___ ___ ___ ___ _| |___ 
|   __|     |   __|  |  |  | . | . |  _| .'| . | -_|
|__|  |__|__|__|     |_____|  _|_  |_| |__,|___|___|
                           |_| |___|                
                                                                                    
${CL}"
}

function yesNoDialog() {
    while true; do
        read -p "${1}" yn
        case $yn in
        [Yy]*) break ;;
        [Nn]*) exit 0 ;;
        *) echo "Please answer yes or no." ;;
        esac
    done

}

function upgradeSystem() {
    msg_info "Updating system"
    apt-get update -y >/dev/null 2>&1
    apt-get full-upgrade -y >/dev/null 2>&1
    msg_ok "System updated"
}

function upgradePHP() {
    msg_info "Updating PHP"
    OLD_PHPVERSION=$(php -v | head -n 1 | cut -d" " -f 2 | cut -d"." -f 1-2)
    apt-get -y install lsb-release ca-certificates apt-transport-https software-properties-common gnupg2 >/dev/null 2>&1
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/sury-php.list >/dev/null 2>&1
    curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/sury-keyring.gpg >/dev/null 2>&1
    apt-get update -y >/dev/null 2>&1
    apt-get install -y php8.1 >/dev/null 2>&1
    apt-get update -y >/dev/null 2>&1
    apt-get -f -m full-upgrade -y >/dev/null 2>&1
    apt-get autoremove -y >/dev/null 2>&1
    update-alternatives --set php /usr/bin/php${PHP_VERSION} >/dev/null 2>&1
    PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1-2)
    if [[ "${OLD_PHPVERSION}" == "${PHP_VERSION}" ]]; then
        errorhandler "PHP update failed, check logs"
    else
        msg_ok "PHP updated from version ${OLD_PHPVERSION} to ${PHP_VERSION}"
    fi
    msg_info "Setting PHP Version ${PHP_VERSION} as default"
    if [ -f /etc/apache2/apache2.conf ]; then
        msg_info "Detected Apache2, updating php version"
        a2dismod php${OLD_PHPVERSION} >/dev/null 2>&1
        a2enmod php${PHP_VERSION} >/dev/null 2>&1
        a2disconf php${OLD_PHPVERSION}-fpm >/dev/null 2>&1
        a2enconf php${PHP_VERSION}-fpm >/dev/null 2>&1
        systemctl restart apache2 >/dev/null 2>&1
        msg_ok "Apache2 updated"
    fi

    if [[ "$(systemctl is-active ${OLD_PHPVERSION}-fpm)" == "active" ]]; then
        msg_info "Detected PHP-FPM, updating php version"
        systemctl stop ${OLD_PHPVERSION}-fpm >/dev/null 2>&1
        systemctl disable ${OLD_PHPVERSION}-fpm >/dev/null 2>&1
        systemctl enable php${PHP_VERSION}-fpm >/dev/null 2>&1
        msg_ok "PHP-FPM updated"
    fi
    if [[ "$(systemctl is-active php8.1-fpm)" == "inactive" ]]; then
        systemctl restart php${PHP_VERSION}-fpm >/dev/null 2>&1
        systemctl enable php${PHP_VERSION}-fpm >/dev/null 2>&1
    fi
    if [ -f /etc/nginx/nginx.conf ]; then
        msg_info "Detected Nginx, updating php version"
        sed -i "s/${OLD_PHPVERSION}/${PHP_VERSION}/g" /etc/nginx/nginx.conf >/dev/null 2>&1
        sed -i "s/${OLD_PHPVERSION}/${PHP_VERSION}/g" /etc/nginx/sites-available/* >/dev/null 2>&1
        nginxStatus="$(nginx -t 2>&1)"
        if [[ "$nginxStatus" = *"successful"* ]]; then
            systemctl restart nginx >/dev/null 2>&1
        else
            msg_error "Nginx config test failed, please check your config"
        fi
        msg_ok "Nginx updated"
    fi
    msg_ok "PHP ${OLD_PHPVERSION} disabled and PHP ${PHP_VERSION} enabled"

}

function main() {
    header_info
    yesNoDialog "This script will upgrade your system and PHP to the latest version. Do you want to continue? [y/n]: "
    if [[ "$EUID" -ne 0 ]]; then
        errorhandler "This script must be run as root"
    fi
    upgradeSystem
    upgradePHP
}
main
