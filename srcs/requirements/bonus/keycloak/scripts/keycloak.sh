#!/bin/sh
set -e

: "${KC_DB:=mariadb}"
: "${KC_DB_USERNAME:?KC_DB_USER not set}"
: "${KC_DB_PASSWORD:?KC_DB_PWD not set}"
: "${KC_DB_URL_HOST:=mariadb}"
: "${KC_DB_URL_PORT:=3306}"
: "${KC_DB_URL_DATABASE:=keycloak}"
: "${KEYCLOAK_ADMIN:?KC_ADMIN not set}"
: "${KEYCLOAK_ADMIN_PASSWORD:?KEYCLOAK_ADMIN_PWD not set}"

KC_HOME=/opt/keycloak

DB_URL="jdbc:mariadb://${KC_DB_URL_HOST}:${KC_DB_URL_PORT}/${KC_DB_URL_DATABASE}"

KC_EXEC="${KC_HOME}/bin/kc.sh"

exec ${KC_EXEC} start \
  --db=${KC_DB} \
  --db-url=${DB_URL} \
  --db-username=${KC_DB_USERNAME} \
  --db-password=${KC_DB_PASSWORD} \
  --hostname-strict=false \
  --hostname="${DOMAIN:-oilyine.42.lu}" \
  --proxy-headers=xforwarded \
  --http-enabled=true \
  --http-port=8080
