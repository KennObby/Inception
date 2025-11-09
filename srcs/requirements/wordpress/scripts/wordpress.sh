#!/bin/sh

set -e


mkdir -p /var/www/
mkdir -p /var/www/wordpress

cd /var/www/wordpress

DB_HOST="${WP_DB_HOST%:*}"
DB_PORT="${WP_DB_HOST#*:}"
[ "$DB_HOST" = "$WP_DB_HOST" ] && DB_PORT=3306

echo "Waiting for MariaDB at $DB_HOST:$DB_PORT and DB ${WP_DB}..."
until mysql -h "$DB_HOST" -P "$DB_PORT" -u "$WP_DB_USER" -p"$WP_DB_PWD" -e "USE ${WP_DB}; SELECT 1;" >/dev/null 2>&1; do
    sleep 2
done
echo "MariaDB ready."

if ! command -v wp > /dev/null 2>&1; then 
    curl -LO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp
fi

if [ ! -f /var/www/wordpress/wp-settings.php ]; then
    wp core download --allow-root
fi

if [ -f /var/www/wordpress/wp-config.php ]; then
  wp config set DB_NAME     "$WP_DB"      --type=constant --allow-root
  wp config set DB_USER     "$WP_DB_USER" --type=constant --allow-root
  wp config set DB_PASSWORD "$WP_DB_PWD"  --type=constant --allow-root
  wp config set DB_HOST     "$WP_DB_HOST" --type=constant --allow-root
else
  wp config create \
    --dbname="$WP_DB" \
    --dbuser="$WP_DB_USER" \
    --dbpass="$WP_DB_PWD" \
    --dbhost="$WP_DB_HOST" \
    --allow-root --skip-check
  wp config shuffle-salts --allow-root
fi

wp core is-installed --allow-root --path=/var/www/wordpress || \
wp core install \
    --url="$DOMAIN" \
    --title="$WP_TITLE" \
    --admin_user="$WP_ADMIN_USER" \
    --admin_password="$WP_ADMIN_PWD" \
    --admin_email=$WP_ADMIN_MAIL \
    --skip-email \
    --allow-root --path=/var/www/wordpress

wp user create $WP_USER $WP_MAIL --allow-root

wp theme install beep --activate --allow-root

wp plugin update --all --allow-root

sed -i 's|^listen = .*|listen = 9000|' /etc/php/8.2/fpm/pool.d/www.conf
mkdir -p /run/php

chown -R www-data:www-data /var/www/wordpress

exec /usr/sbin/php-fpm8.2 -F
