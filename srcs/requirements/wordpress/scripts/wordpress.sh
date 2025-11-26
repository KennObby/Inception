#!/bin/sh

set -e


mkdir -p /var/www/
mkdir -p /var/www/wordpress

cd /var/www/wordpress

DB_HOST="${WP_DB_HOST%:*}"
DB_PORT="${WP_DB_HOST#*:}"
[ "$DB_HOST" = "$WP_DB_HOST" ] && DB_PORT=3306

WP_URL="https://${DOMAIN}"

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
  wp --allow-root --path=/var/www/wordpress config set DB_NAME     "$WP_DB"      --type=constant
  wp --allow-root --path=/var/www/wordpress config set DB_USER     "$WP_DB_USER" --type=constant
  wp --allow-root --path=/var/www/wordpress config set DB_PASSWORD "$WP_DB_PWD"  --type=constant
  wp --allow-root --path=/var/www/wordpress config set DB_HOST     "$WP_DB_HOST" --type=constant
else
  wp --allow-root --path=/var/www/wordpress config create \
    --dbname="$WP_DB" \
    --dbuser="$WP_DB_USER" \
    --dbpass="$WP_DB_PWD" \
    --dbhost="$WP_DB_HOST" \
    --skip-check
  wp --allow-root --path=/var/www/wordpress config shuffle-salts
fi

if ! wp --allow-root --path=/var/www/wordpress core is-installed; then
wp --allow-root --path=/var/www/wordpress core install \
    --url="$DOMAIN" \
    --title="$WP_TITLE" \
    --admin_user="$WP_ADMIN_USER" \
    --admin_password="$WP_ADMIN_PWD" \
    --admin_email=$WP_ADMIN_MAIL \
    --skip-email \
    --allow-root --path=/var/www/wordpress
fi


wp --allow-root --path=/var/www/wordpress option update home "$WP_URL"
wp --allow-root --path=/var/www/wordpress option update siteurl "$WP_URL"

touch /var/www/wordpress/.bootstrapped

if ! wp --allow-root --path=/var/www/wordpress user get "$WP_USER" >/dev/null 2>&1; then
  wp --allow-root --path=/var/www/wordpress user create "$WP_USER" "$WP_MAIL" \
    --user_pass="$WP_USER_PWD" \
    --role=author
fi

if wp --allow-root --path=/var/www/wordpress core is-installed; then
  wp --allow-root --path=/var/www/wordpress theme install twentysixteen --activate || true
  wp --allow-root --path=/var/www/wordpress plugin redis-cache --activate || true
  wp --allow-root redis enable || true
  wp --allow-root --path=/var/www/wordpress plugin update --all || true
fi

sed -i 's|^listen\s*=.*|listen = 0.0.0.0:9000|' /etc/php/8.2/fpm/pool.d/www.conf
mkdir -p /run/php

chown -R www-data:www-data /var/www/wordpress

exec php-fpm8.2 -F
