#!/usr/bin/env bash

set -eo pipefail
[[ -n "${DEBUG}" ]] && set -x

LOG_DIR=${LOG_DIR:-/data/logs}

[[ -z "${CLICKHOUSE_DB}"    ]] && >&2 echo "ERROR: CLICKHOUSE_DB must be set!" && exit 1
[[ -z "${CLICKHOUSE_TABLE}" ]] && >&2 echo "ERROR: CLICKHOUSE_TABLE must be set!" && exit 1

[[ "$1" == "--print-schema" ]] && exec /bin/trace-convert --print-schema

[[ -z "${CLICKHOUSE_ADDR}"  ]] && >&2 echo "ERROR: CLICKHOUSE_ADDR must be set!" && exit 1
echo -n "creating schema... "
/bin/trace-convert --create-schema

echo "watching logs in ${LOG_DIR}"
while read line; do
  tracefile=$(echo "${line}" | awk '{print $1$3}')
  echo "submitting trace file '${tracefile}' to ClickHouse..."
  /bin/trace-convert "$@" "${tracefile}"
done < <(inotifywait -m "${LOG_DIR}" -e close_write)
