#! /usr/bin/env python3

import sys, os, requests
from urllib.parse import urlparse

import pandas as pd
from pandas import np

## creates a POST request to a ClickHouse HTTP endpoint.
## kwargs is intended to contain e.g. json=... or data=...
def clickhouse_post(**kwargs):
    auth = None
    if 'CLICKHOUSE_USER' in os.environ and 'CLICKHOUSE_PASS' in os.environ:
        auth = (os.environ['CLICKHOUSE_USER'], os.environ['CLICKHOUSE_PASS'])

    url = urlparse(os.environ['CLICKHOUSE_ADDR'])
    return requests.post(url.geturl(), auth=auth, **kwargs)

## return the ClickHouse schema for some set of columns as a string
def clickhouse_schema(columns):
    # options
    index_granularity = 8192
    partition_col = 'toYYYYMM(Time)'
    order_by = [ 'Time' ]

    ## generate the actual table schema
    table = os.environ['CLICKHOUSE_TABLE']
    cols = ""
    first = True
    for c in columns.keys():
        ccols = columns[c]

        cname = "`" + c + "`"
        typ = ccols[0]
        codec = ccols[1]
        comment = "'" + ccols[2] + "'"

        if first:
            first = False
            fmt = "  ( {:<14} {:<18} COMMENT {:<20} {}"
        else:
            fmt = "\n  , {:<14} {:<18} COMMENT {:<20} {}"

        cols = cols + fmt.format(cname, typ, comment, codec)

    return f"""CREATE TABLE IF NOT EXISTS `{table}`
{cols}
  ) ENGINE = MergeTree()
    PARTITION BY
      {partition_col}
    ORDER BY
      (Time)
    SETTINGS
      index_granularity={index_granularity}"""

## create the ClickHouse schema in the database by creating
## a CREATE TABLE request via HTTP POST
def create_schema(schema):
    db = os.environ['CLICKHOUSE_DB']
    clickhouse_post(data='CREATE DATABASE IF NOT EXISTS {}'.format(db))
    return clickhouse_post(data=schema, params={ 'database': db })

## inserts a single DataFrame into ClickHouse by emitting it in JSONEachRow format.
## it's expected that the dataframe is already 'trimmed' to only contain valid columns
## in the schema
def insert_trace(df):
    params = {
        'database': os.environ['CLICKHOUSE_DB'],
        'query': 'INSERT INTO {} FORMAT JSONEachRow'.format(os.environ['CLICKHOUSE_TABLE']),
    }
    blob = df.to_json(orient='records', lines=True)
    return clickhouse_post(data=blob, params=params)

def check_envvar(x):
    if not x in os.environ:
        print('Please set {}'.format(x))
        sys.exit(1)

def main(argv):
    # check environment variables
    for x in [ 'CLICKHOUSE_DB', 'CLICKHOUSE_TABLE' ]:
        check_envvar(x)

    # these are the only columns we're interested in
    columns = {
        'Severity'   : [           'UInt32', 'CODEC(Delta, ZSTD)', 'Event Severity Code' ],
        'Machine'    : [           'String', 'CODEC(ZSTD)',        'Machine ID for Event' ],
        'LogGroup'   : [           'String', 'CODEC(ZSTD)',        'Group for Event Type' ],
        'Time'       : [         'DateTime', 'CODEC(ZSTD)',        'Event Timestamp' ],
        'Type'       : [           'String', 'CODEC(ZSTD)',        'Event Type' ],

        'ID'         : [ 'Nullable(String)', 'CODEC(ZSTD)',        'Event Identifier' ],
    }

    f = argv[1]
    schema = clickhouse_schema(columns)
    if f == "--print-schema":
        print(schema)
        sys.exit(0)

    # we need this if we get past this point
    check_envvar('CLICKHOUSE_ADDR')

    if f == "--create-schema":
        r = create_schema(schema)
        print(r.status_code)
        sys.exit(0)

    delete_logs = False
    if f == "--delete-logs":
        f = argv[2]
        delete_logs = True

    # parse, slice relevant cols
    data = pd.read_json(f, lines=True)
    data = data[columns.keys()] # no usecols= param??

    # munge some types
    data['Time'] = data['Time'].astype(int)

    # print info
    print(data.info())
    r = insert_trace(data)
    print(r.status_code)

    if r.status_code != 200:
        print('ERROR: {}'.format(r.content))
    else:
        if delete_logs:
            os.remove(f)

    sys.exit(0)

if __name__ == '__main__':
    main(sys.argv)
