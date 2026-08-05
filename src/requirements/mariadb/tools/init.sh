#!/bin/bash

# 1. Guarantee the mysql user actually owns the folder
chown -R mysql:mysql /var/lib/mysql

# 2. Check if the core system tables exist. If not, build them.
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "Installing MariaDB system tables..."
    mysql_install_db --user=mysql --datadir=/var/lib/mysql
fi

# 3. Start MariaDB in the background
mysqld_safe &

echo "Waiting for MariaDB to wake up..."
until mysqladmin ping >/dev/null 2>&1; do
    sleep 1
done

echo "MariaDB is online. Forcing configuration updates..."

# 4. Generate our SQL rules
cat << EOF > /tmp/init.sql
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS \`${MYSQL_USER}\`@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO \`${MYSQL_USER}\`@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF

# 5. THE MAGIC TRICK:
# Try to run the SQL without a password (works if the database is brand new).
# || If that fails, run it WITH the password (works if the database was already initialized).
mysql -u root < /tmp/init.sql 2>/dev/null || mysql -u root -p"${MYSQL_ROOT_PASSWORD}" < /tmp/init.sql

rm /tmp/init.sql

# 6. Shut down the background process securely
mysqladmin -u root -p"${MYSQL_ROOT_PASSWORD}" shutdown & pid=$!
wait $pid

# 7. Start in the foreground
echo "Starting MariaDB in the foreground..."
exec mysqld_safe