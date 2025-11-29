#!/bin/sh
set -e

FTP_USER="${FTP_USER:-ftpuser}"
FTP_PWD="${FTP_PWD:-ftppass}"

FTP_USER="$(echo "$FTP_USER" | tr 'A-Z' 'a-z')"

mkdir -p /var/run/vsftpd/empty

if ! id "$FTP_USER" >/dev/null 2>&1; then
    echo "Creating FTP user: $FTP_USER"
    adduser --disabled-password --gecos "" "$FTP_USER"
    echo "$FTP_USER:$FTP_PWD" | chpasswd
    usermod -d /var/www/wordpress "$FTP_USER"
fi

while [ ! -d /var/www/wordpress ]; do
    echo "Waiting for WordPress volume..."
    sleep 2
done

echo "Setting permissions for $FTP_USER on /var/www/wordpress"
chown -R "$FTP_USER:$FTP_USER" /var/www/wordpress

if [ ! -f /etc/ssl/private/ftp.key ]; then
    mkdir -p /etc/ssl/private/
    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout /etc/ssl/private/ftp.key \
        -out /etc/ssl/private/ftp.crt \
        -days 365 \
        -subj "/CN=${DOMAIN:-localhost}"
fi

echo "Starting vsftpd..."
exec /usr/sbin/vsftpd /etc/vsftpd.conf
