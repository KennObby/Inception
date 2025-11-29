FROM debian:bookworm

RUN apt-get update -y && apt-get install -y redis-server \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /data && chown redis:redis /data

COPY ./conf/redis.conf /etc/redis/redis.conf

EXPOSE 6379

USER redis

CMD [ "redis-server", "/etc/redis/redis.conf" ]
