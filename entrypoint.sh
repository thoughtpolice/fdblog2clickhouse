#!/usr/bin/env bash

set -eo pipefail
[[ -n "${DEBUG}" ]] && set -x

LOG_DIR=${LOG_DIR:-/logs}

[[ -z "${CLICKHOUSE_DB}"    ]] && >&2 echo "ERROR: CLICKHOUSE_DB must be set!" && exit 1
[[ -z "${CLICKHOUSE_TABLE}" ]] && >&2 echo "ERROR: CLICKHOUSE_TABLE must be set!" && exit 1

[[ "$1" == "--print-schema" ]] && exec /bin/trace-convert --print-schema

[[ -z "${CLICKHOUSE_ADDR}"  ]] && >&2 echo "ERROR: CLICKHOUSE_ADDR must be set!" && exit 1
echo -n "creating schema... "
/bin/trace-convert --create-schema

echo "watching logs in ${LOG_DIR}"
while read line; do
  fname=$(echo "${line}" | awk '{print $3}')
  tracefile=$(echo "${line}" | awk '{print $1$3}')

  [[ -n "${WATCH_COMPLETION_FILE}" ]] && [[ "$fname" == "sim-completed" ]] && \
    echo "NOTE: found 'sim-completed' file; exiting..." && \
    exit 0

  [[ ${fname: -5} != ".json" ]] && continue
  echo "submitting trace file '${tracefile}' to ClickHouse..."
  /bin/trace-convert "$@" "${tracefile}"
done < <(inotifywait -m "${LOG_DIR}" -e close_write)
