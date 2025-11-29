#!/bin/sh

set -e

DATADIR=/var/lib/mysql
SOCK=/run/mysqld/mysqld.sock


mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld

if [ ! -d "$DATADIR/mysql" ]; then
    echo "Initializing MariaDB data dir..."
    mariadb-install-db --user=mysql --datadir="$DATADIR" --skip-test-db > /dev/null
fi

mariadbd --user=mysql --datadir="$DATADIR" --socket="$SOCK" --skip-networking=0 &
pid=$!

echo -n "Waiting for temporary MariaDB to accept connections..."
until mariadb-admin --protocol=socket --socket="$SOCK" ping >/dev/null 2>&1; do
    sleep 1
done
echo " up."

    mariadb --protocol=socket --socket="$SOCK" -uroot <<SQL
CREATE DATABASE IF NOT EXISTS \`${MARIADB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${MARIADB_USER}'@'%' IDENTIFIED BY '${MARIADB_PWD}';
GRANT ALL PRIVILEGES ON \`${MARIADB_NAME}\`.* TO '${MARIADB_USER}'@'%';

CREATE DATABASE IF NOT EXISTS \`${KC_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${KC_DB_USER}'@'%' IDENTIFIED BY '${KC_DB_PWD}';
GRANT ALL PRIVILEGES ON \`${KC_NAME}\`.* TO '${KC_DB_USER}'@'%';

FLUSH PRIVILEGES;
SQL

mariadb-admin --protocol=socket --socket="$SOCK" -uroot shutdown
wait "$pid" || true

exec mariadbd --user=mysql --datadir="$DATADIR" --console
