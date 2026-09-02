#!/bin/sh
set -e

#DB .env variables CHECKER
: "${KC_DB:=mariadb}"
: "${KC_DB_USERNAME:?KC_DB_USER not set}"
: "${KC_DB_PASSWORD:?KC_DB_PWD not set}"
: "${KC_DB_URL_HOST:=mariadb}"
: "${KC_DB_URL_PORT:=3306}"
: "${KC_DB_URL_DATABASE:=keycloak}"
: "${KEYCLOAK_ADMIN:?KC_ADMIN not set}"
: "${KEYCLOAK_ADMIN_PASSWORD:?KEYCLOAK_ADMIN_PWD not set}"
: "${DOMAIN:?Domain not set}"

#REALM .env variables CHECKER
: "${KC_REALM:=inception}"
: "${KC_CLIENT_ID:=wordpress}"
: "${KC_CLIENT_SECRET:?KC_CLIENT_SECRET not set}"
: "${KC_TEST_USER:=member}"
: "${KC_TEST_USER_PWD:?KC_TEST_USER_PWD not set}"
: "${KC_TEST_USER_EMAIL:?KC_TEST_USER_EMAIL}"

KC_HOME=/opt/keycloak
KC_EXEC="${KC_HOME}/bin/kc.sh"
KCADM="${KC_HOME}/bin/kcadm.sh"

DB_URL="jdbc:mariadb://${KC_DB_URL_HOST}:${KC_DB_URL_PORT}/${KC_DB_URL_DATABASE}"

KC_PUBLIC_URL="https://${DOMAIN}/auth"

exec ${KC_EXEC} start \
  --db=${KC_DB} \
  --db-url=${DB_URL} \
  --db-username=${KC_DB_USERNAME} \
  --db-password=${KC_DB_PASSWORD} \
  --hostname="${KC_PUBLIC_URL}" \
  --http-enabled=true \
  --http-port=8080 \
  --http-relative-path=/auth \
  --proxy-headers=xforwarded &

KC_PID=$!
trap 'kill -TERM "$KC_PID" 2>/dev/null; wait "$KC_PID"' TERM INT 

echo -n "Waiting for Keycloak to accept connections..."
until curl -sf "http://localhost:8080/auth/realms/master" >/dev/null 2>&1; do 
    sleep 2
done
echo "up."

"${KCADM}" config credentials \
    --server http://localhost:8080/auth \
    --realm master \
    --user "${KEYCLOAK_ADMIN}" \
    --password "${KEYCLOAK_ADMIN_PASSWORD}"

#REALM config

if ! "${KCADM}" get "realms/${KC_REALM}" > /dev/null 2>&1; then
    echo "Creating realm '${KC_REALM}'..."
    "${KCADM}" create realms -s realm="${KC_REALM}" -s enabled=true
else
    echo "Realm '${KC_REALM}' already exists."
fi

#CLIENT (confidential, Authorization Code flow)
CLIENT_UUID=$("${KCADM}" get clients -r "${KC_REALM}" -q clientId="${KC_CLIENT_ID}" | jq -r '.[0].id // empty')

if [ -z "${CLIENT_UUID}" ]; then
    echo "Creating client '$KC_CLIENT_ID'..."
    "${KCADM}" create clients -r "${KC_REALM}" \
        -s clientId="${KC_CLIENT_ID}" \
        -s enabled=true \
        -s protocol=openid-connect \
        -s publicClient=false \
        -s standardFlowEnabled=true \
        -s directAccessGrantsEnabled=false \
        -s serviceAccountsEnabled=false \
        -s secret="${KC_CLIENT_SECRET}" \
        -s "redirectUris=[\"https://${DOMAIN}/*\"]" \
        -s "webOrigins=[\"https://${DOMAIN}\"]"

else
    echo "Client '${KC_CLIENT_ID}' already exists, syncing config..."
    "${KCADM}" update "clients/${CLIENT_UUID}" -r "${KC_REALM}" \
        -s secret="${KC_CLIENT_SECRET}" \
        -s "redirectUris=[\"https://${DOMAIN}/*\"]" \
        -s "webOrigins=[\"https://${DOMAIN}\"]"

fi

#TEST ADMIN USER
USER_ID=$("${KCADM}" get users -r "${KC_REALM}" -q username="${KC_TEST_USER}" | jq -r '.[0].id // empty')

if [ -z "${USER_ID}" ]; then
    echo "Creating test user '${KC_TEST_USER}'..."
    "${KCADM}" create users -r "${KC_REALM}" \
        -s username="${KC_TEST_USER}" \
        -s email="${KC_TEST_USER_EMAIL}" \
        -s enabled=true \
        -s emailVerified=true
    "${KCADM}" set-password -r "${KC_REALM}" \
        --username "${KC_TEST_USER}" \
        --new-password "${KC_TEST_USER_PWD}" \
        --temporary=false

else
    echo "Test user '${KC_TEST_USER}' already exists."

fi

echo "Keycloak provisioning complete: realm=${KC_REALM} client=${KC_CLIENT_ID}"

wait "$KC_PID"
