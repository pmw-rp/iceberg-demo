SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

source ./refresh-token.sh

kubectl cp -n $DUCKDB_NAMESPACE find-record.sql duckdb:/root
kubectl exec -it -n $DUCKDB_NAMESPACE duckdb -- /root/.duckdb/cli/$DUCKDB_VERSION/duckdb -init /root/init-env.sql -f /root/find-record.sql

popd
