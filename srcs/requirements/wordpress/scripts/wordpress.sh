#!/bin/sh
set -e

mkdir -p /var/www/wordpress
cd /var/www/wordpress

DB_HOST="${WP_DB_HOST%:*}"
DB_PORT="${WP_DB_HOST#*:}"
[ "$DB_HOST" = "$WP_DB_HOST" ] && DB_PORT=3306

WP_URL="${WP_PUBLIC_URL:-https://${DOMAIN}}"

: "${KC_REALM:?KC_REALM is not set}"
: "${KC_CLIENT_ID:?KC_CLIENT_ID is not set}"
: "${KC_CLIENT_SECRET:?KC_CLIENT_SECRET not set}"

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

if ! grep -q "WP_REDIS_HOST" /var/www/wordpress/wp-config.php; then
    wp --allow-root --path=/var/www/wordpress config set WP_REDIS_HOST redis --type=constant
    wp --allow-root --path=/var/www/wordpress config set WP_REDIS_PORT 6379 --type=constant --raw
fi

if ! grep -q "OIDC_CLIENT_ID" /var/www/wordpress/wp-config.php; then
    KC_ISSUER_BASE="https://${DOMAIN}/auth/realms/${KC_REALM}"
    KC_INTERNAL_BASE="http://keycloak:8080/auth/realms/${KC_REALM}"

    wp --allow-root --path=/var/www/wordpress config set OIDC_LOGIN_TYPE              "button"                                               --type=constant
    wp --allow-root --path=/var/www/wordpress config set OIDC_CLIENT_ID               "${KC_CLIENT_ID}"                                      --type=constant
    wp --allow-root --path=/var/www/wordpress config set OIDC_CLIENT_SECRET           "${KC_CLIENT_SECRET}"                                  --type=constant
    wp --allow-root --path=/var/www/wordpress config set OIDC_CLIENT_SCOPE            "openid email profile"                                 --type=constant
    wp --allow-root --path=/var/www/wordpress config set OIDC_ISSUER                  "${KC_ISSUER_BASE}"                                    --type=constant
    wp --allow-root --path=/var/www/wordpress config set OIDC_ENDPOINT_LOGIN_URL      "${KC_ISSUER_BASE}/protocol/openid-connect/auth"       --type=constant
    wp --allow-root --path=/var/www/wordpress config set OIDC_ENDPOINT_LOGOUT_URL     "${KC_ISSUER_BASE}/protocol/openid-connect/logout"     --type=constant
    wp --allow-root --path=/var/www/wordpress config set OIDC_ENDPOINT_TOKEN_URL      "${KC_INTERNAL_BASE}/protocol/openid-connect/token"    --type=constant
    wp --allow-root --path=/var/www/wordpress config set OIDC_ENDPOINT_USERINFO_URL   "${KC_INTERNAL_BASE}/protocol/openid-connect/userinfo" --type=constant
    wp --allow-root --path=/var/www/wordpress config set OIDC_ENDPOINT_JWKS_URL       "${KC_INTERNAL_BASE}/protocol/openid-connect/certs"    --type=constant

    wp --allow-root --path=/var/www/wordpress config set OIDC_LINK_EXISTING_USERS      1 --type=constant --raw
    wp --allow-root --path=/var/www/wordpress config set OIDC_CREATE_IF_DOES_NOT_EXIST 1 --type=constant --raw
    wp --allow-root --path=/var/www/wordpress config set OIDC_REDIRECT_ON_LOGOUT       1 --type=constant --raw
fi



if ! wp --allow-root --path=/var/www/wordpress core is-installed; then
    wp --allow-root --path=/var/www/wordpress core install \
        --url="$DOMAIN" \
        --title="$WP_TITLE" \
        --admin_user="$WP_ADMIN_USER" \
        --admin_password="$WP_ADMIN_PWD" \
        --admin_email="$WP_ADMIN_MAIL" \
        --skip-email
fi

if wp --allow-root --path=/var/www/wordpress core is-installed; then
    wp --allow-root --path=/var/www/wordpress option update home "$WP_URL" || true
    wp --allow-root --path=/var/www/wordpress option update siteurl "$WP_URL" || true
fi

if ! wp --allow-root --path=/var/www/wordpress user get "$WP_USER" >/dev/null 2>&1; then
    wp --allow-root --path=/var/www/wordpress user create "$WP_USER" "$WP_MAIL" \
        --user_pass="$WP_USER_PWD" \
        --role=author
fi

if wp --allow-root --path=/var/www/wordpress core is-installed; then
    if ! wp --allow-root --path=/var/www/wordpress theme is-installed twentysixteen; then
        wp --allow-root --path=/var/www/wordpress theme install twentysixteen --activate || true
    else
        wp --allow-root --path=/var/www/wordpress theme activate twentysixteen || true
    fi

    if ! wp --allow-root --path=/var/www/wordpress plugin is-installed redis-cache; then
        wp --allow-root --path=/var/www/wordpress plugin install redis-cache --activate || true
    else
        wp --allow-root --path=/var/www/wordpress plugin activate redis-cache || true
    fi

    if ! wp --allow-root --path=/var/www/wordpress plugin is-installed daggerhart-openid-connect-generic; then
        wp --allow-root --path=/var/www/wordpress plugin install daggerhart-openid-connect-generic --activate || true
    else
        wp --allow-root --path=/var/www/wordpress plugin activate daggerhart-openid-connect-generic || true
    fi
    wp --allow-root --path=/var/www/wordpress eval '
    $settings = get_option("openid_connect_generic_settings", array());
    $settings["allow_internal_idp"] = 1;
    update_option("openid_connect_generic_settings", $settings);
    '

    wp --allow-root --path=/var/www/wordpress redis enable 2>/dev/null || echo "Redis cache setup complete"
    wp --allow-root --path=/var/www/wordpress plugin update --all || true
fi

sed -i 's|^listen\s*=.*|listen = 0.0.0.0:9000|' /etc/php/8.2/fpm/pool.d/www.conf
mkdir -p /run/php
chown -R www-data:www-data /var/www/wordpress
exec php-fpm8.2 -F
