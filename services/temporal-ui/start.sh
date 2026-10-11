#!/bin/bash
# Starts Temporal UI on an internal port and Caddy (basic auth) on $PORT.
# Exits when either process stops so Railway's restart policy takes over.
set -euo pipefail

: "${TEMPORAL_UI_USERNAME:?TEMPORAL_UI_USERNAME must be set}"
: "${TEMPORAL_UI_PASSWORD:?TEMPORAL_UI_PASSWORD must be set}"

# Port the UI server listens on inside the container (read by its config template).
export TEMPORAL_UI_PORT="${TEMPORAL_UI_INTERNAL_PORT:-8081}"

TEMPORAL_UI_PASSWORD_HASH="$(caddy hash-password --plaintext "$TEMPORAL_UI_PASSWORD")"
export TEMPORAL_UI_PASSWORD_HASH
unset TEMPORAL_UI_PASSWORD

cd /home/ui-server
./start-ui-server.sh &
ui_pid=$!

caddy run --config /etc/railway/Caddyfile --adapter caddyfile &
caddy_pid=$!

shutdown() {
  kill -TERM "$ui_pid" "$caddy_pid" 2>/dev/null || true
}
trap shutdown TERM INT

set +e
wait -n "$ui_pid" "$caddy_pid"
status=$?
shutdown
wait
exit "$status"
