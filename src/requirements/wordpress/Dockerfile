FROM debian:bullseye
RUN apt-get update -y && \
    apt-get install -y php7.4-fpm php7.4-mysql php7.4-redis mariadb-client curl
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x wp-cli.phar && \
    mv wp-cli.phar /usr/local/bin/wp
RUN mkdir -p /run/php
RUN rm -f /etc/php/7.4/fpm/pool.d/www.conf
COPY conf/www.conf /etc/php/7.4/fpm/pool.d/www.conf
COPY tools/init.sh /init.sh
RUN chmod +x /init.sh
EXPOSE 9000
ENTRYPOINT ["/init.sh"]