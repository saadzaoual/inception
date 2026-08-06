#!/bin/bash

# Go to the directory where the website files will live
cd /var/www/html

MYSQL_PASSWORD="$(cat /run/secrets/db_password)"
WP_ADMIN_PASSWORD="$(cat /run/secrets/wp_admin_password)"
WP_NORMAL_PASSWORD="$(cat /run/secrets/wp_user_password)"

# Active Waiting Loop: Wait for MariaDB to be fully ready
echo "Waiting for MariaDB connection..."
while ! mariadb -h mariadb -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "USE ${MYSQL_DATABASE};" >/dev/null 2>&1; do
    echo "MariaDB is not ready yet. Retrying in 3 seconds..."
    sleep 3
done
echo "MariaDB connection established!"

# Check if WordPress is already configured
if [ ! -f "wp-config.php" ]; then
    echo "Downloading and installing WordPress..."

    wp core download --allow-root

    wp config create \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${MYSQL_PASSWORD}" \
        --dbhost=mariadb:3306 \
        --allow-root

    wp core install \
        --url="${DOMAIN_NAME}" \
        --title="Inception 42" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --allow-root

    wp user create \
        "${WP_NORMAL_USER}" \
        "${WP_NORMAL_EMAIL}" \
        --role=author \
        --user_pass="${WP_NORMAL_PASSWORD}" \
        --allow-root
else
    echo "WordPress is already installed."
fi

# Ensure correct permissions
chown -R www-data:www-data /var/www/html

# Start PHP-FPM in the foreground
echo "Starting PHP-FPM..."
exec php-fpm7.4 -F
