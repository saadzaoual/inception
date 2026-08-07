#!/bin/bash
set -e

mkdir -p /run/mysqld
chown mysql:mysql /run/mysqld

if [ ! -d /var/lib/mysql/mysql ]; then
	mysql_install_db --user=mysql --datadir=/var/lib/mysql

	# --bootstrap reads SQL from stdin, applies it, then exits.
	# Nothing runs in the background and there is nothing to wait for.
	mariadbd --user=mysql --datadir=/var/lib/mysql --bootstrap <<-EOF
		USE mysql;
		CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
		CREATE USER IF NOT EXISTS \`${MYSQL_USER}\`@'%' IDENTIFIED BY '$(cat /run/secrets/db_password)';
		GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO \`${MYSQL_USER}\`@'%';
		DELETE FROM mysql.user WHERE User='';
		ALTER USER 'root'@'localhost' IDENTIFIED BY '$(cat /run/secrets/db_root_password)';
		FLUSH PRIVILEGES;
	EOF
fi

exec mariadbd --datadir=/var/lib/mysql --user=mysql
