#!/bin/bash
set -e

mkdir -p /run/mysqld
chown mysql:mysql /run/mysqld

if [ ! -d /var/lib/mysql/mysql ]; then
	mysql_install_db --user=mysql --datadir=/var/lib/mysql
fi

# Provisioning runs via --init-file, which mariadbd executes after the server
# is up and the grant tables are live. --bootstrap cannot be used here: it
# implies --skip-grant-tables, which rejects CREATE USER / GRANT with error 1290.
#
# The file lives in /run (container-local, wiped with the container) and never
# in /var/lib/mysql, which is bind-mounted to the host: the passwords must not
# be written to the host filesystem.
#
# Every statement is idempotent, so this is safe to re-run on each start and
# repairs a half-provisioned database instead of skipping it forever.
INIT_SQL=/run/mysqld/init.sql
umask 077
cat > "$INIT_SQL" <<-EOF
	CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
	CREATE USER IF NOT EXISTS \`${MYSQL_USER}\`@'%' IDENTIFIED BY '$(cat /run/secrets/db_password)';
	GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO \`${MYSQL_USER}\`@'%';
	ALTER USER 'root'@'localhost' IDENTIFIED BY '$(cat /run/secrets/db_root_password)';
	DELETE FROM mysql.global_priv WHERE User='';
	FLUSH PRIVILEGES;
EOF
chown mysql:mysql "$INIT_SQL"

exec mariadbd --datadir=/var/lib/mysql --user=mysql --init-file="$INIT_SQL"
