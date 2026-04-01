#!/usr/bin/env bash
# Ensure the Polaris port-forward is running, refresh the token, and update init-env.sql in the DuckDB pod.
# Source this file — do not execute it directly.

source "$(dirname "${BASH_SOURCE[0]}")/../../config"

# Start Polaris port-forward if not already listening on 8181
if ! lsof -i tcp:8181 -sTCP:LISTEN -t &>/dev/null; then
  kubectl port-forward svc/polaris -n $POLARIS_NAMESPACE 8181:8181 &
  for i in $(seq 1 20); do
    lsof -i tcp:8181 -sTCP:LISTEN -t &>/dev/null && break
    sleep 1
  done
fi

export TOKEN=$(curl -s http://localhost:8181/api/catalog/v1/oauth/tokens \
  --user root:pass \
  -H "Polaris-Realm: POLARIS" \
  -d grant_type=client_credentials \
  -d scope=PRINCIPAL_ROLE:ALL | jq -r .access_token)

export MINIO_ENDPOINT=local-minio.$MINIO_NAMESPACE.svc.cluster.local:9000
export POLARIS_ENDPOINT=http://polaris.$POLARIS_NAMESPACE.svc.cluster.local:8181/api/catalog
export MINIO_USER=$(kubectl get secret --namespace $MINIO_NAMESPACE local-minio -o jsonpath="{.data.root-user}" | base64 -d)
export MINIO_PASSWORD=$(kubectl get secret --namespace $MINIO_NAMESPACE local-minio -o jsonpath="{.data.root-password}" | base64 -d)

envsubst < "$(dirname "${BASH_SOURCE[0]}")/../../resources/init.sql" > /tmp/init-env.sql
kubectl cp -n $DUCKDB_NAMESPACE /tmp/init-env.sql duckdb:/root/init-env.sql
