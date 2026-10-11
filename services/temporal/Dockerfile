# Temporal server for the Postiz Railway template.
#
# temporalio/auto-setup is no longer published after 1.29.x, and the plain
# temporalio/server image ships neither the schema tools nor a dynamic config
# file (the server refuses to start without one). This image adds both, taken
# from the matching temporalio/admin-tools release, plus an idempotent bootstrap
# entrypoint (schema setup/upgrade, visibility index, namespace, search attributes).
#
# Upgrade: bump BOTH tags together, one minor version at a time (Temporal does
# not support skipping minor versions). The entrypoint applies schema upgrades.

FROM temporalio/admin-tools:1.32.1 AS admin-tools

FROM temporalio/server:1.32.1

COPY --from=admin-tools /usr/local/bin/temporal /usr/local/bin/temporal-sql-tool /usr/local/bin/temporal-elasticsearch-tool /usr/local/bin/
COPY --from=admin-tools /etc/temporal/schema /etc/temporal/schema
COPY dynamicconfig/railway.yaml /etc/temporal/config/dynamicconfig/railway.yaml
COPY --chmod=0755 railway-entrypoint.sh /etc/temporal/railway-entrypoint.sh

ENV DYNAMIC_CONFIG_FILE_PATH=/etc/temporal/config/dynamicconfig/railway.yaml

CMD ["/etc/temporal/railway-entrypoint.sh"]
