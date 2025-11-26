FROM debian:bookworm

RUN apt-get update -y \
    && apt-get install -y vsftpd openssl \
    && rm -rf /var/www/apt/lists/*

COPY ./conf/vsftpd.conf /etc/vsftpd.conf
COPY ./scripts/ftp.sh /ftp.sh
RUN chmod +x /ftp.sh

EXPOSE 21 21000-21010
ENTRYPOINT [ "/ftp.sh" ]
