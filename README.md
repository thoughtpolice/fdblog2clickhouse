# Ingest FoundationDB Trace Logs into ClickHouse

This is a simple Python tool that ingests
[FoundationDB](https://www.foundationdb.org) Trace Logs (which contain rich
information about the server and its operating status) into
[ClickHouse](https://clickhouse.yandex) tables. The intention is that you run
this tool on every server in the database cluster, and have it forward trace
logs to ClickHouse when they get rotated internally by the `fdbserver` process.
Then, you can query the operational state of your FoundationDB cluster using
traditional OLAP SQL queries.

The tool is packaged as a Docker image and can be run easily on a database
host in the cluster, and supports ClickHouse HTTP authentication.

> **WARNING**: This code is very rough and may not work correctly or capture
> all the necessary trace information you need. No advanced schema management
> is provided (nor any schema compatibility guaranteed at this time). See the
> `TODO` information below. Patches to add columns and make the code more
> robust are welcome.

## Configure FoundationDB

The `foundtiondb.conf` file **MUST** be configured to emit trace logs in JSON,
not XML, format. This only exists in more recent versions (6.0+)

Add `trace_format = json` to your `[fdbserver]` section:

```
[fdbserver]
command = ...
...
logdir = /var/log/foundationdb
trace_format = json
```

Restart your server and now you'll be writing `.json` trace logs.

## Use the prebuilt Docker image

Start a demo ClickHouse server:

```
$ docker run -d --rm \
    --ulimit nofile=262144:262144 \
    -p 8123:8123 \
    --name clickhouse-server \
    yandex/clickhouse-server
```

Now, run the `trace-converter` container, while mounting
`/var/log/foundationdb` (from `foundationdb.conf`) into the container, so it
can watch the log files:

```
$ docker run -d --rm \
    --link clickhouse-server \
    -e CLICKHOUSE_ADDR=http://clickhouse-server:8123 \
    -e CLICKHOUSE_DB=testing \
    -e CLICKHOUSE_TABLE=cluster01 \
    -v /var/log/foundationdb:/logs \
    thoughtpolice/fdblog2clickhouse:latest
```

After a while, the trace converter will get notified when a log file is
rotated, ingest the logs, and `POST` them to the ClickHouse HTTP endpoint
specified by `CLICKHOUSE_ADDR`. Trace logs tend to contain thousands of entries
and are rotated semi-regularly, which is an ingestion pattern ClickHouse can
easily handle (rather than continuously buffering data in-memory).

The logs look something like this upon rotation:

```
creating schema... 200
watching logs in /logs
Setting up watches.
Watches established.
submitting trace file '/logs/trace.127.0.0.1.4500.1557761852.s7mRgR.22.json' to ClickHouse...
<class 'pandas.core.frame.DataFrame'>
RangeIndex: 25810 entries, 0 to 25809
Data columns (total 8 columns):
As            10 non-null object
ID            25810 non-null object
Locality      1 non-null object
Machine       25810 non-null object
Severity      25810 non-null int64
Transition    10 non-null object
Time          25810 non-null datetime64[ns]
Type          25810 non-null object
dtypes: datetime64[ns](1), int64(1), object(6)
memory usage: 1.6+ MB
None
200
```

You can also use the `CLICKHOUSE_USER` and `CLICKHOUSE_PASS` environment
variables to specify HTTP Basic Auth credentials for logging into an
authenticated ClickHouse HTTP endpoint.

If you pass `--delete-logs` as an argument to the container (not an environment
variable), then the script will delete rotated trace files, only if it can
submit the logs to ClickHouse successfully.

## Database schema

**NOTE**: The trace converter AUTOMATICALLY creates a table named
`CLICKHOUSE_TABLE` inside the database `CLICKHOUSE_DB` through an automatically
generated schema, and it will create both of these if they do not exist already
(`CREATE ... IF NOT EXISTS`). If you want to manage this schema yourself, you
can get it printed out for you:

```
$ docker run --rm \
    -e CLICKHOUSE_DB=testing \
    -e CLICKHOUSE_TABLE=cluster01 \
    thoughtpolice/fdblog2clickhouse:latest \
    --print-schema

CREATE TABLE IF NOT EXISTS `cluster01`
  ( `As`           Nullable(String)   COMMENT 'Lorem ipsum'        CODEC(NONE)
  , `ID`           String             COMMENT 'Lorem ipsum'        CODEC(NONE)
  , `Locality`     Nullable(String)   COMMENT 'Lorem ipsum'        CODEC(NONE)
  , `Machine`      String             COMMENT 'Lorem ipsum'        CODEC(NONE)
  , `Severity`     UInt32             COMMENT 'Event severity'     CODEC(NONE)
  , `Transition`   Nullable(String)   COMMENT 'Lorem ipsum'        CODEC(NONE)
  , `Time`         DateTime           COMMENT 'Event timestamp'    CODEC(NONE)
  , `Type`         String             COMMENT 'Event type'         CODEC(NONE)
  ) ENGINE = MergeTree()
    PARTITION BY
      toYYYYMM(Time)
    ORDER BY
      (Time)
    SETTINGS
      index_granularity=8192
```

The schema is auto-generated from an internal set of columns to look for. See
`columns` in `trace-converter.py` for more.

### Example queries

To be written.

## Internals

Some hacker notes.

### Building

`nix build -f default.nix` will do all the hard work. The `trace-converter`
attribute contains the included Python program and can be run from
`result/bin/trace-converter` with the same arguments/environment variables as
above.

To build a Docker image from the working copy and load it into the daemon:
`docker load < $(nix-build --no-link -QA docker)`

### Public Docker Hub Builds

New docker builds are published to the `:latest` tag on every commit to
`master` in this repository, built by the GitHub Actions available here. Look
under `.github/actions` and the `main.workflow` for more information. There are
also tags for each branch (e.g. a continuously updated `master` tag), but
`:master` is always the same as `:latest`.

There are also immutable images that are published to a fully identified,
unique version tag based on the git revision, e.g. the tag `:0.9preN_ABCDEF`,
indicating a docker image built from the `ABCDEF` git revision in this
repository (which has `N` commits of history, as of that revision).

If you want to use a stable, unchanging version of this tool, you should use a
tagged version of the Docker image with the git identifier embedded into it.

### How it works

FoundationDB internally manages trace logs, and each `fdbserver` rotates them
occasionally by syncing the current trace and creating a new log file. This
tool uses `inotifywait(1)` to trigger an action when a `CLOSE_WRITE` event is
received by `inotify` -- which occurs upon rotation of a trace file (when it is
closed and a new trace is created).

This trigger runs a Python program, which reads the JSON data into a [Pandas
DataFrame](https://pandas.pydata.org), trims/cleans it a bit (see `columns`
in `trace_converter.py`) and then POSTs records to ClickHouse, using the
HTTP endpoint with `JSONEachRow` format. It also does schema management and
creates a necessary ClickHouse table if needed.

As there is only a subset of column data currently available and sent to the
database, if you need more information from the trace files, it's recommended
to open a PR after adding the column information to `trace_converter.py`.

### Managing trace logging

ClickHouse, as a system, is designed to be written to using large, bulk writes
-- containing thousands or tens/hundreds of thousands of entries per `INSERT`
statement. While you can also submit many concurrent, bulk writes through many
clients, this is a baseline requirement for good performance -- ClickHouse suffers
from large performance/operational degredation with many (or even relatively few)
small `INSERT`s.

As a result, most systems buffer records in memory before sending off large, bulk
inserts to ClickHouse. FoundationDB trace logs, when truncated and rotated out
of use, normally fit in this ballpark (10s of thousands of entries per trace file.)
Therefore, the included code here is very simple -- it does not have to buffer
records at all, only batch process an entire set at once, POST them, and exit.
However, this does mean that the rate at which FoundationDB writes/rotates logs
in turn has an impact on your ingestion rates.

TODO: Write about some knobs (that probably exist somewhere) to tune trace log
flushing/rotations.

### TODO

If you want to improve this project or send patches, here are some ideas:

- [ ] Implement proper `CODEC`s for each column
  - Various types may benefit from different codec choices, e.g.
    `DELTA` vs `ZSTD`, though `ZSTD` seems like a solid default for
    most columns.
- [ ] Think about keeping fractional, sub-second resolution around for the
      `Time` column.
  - ClickHouse `DateTime` doesn't support sub-second resolution, as
    sub-second time components are "effectively random" which has
    large compression (and thus, performance) impacts. See
    [yandex/clickhouse#525](https://github.com/yandex/ClickHouse/issues/525)
    for more information.
- [ ] Implement some useful SQL queries to show off.
- [ ] Write buffer/trace tuning section.
- [ ] Implement support for many more column types in the trace logs,
      and test their usage
- [ ] Various Schema improvements
  - Plenty of ClickHouse features to leverage for better queries: dictionaries,
    IP types, various table/utility functions
  - Probably worth investigating `AggregatingMergeTree` or `SummingMergeTree`
    for various rollup tables.
  - Can likely create some useful `MATERIALIZED VIEW`s out of the 'raw' data
    table
- [ ] Think about replacing `inotifywait` with `pyinotify` or something.
  - Would be nice to have no operational difference between image and the
    ordinary python code, but probably a bit more complex.
- [ ] Look into trimming down the Docker image, somehow.

# License

Apache 2.0. See `LICENSE.txt` for details.
