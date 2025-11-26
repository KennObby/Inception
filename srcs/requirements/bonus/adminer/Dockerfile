FROM debian:bookworm

RUN apt-get update -y && apt-get install -y php php-mysql wget \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/www/adminer/ \
    && wget -O /var/www/adminer/index.php https://www.adminer.org/latest.php

EXPOSE 8080
CMD ["php", "-S", "0.0.0.0:8080", "-t", "/var/www/adminer"]
