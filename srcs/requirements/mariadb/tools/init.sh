#!/bin/bash
set -eu

# Read credentials from Docker secrets instead of environment variables
MYSQL_ROOT_PASSWORD="$(cat /run/secrets/db_root_password)"
MYSQL_PASSWORD="$(cat /run/secrets/db_password)"

SOCKET=/run/mysqld/mysqld.sock

# mysqld creates its socket and pid file here; the directory is not shipped by
# the package, so without this the server dies before it can accept a client.
mkdir -p /run/mysqld
chown mysql:mysql /run/mysqld

# Guarantee the mysql user actually owns the data directory
chown -R mysql:mysql /var/lib/mysql

# Run root SQL through whichever credentials the datadir currently has: a fresh
# install authenticates root over the socket, an already-configured one wants
# the password. The probe is silent, the real command is not, so a genuine SQL
# error still reaches the logs and trips set -e.
run_root_sql() {
    if mariadb --socket="$SOCKET" -u root -e "SELECT 1" >/dev/null 2>&1; then
        mariadb --socket="$SOCKET" -u root
    else
        mariadb --socket="$SOCKET" -u root -p"${MYSQL_ROOT_PASSWORD}"
    fi
}

# Keyed on the application database, not on the system tables: if setup dies
# half way through, the next start retries it instead of skipping forever.
if [ ! -d "/var/lib/mysql/${MYSQL_DATABASE}" ]; then

    if [ ! -d "/var/lib/mysql/mysql" ]; then
        echo "[mariadb] Empty data directory, installing system tables..."
        mysql_install_db --user=mysql --datadir=/var/lib/mysql --skip-test-db
    fi

    echo "[mariadb] Starting temporary server for setup..."
    mysqld --user=mysql --skip-networking --socket="$SOCKET" &
    pid=$!

    echo "[mariadb] Waiting for the temporary server..."
    for _ in $(seq 1 30); do
        mariadb-admin --socket="$SOCKET" ping >/dev/null 2>&1 && break
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "[mariadb] Temporary server died during startup." >&2
            exit 1
        fi
        sleep 1
    done

    echo "[mariadb] Creating database, user and root password..."
    run_root_sql <<EOF
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF

    echo "[mariadb] Stopping the temporary server..."
    mariadb-admin --socket="$SOCKET" -u root -p"${MYSQL_ROOT_PASSWORD}" shutdown || kill "$pid"
    wait "$pid" || true

    echo "[mariadb] Setup complete."
else
    echo "[mariadb] Database '${MYSQL_DATABASE}' already present, skipping setup."
fi

# Start the real server in the foreground as PID 1
echo "[mariadb] Starting MariaDB in the foreground..."
exec mysqld --user=mysql