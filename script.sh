#!/bin/bash

set -eu

trap end_install EXIT

#
##
update_system() {
    #
    apt update
    apt -yqq upgrade
}

#
##
install_base_system() {
    #
    apt -yqq install --no-install-recommends apt-utils 2>&1
    apt -yqq install --no-install-recommends apt-transport-https 2>&1
    #
    apt -yqq install ca-certificates build-essential net-tools curl wget lsb-release procps 2>&1
    apt -yqq install perl unzip git nano htop iftop mariadb-client 2>&1
}

#
##
define_passwords() {
    # check if existing passwords file exists
    if [ ! -f /root/passwords.txt ]; then
        # root database user
        rootdbpass=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
        # database user
        dbname="app"
        dbuser="app"
        dbpass=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

        echo "#
# Deploy Script - Credentials file
#
# Database
#
# Root user password
rootdbpass=\"$rootdbpass\"
#
# Database Name
dbname=\"$dbname\"
#
# Database User
dbuser=\"$dbuser\"
#
# Database Password
dbpass=\"$dbpass\"
" > /root/passwords.txt
    else
        # load existing file
        set -o allexport
        source /root/passwords.txt
        set +o allexport
    fi
}

#
##
install_apache() {
    # apache2 and Utils
    apt -yqq install apache2 apache2-utils

    # enable apache modules
    a2enmod headers
    a2enmod rewrite

    #
    awk '/<Directory \/var\/www\/>/,/AllowOverride None/{sub("None", "All",$0)}{print}' /etc/apache2/apache2.conf > tmp.conf && mv tmp.conf /etc/apache2/apache2.conf
    
    #
    service apache2 restart

    #
    rm  -f /var/www/html/index.html
}

#
##
install_adminer() {
    #
    wget http://www.adminer.org/latest.php -O /var/www/html/index.php
}

#
##
install_php() {
    # is PHP5
    if [ "$VERSION_ID" = "12.04" ] || [ "$VERSION_ID" = "14.04" ] || [ "$VERSION_ID" = "15.04" ]; then
        PHP_VERSION="5"
    fi

    # is PHP7
    if [ "$VERSION_ID" = "16.04" ] || [ "$VERSION_ID" = "16.10" ] || [ "$VERSION_ID" = "17.04" ] || [ "$VERSION_ID" = "17.10" ]; then
        PHP_VERSION="7.0"
    fi

    # is PHP7.2
    if [ "$VERSION_ID" = "18.04" ] || [ "$VERSION_ID" = "18.10" ]; then
        PHP_VERSION="7.2"
    fi

    # is PHP7.4
    if [ "$VERSION_ID" = "20.04" ] || [ "$VERSION_ID" = "20.10" ]; then
        PHP_VERSION="7.4"
    fi

    #

    # install PHP5
    if [ "$PHP_VERSION" = "5" ]; then
        #
        echo "Installing PHP$PHP_VERSION"
        apt -yqq install php$PHP_VERSION php$PHP_VERSION-cli
        apt -yqq install php$PHP_VERSION-{curl,gd,mcrypt,json,mysql,sqlite}
        #
        apt -yqq install libapache2-mod-php$PHP_VERSION
        #
        # enable mods
        php5enmod mcrypt

        #
        service apache2 restart
    fi

    # install PHP7
    if [ "$PHP_VERSION" = "7.0" ]; then
        #
        echo "Installing PHP$PHP_VERSION"
        apt -yqq install php$PHP_VERSION php$PHP_VERSION-cli
        apt -yqq install php$PHP_VERSION-{mbstring,curl,gd,mcrypt,json,xml,mysql,sqlite}
        #
        apt -yqq install libapache2-mod-php$PHP_VERSION

        #
        service apache2 restart
    fi

    # install PHP[7.2]
    if [ "$PHP_VERSION" = "7.2" ] || [ "$PHP_VERSION" = "7.4" ]; then
        #
        echo "Installing PHP$PHP_VERSION"
        apt -yqq install php$PHP_VERSION php$PHP_VERSION-cli
        apt -yqq install php$PHP_VERSION-{mbstring,curl,gd,json,xml,mysql,sqlite3,opcache,zip}
        #
        apt -yqq install libapache2-mod-php$PHP_VERSION

        #
        service apache2 restart
    fi

    # install PHP[7.4]
    if [ "$PHP_VERSION" = "7.4" ]; then
        #
        echo "Installing PHP"
        apt -yqq install php php-cli
        apt -yqq install php-{common,bz2,getid3,imagick,intl,mbstring,curl,gd,json,xml,mysql,sqlite3,opcache,zip}
        #
        apt -yqq install libapache2-mod-php

        #
        service apache2 restart
    fi
}

#
##
install_mysql() {
    #
    debconf-set-selections <<< "mariadb-server-10.0 mysql-server/root_password password $rootdbpass"
    debconf-set-selections <<< "mariadb-server-10.0 mysql-server/root_password_again password $rootdbpass"
    
    #
    apt -yqq install mariadb-server
    apt -yqq install mariadb-client
    
    #
    sed -i "s/.*bind-address.*/bind-address = 0.0.0.0/" /etc/mysql/mariadb.conf.d/50-server.cnf
    
    #
    service mysql start

    #
    while ! mysqladmin ping --silent -u"root" -p"$rootdbpass"; do
        echo >&2 "Deploy-Script: [database] - waiting for database server to start +2s"
        sleep 2
    done

    #
    mysql -u root -p"$rootdbpass" -e "CREATE DATABASE IF NOT EXISTS \`$dbname\` /*\!40100 DEFAULT CHARACTER SET utf8mb4 */;"
    mysql -u root -p"$rootdbpass" -e "CREATE USER IF NOT EXISTS $dbuser@'%' IDENTIFIED BY '$dbpass';"
    mysql -u root -p"$rootdbpass" -e "GRANT ALL PRIVILEGES ON \`$dbname\`.* TO '$dbuser'@'%';"
    mysql -u root -p"$rootdbpass" -e "GRANT ALL PRIVILEGES on *.* to 'root'@'localhost' IDENTIFIED BY '$rootdbpass';"
    mysql -u root -p"$rootdbpass" -e "FLUSH PRIVILEGES;"
}

start_install(){
    #
    . /etc/os-release

    # check is root user
    if [[ $EUID -ne 0 ]]; then
        echo "You must be root user to install scripts."
        sudo su
    fi

    # check is root user
    if [[ $ID != "ubuntu" ]]; then
        echo "Wrong OS! Sorry only Ubuntu is supported."
        exit 1
    fi

    export DEBIAN_FRONTEND=noninteractive
    echo >&2 "Deploy-Script: [OS] $PRETTY_NAME"
}

end_install(){
    # clean up apt
    apt-get autoremove -y && apt-get autoclean -y && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

    # return to dialog
    export DEBIAN_FRONTEND=dialog

    # remove script
    rm -f script.sh
}

#
##
main() {
    #
    start_install

    #
    update_system
    
    #
    install_base_system

    #
    define_passwords

    #
    install_apache
    
    #
    install_php
    
    #
    install_adminer
    
    #
    install_mysql

    echo >&2 "LAMP install completed"

    end_install
}

main
