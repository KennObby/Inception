#!/bin/sh
set -e

: "${DOMAIN:=localhost}"
CERT_DIR="/etc/nginx/certs"
KEY="${CERT_DIR}/${DOMAIN}.key"
CRT="${CERT_DIR}/${DOMAIN}.crt"

mkdir -p "$CERT_DIR"

if [ ! -f "$KEY" ] || [ ! -f "$CRT" ]; then
  echo "Generating self-signed certificate for ${DOMAIN}…"

  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$KEY" \
    -out "$CRT" \
    -days 365 \
    -subj "/C=LU/ST=Luxembourg/L=Luxembourg/O=Inception/OU=Dev/CN=${DOMAIN}" \
    -addext "subjectAltName=DNS:${DOMAIN},DNS:www.${DOMAIN} "\
    -addext "keyUsage=digitalSignature,keyEncipherment" \
    -addext "extendedKeyUsage=serverAuth"
  
  chmod 600 "$KEY"
fi

sed "s/\\\$DOMAIN/${DOMAIN}/g" /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

nginx -t
exec nginx -g "daemon off;"
