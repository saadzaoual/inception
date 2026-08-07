FROM debian:bookworm
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends php8.2-fpm php8.2-mysql php-redis mariadb-client curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x wp-cli.phar && \
    mv wp-cli.phar /usr/local/bin/wp
RUN mkdir -p /run/php
RUN rm -f /etc/php/8.2/fpm/pool.d/www.conf
COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf
COPY tools/init.sh /init.sh
RUN chmod +x /init.sh
EXPOSE 9000
ENTRYPOINT ["/init.sh"]
