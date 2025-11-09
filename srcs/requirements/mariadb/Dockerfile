FROM debian:bookworm

RUN apt update -y && apt install mariadb-server -y

COPY ./scripts/50-server.cnf /etc/mysql/mariadb.conf.d/

COPY ./scripts/mariadb.sh /

ENTRYPOINT ["sh", "/mariadb.sh"]
