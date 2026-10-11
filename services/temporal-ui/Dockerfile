# Temporal Web UI behind HTTP basic auth (Postiz Railway template).
#
# Temporal UI has no built-in password login (only OIDC), so Caddy runs in the
# same container on $PORT (public) with basic_auth and proxies to the UI server
# on an internal port. /healthz is left open for the Railway healthcheck.

FROM caddy:2.11.7-alpine AS caddy
# Plain copy drops the image's file capability (not needed for an unprivileged port).
RUN cp /usr/bin/caddy /usr/local/bin/caddy-plain

FROM temporalio/ui:2.55.0

COPY --from=caddy /usr/local/bin/caddy-plain /usr/local/bin/caddy
COPY Caddyfile /etc/railway/Caddyfile
COPY --chmod=0755 start.sh /etc/railway/start.sh

ENV XDG_CONFIG_HOME=/tmp/caddy/config \
    XDG_DATA_HOME=/tmp/caddy/data

ENTRYPOINT ["/etc/railway/start.sh"]
