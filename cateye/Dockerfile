ARG CATEYE_VERSION
FROM docker.io/heyjude77/cateye:v${CATEYE_VERSION}

LABEL \
  io.hass.type="app" \
  io.hass.arch="aarch64|amd64"

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/nginx

COPY run.sh /run.sh
COPY client.toml /client.toml
COPY ingress.conf.template /ingress.conf.template

RUN chmod 755 /run.sh

ENTRYPOINT ["/run.sh"]
