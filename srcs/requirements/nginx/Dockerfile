FROM debian:bookworm

RUN apt -y update \
    && apt install -y --no-install-recommends nginx openssl ca-certificates iputils-ping net-tools bind9-dnsutils netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/nginx/certs

COPY ./scripts/nginx.conf /etc/nginx/nginx.conf.template

COPY ./scripts/nginx.sh /nginx.sh
RUN chmod +x /nginx.sh


ENTRYPOINT ["/nginx.sh"]
