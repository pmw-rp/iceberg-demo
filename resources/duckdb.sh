#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

# Refresh the token

source ../config

## Get an access token
export TOKEN=$(curl -s http://localhost:8181/api/catalog/v1/oauth/tokens \
  --user root:pass \
  -H "Polaris-Realm: POLARIS" \
  -d grant_type=client_credentials \
  -d scope=PRINCIPAL_ROLE:ALL | jq -r .access_token)

# Configure the DuckDB init sql
export MINIO_ENDPOINT=local-minio.$MINIO_NAMESPACE.svc.cluster.local:9000
export POLARIS_ENDPOINT=http://polaris.$POLARIS_NAMESPACE.svc.cluster.local:8181/api/catalog
envsubst < resources/init.sql > resources/init-env.sql
kubectl cp -n $DUCKDB_NAMESPACE resources/init-env.sql duckdb:/root

# Check the number of arguments
if [ $# -eq 0 ]; then
   kubectl exec -it -n $DUCKDB_NAMESPACE duckdb -- /root/.duckdb/cli/$DUCKDB_VERSION/duckdb -init /root/init-env.sql

elif [ $# -eq 1 ]; then
    kubectl cp -n $DUCKDB_NAMESPACE $1 duckdb:/root
    kubectl exec -it -n $DUCKDB_NAMESPACE duckdb -- /root/.duckdb/cli/$DUCKDB_VERSION/duckdb -init /root/init-env.sql -f /root/$(basename "$1")

else
    echo "Error: Expected 0 or 1 arguments, but got $#"
    echo "Usage: $0 file.sql"
fi

popd