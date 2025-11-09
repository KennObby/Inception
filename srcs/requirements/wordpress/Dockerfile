FROM debian:bookworm

RUN apt update -y

RUN apt install php-fpm php-mysql php-cli unzip curl -y

RUN apt install mariadb-client ca-certificates -y

EXPOSE 9000

COPY ./scripts/wordpress.sh /

ENTRYPOINT [ "sh", "/wordpress.sh" ]
