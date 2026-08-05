FROM debian:bookworm

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends mariadb-server mariadb-client && \
    rm -rf /var/lib/apt/lists/*

# The package postinst seeds a data directory inside the image, which Docker
# then copies into the volume on first mount. Drop it so init.sh owns the whole
# bootstrap, and create the runtime directory mysqld needs for its socket.
RUN rm -rf /var/lib/mysql/* && \
    mkdir -p /run/mysqld /var/lib/mysql && \
    chown -R mysql:mysql /run/mysqld /var/lib/mysql

COPY conf/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf
COPY tools/init.sh /init.sh
RUN chmod +x /init.sh

EXPOSE 3306
ENTRYPOINT ["/init.sh"]