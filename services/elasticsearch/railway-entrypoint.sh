#!/bin/bash
# Railway mounts volumes owned by root, but Elasticsearch refuses to run as root.
# Fix ownership of the data volume, then drop to uid 1000 (the image's
# "elasticsearch" user, group 0) and hand over to the official entrypoint.
set -euo pipefail

ES_HOME=/usr/share/elasticsearch
DATA_DIR="$ES_HOME/data"

if [ "$(id -u)" = "0" ]; then
  mkdir -p "$DATA_DIR"
  rm -rf "$DATA_DIR/lost+found"
  if [ "$(stat -c %u "$DATA_DIR")" != "1000" ]; then
    echo "[railway-entrypoint] setting ownership of $DATA_DIR to 1000:0"
    chown -R 1000:0 "$DATA_DIR"
  fi
  export HOME="$ES_HOME"
  cd "$ES_HOME"
  # chroot to "/" with --skip-chdir only switches user/group (coreutils).
  exec chroot --userspec=1000:0 --skip-chdir / /usr/local/bin/docker-entrypoint.sh "$@"
fi

exec /usr/local/bin/docker-entrypoint.sh "$@"
