SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

source ../../config

# Perform a query to retrieve some data
kubectl cp -n $DUCKDB_NAMESPACE describe.sql duckdb:/root
kubectl exec -it -n $DUCKDB_NAMESPACE duckdb -- /root/.duckdb/cli/$DUCKDB_VERSION/duckdb -init /root/init-env.sql -f /root/describe.sql

popd