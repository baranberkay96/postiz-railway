#!/bin/sh
# Bootstrap for the Temporal server in the Postiz Railway template.
#
# Runs on every boot and is safe to re-run:
#   1. create the Temporal database in the shared Postgres and apply/upgrade its schema
#   2. apply the Elasticsearch visibility template/settings and create/upgrade the index
#   3. start temporal-server (official image entrypoint)
#   4. ensure the namespace and the search attributes Postiz queries (organizationId, postId)
#
# Railway starts all template services in parallel, so steps 1-2 wait for
# Postgres and Elasticsearch instead of relying on start order.
set -eu

log() { echo "[railway-entrypoint] $*"; }

for name in POSTGRES_SEEDS POSTGRES_USER POSTGRES_PWD ES_SEEDS ES_USER ES_PWD; do
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    log "ERROR: required variable $name is not set"
    exit 1
  fi
done

DB="${DB:-postgres12}"
DB_PORT="${DB_PORT:-5432}"
DBNAME="${DBNAME:-temporal}"
ES_SCHEME="${ES_SCHEME:-http}"
ES_PORT="${ES_PORT:-9200}"
ES_VIS_INDEX="${ES_VIS_INDEX:-temporal_visibility_v1}"
NAMESPACE="${DEFAULT_NAMESPACE:-default}"
RETENTION="${DEFAULT_NAMESPACE_RETENTION:-72h}"
WAIT_ATTEMPTS="${BOOTSTRAP_WAIT_ATTEMPTS:-60}"
FRONTEND_ADDR="127.0.0.1:${FRONTEND_GRPC_PORT:-7233}"
export DB DB_PORT DBNAME ES_SCHEME ES_PORT ES_VIS_INDEX
export TEMPORAL_ALLOW_NO_AUTH="${TEMPORAL_ALLOW_NO_AUTH:-true}"

server_pid=""

# retry <attempts> <command...>: re-run a command every 5s until it succeeds.
retry() {
  attempts="$1"
  shift
  n=1
  until "$@"; do
    if [ -n "$server_pid" ] && ! kill -0 "$server_pid" 2>/dev/null; then
      log "ERROR: temporal-server exited during bootstrap"
      exit 1
    fi
    if [ "$n" -ge "$attempts" ]; then
      log "ERROR: giving up after $n attempts: $*"
      return 1
    fi
    log "not ready yet (attempt $n/$attempts): $*; retrying in 5s"
    n=$((n + 1))
    sleep 5
  done
}

# --- 1. SQL persistence (database "$DBNAME" inside the shared Postgres) ---------
export SQL_PASSWORD="$POSTGRES_PWD"
sql() {
  temporal-sql-tool --plugin "$DB" --ep "$POSTGRES_SEEDS" -p "$DB_PORT" \
    -u "$POSTGRES_USER" --db "$DBNAME" "$@"
}
log "Preparing Postgres database '$DBNAME' on $POSTGRES_SEEDS:$DB_PORT"
retry "$WAIT_ATTEMPTS" sql create
sql setup-schema -v 0.0
sql update-schema -d /etc/temporal/schema/postgresql/v12/temporal/versioned
unset SQL_PASSWORD

# --- 2. Elasticsearch visibility store --------------------------------------
es() {
  temporal-elasticsearch-tool --endpoint "$ES_SCHEME://$ES_SEEDS:$ES_PORT" \
    --user "$ES_USER" --password "$ES_PWD" "$@"
}
log "Preparing Elasticsearch visibility index '$ES_VIS_INDEX' on $ES_SEEDS:$ES_PORT"
retry "$WAIT_ATTEMPTS" es ping
es setup-schema
es create-index --index "$ES_VIS_INDEX"
es update-schema --index "$ES_VIS_INDEX"

# --- 3. Temporal server -------------------------------------------------------
log "Starting temporal-server"
/etc/temporal/entrypoint.sh &
server_pid=$!
trap 'kill -TERM "$server_pid" 2>/dev/null || true' TERM INT

# --- 4. Namespace and Postiz search attributes -----------------------------------
ensure_namespace() {
  if temporal operator namespace describe --address "$FRONTEND_ADDR" \
      --namespace "$NAMESPACE" >/dev/null 2>&1; then
    return 0
  fi
  temporal operator namespace create --address "$FRONTEND_ADDR" \
    --namespace "$NAMESPACE" --retention "$RETENTION"
}

ensure_search_attributes() {
  existing="$(temporal operator search-attribute list --address "$FRONTEND_ADDR" \
    --namespace "$NAMESPACE" 2>/dev/null)" || return 1
  for attribute in organizationId postId; do
    if printf '%s\n' "$existing" | grep -qw "$attribute"; then
      continue
    fi
    temporal operator search-attribute create --address "$FRONTEND_ADDR" \
      --namespace "$NAMESPACE" --name "$attribute" --type Text || return 1
  done
}

if retry "$WAIT_ATTEMPTS" temporal operator cluster health --address "$FRONTEND_ADDR" \
  && retry 12 ensure_namespace \
  && retry 12 ensure_search_attributes; then
  log "Bootstrap complete: namespace '$NAMESPACE' is ready"
else
  log "ERROR: post-start bootstrap failed; stopping so Railway restarts the service"
  kill -TERM "$server_pid" 2>/dev/null || true
  wait "$server_pid" || true
  exit 1
fi

set +e
wait "$server_pid"
status=$?
if [ "$status" -gt 128 ]; then
  # Interrupted by a signal: wait for the server to finish shutting down.
  wait "$server_pid"
  status=$?
fi
exit "$status"
