SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

source ./refresh-token.sh

# Get the pre-delete snapshot ID (second most recent by sequence number)
export SNAPSHOT_ID=$(kubectl exec -n $DUCKDB_NAMESPACE duckdb -- \
  /root/.duckdb/cli/$DUCKDB_VERSION/duckdb -init /root/init-env.sql \
  -csv -noheader -c \
  "SELECT snapshot_id FROM iceberg_snapshots(iceberg_catalog.redpanda.syslog) ORDER BY sequence_number DESC LIMIT 1 OFFSET 1;" \
  2>/dev/null | tr -d '[:space:]')

echo "Travelling to snapshot: $SNAPSHOT_ID"

envsubst < time-travel.sql > /tmp/time-travel-env.sql
kubectl cp -n $DUCKDB_NAMESPACE /tmp/time-travel-env.sql duckdb:/root/time-travel-env.sql
kubectl exec -it -n $DUCKDB_NAMESPACE duckdb -- /root/.duckdb/cli/$DUCKDB_VERSION/duckdb -init /root/init-env.sql -f /root/time-travel-env.sql

popd
