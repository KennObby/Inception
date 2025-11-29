FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y \
    && apt-get install -y curl ca-certificates openjdk-17-jre-headless bash \
    && rm -rf /var/apt/lists/*

ENV KC_VERSION=26.4.2
ENV KC_HOME=/opt/keycloak

RUN mkdir -p /opt \
    && curl -L "https://github.com/keycloak/keycloak/releases/download/${KC_VERSION}/keycloak-${KC_VERSION}.tar.gz" \
        -o /tmp/keycloak.tar.gz \
    && tar -xzf /tmp/keycloak.tar.gz -C /opt \
    && mv /opt/keycloak-${KC_VERSION} ${KC_HOME} \
    && rm -rf /tmp/keycloak.tar.gz

WORKDIR ${KC_HOME}

RUN bash ${KC_HOME}/bin/kc.sh build

EXPOSE 8080

COPY ./scripts/keycloak.sh /keycloak.sh
RUN chmod +x /keycloak.sh

ENTRYPOINT [ "/keycloak.sh" ]
