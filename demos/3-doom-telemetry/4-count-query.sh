SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

source ../../config

# Perform a query to see the breakdown of telemetry records by type
kubectl cp -n $DUCKDB_NAMESPACE query.sql duckdb:/root
kubectl exec -it -n $DUCKDB_NAMESPACE duckdb -- /root/.duckdb/cli/latest/duckdb -init /root/init-env.sql -f /root/query.sql

popd