#!/bin/sh

FTP_USER="${FTP_USER:-Oleg}"
FTP_PWD="${FTP_PWD:-test}"

if ! id "$FTP_USER" >/dev/null 2>&1; then
    adduser --disabled-password --gecos " " "$FTP_USER"
    echo "$FTP_USER:$FTP_PWD" | chpasswd
fi

usermod -d /var/www/wordpress "$FTP_USER"
chown -R "$FTP_USER:$FTP_PWD" /var/www/wordpress

if [ ! -f /etc/ssl/private/ftp.key ]; then
    mkdir -p /etc/ssl/private/
    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout /etc/ssl/private/ftp.key \
        -out /etc/ssl/private/ftp.crt \
        -days 365 \
        -subj "/CN=${DOMAIN:-localhost}"
fi

exec /usr/sbin/vsftpd /etc/vsftpd.conf
