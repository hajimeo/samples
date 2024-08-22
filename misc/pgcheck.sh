#!/bin/bash
# From https://cloud.google.com/blog/products/databases/using-haproxy-to-scale-read-only-workloads-on-cloud-sql-for-postgresql
# TODO: doesn't look like a good script

## Begin configuration block

PG_PSQL_CMD="/usr/bin/env psql"

# Provide the username, database, and password for the health check user
PG_CONN_USER="enter health check username here"
PG_CONN_DB="template1"
PG_CONN_PASSWORD="enter health check user password here"

## End configuration block

PG_CONN_HOST=$3
PG_CONN_PORT=$4

export PGPASSWORD=$PG_CONN_PASSWORD

PG_NODE_RESPONSE="$($PG_PSQL_CMD -t -A -d $PG_CONN_DB -U $PG_CONN_USER -h $PG_CONN_HOST -p $PG_CONN_PORT -c 'select 1')"

if [ "$PG_NODE_RESPONSE" == "1" ]; then
	echo 'Health check succeeded'
	exit 0
else
	echo 'Health check failed'
	exit 1
fi