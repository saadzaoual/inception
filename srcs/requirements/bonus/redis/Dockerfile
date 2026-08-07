FROM debian:bookworm

RUN apt-get update -yqq && \
	apt-get install -y --no-install-recommends redis-server && \
	rm -rf /var/lib/apt/lists/*

COPY conf/redis.conf /etc/redis/redis.conf

EXPOSE 6379

# Exec form, foreground server, no wrapper script and nothing backgrounded:
# redis-server itself is PID 1.
ENTRYPOINT ["redis-server", "/etc/redis/redis.conf"]
