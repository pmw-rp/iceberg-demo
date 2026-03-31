set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

source ./config

# Cleanup temp credential files and background port-forwards on exit
POLARIS_PF_PID=""
cleanup() {
  rm -f aws-creds minio-creds postgres-creds
  [ -n "$POLARIS_PF_PID" ] && kill "$POLARIS_PF_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Install Minio

kubectl create namespace $MINIO_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
cat << EOF | helm upgrade --install -n $MINIO_NAMESPACE local oci://registry-1.docker.io/bitnamicharts/minio --wait -f -
global:
  security:
    allowInsecureImages: true
image:
  repository: bitnamilegacy/minio
  debug: true
console:
  image:
    repository: bitnamilegacy/minio-object-browser
extraEnvVars:
  - name: MINIO_LOG_LEVEL
    value: DEBUG
EOF

# Configure Minio

export MINIO_USER=$(kubectl get secret --namespace $MINIO_NAMESPACE local-minio -o jsonpath="{.data.root-user}" | base64 -d)
export MINIO_PASSWORD=$(kubectl get secret --namespace $MINIO_NAMESPACE local-minio -o jsonpath="{.data.root-password}" | base64 -d)

cat << EOF > minio-creds
access=${MINIO_USER}
secret=${MINIO_PASSWORD}
EOF

export MINIO_POD=$(kubectl get pods -n $MINIO_NAMESPACE | grep -Ev 'console|NAME' | awk '{print $1}')

kubectl exec -n ${MINIO_NAMESPACE} ${MINIO_POD} -- mc alias set local http://local-minio.$MINIO_NAMESPACE.svc.cluster.local:9000 ${MINIO_USER} ${MINIO_PASSWORD}
kubectl exec -n ${MINIO_NAMESPACE} ${MINIO_POD} -- mc mb local/redpanda
kubectl exec -n ${MINIO_NAMESPACE} ${MINIO_POD} -- mc anonymous set public local/redpanda

export MINIO_ENDPOINT=local-minio.$MINIO_NAMESPACE.svc.cluster.local:9000

# Install Postgres

kubectl create namespace $POSTGRES_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f resources/postgres.yaml -n ${POSTGRES_NAMESPACE}
kubectl wait --for=condition=ready pod -l app=postgres -n $POSTGRES_NAMESPACE --timeout=120s
for i in $(seq 1 30); do
  kubectl exec -n $POSTGRES_NAMESPACE postgres-0 -- pg_isready -U postgres && break
  [ $i -eq 30 ] && { echo "Timed out waiting for postgres to accept connections"; exit 1; }
  sleep 2
done
export POSTGRES_PASSWORD=postgres123
cat resources/create-db.sql | kubectl exec -it postgres-0 -n $POSTGRES_NAMESPACE -- /bin/bash -c "psql postgresql://postgres:${POSTGRES_PASSWORD}@postgres-0/postgres"

# Install Polaris

kubectl create namespace $POLARIS_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

cat << EOF > aws-creds
[minio]
aws_access_key_id=${MINIO_USER}
aws_secret_access_key=${MINIO_PASSWORD}
region=dummy
EOF
kubectl create secret generic aws-creds -n $POLARIS_NAMESPACE --from-file=credentials=aws-creds --dry-run=client -o yaml | kubectl apply -f -

cat << EOF > postgres-creds
username=polaris
password=polaris123
url=jdbc:postgresql://postgres.$POSTGRES_NAMESPACE.svc.cluster.local:5432/polaris?currentSchema=polaris
EOF
kubectl create secret generic postgres-creds --from-env-file="$PWD/postgres-creds" -n $POLARIS_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install --namespace $POLARIS_NAMESPACE polaris resources/polaris/helm/polaris -f resources/polaris-values.yaml --wait

# Configure Polaris (realm and initial user)

envsubst < resources/bootstrap.yaml | kubectl apply -f -
kubectl wait --for=condition=complete job/bootstrap -n $POLARIS_NAMESPACE
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=polaris -n $POLARIS_NAMESPACE --timeout=120s

# Create the Redpanda catalog and associated RBAC

kubectl port-forward svc/polaris -n $POLARIS_NAMESPACE 8181:8181 &
POLARIS_PF_PID=$!

# Wait for port-forward to be ready
for i in $(seq 1 20); do
  curl -sf http://localhost:8181/api/catalog/v1/oauth/tokens --user root:pass \
    -H "Polaris-Realm: POLARIS" -d grant_type=client_credentials \
    -d scope=PRINCIPAL_ROLE:ALL -o /dev/null && break
  [ $i -eq 20 ] && { echo "Timed out waiting for Polaris port-forward"; exit 1; }
  sleep 1
done

export POLARIS_HOST=localhost
export POLARIS_ENDPOINT=http://$POLARIS_HOST:8181/api/catalog

## Get an access token
export TOKEN=$(curl -s http://$POLARIS_HOST:8181/api/catalog/v1/oauth/tokens \
  --user root:pass \
  -H "Polaris-Realm: POLARIS" \
  -d grant_type=client_credentials \
  -d scope=PRINCIPAL_ROLE:ALL | jq -r .access_token)

[ -z "$TOKEN" ] || [ "$TOKEN" = "null" ] && { echo "Failed to obtain Polaris token"; exit 1; }

## Create the catalog
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://$POLARIS_HOST:8181/api/management/v1/catalogs \
  -H "Polaris-Realm: POLARIS" \
  -H "Authorization: Bearer $TOKEN" \
  --json '{"type":"INTERNAL","name":"redpanda_catalog","properties":{"default-base-location":"s3://redpanda"},"createTimestamp":1758705392193,"lastUpdateTimestamp":1758705392193,"entityVersion":1,"storageConfigInfo":{"roleArn":"arn:aws:iam::123456789012:role/dummy","region":"dummy","endpoint":"http://local-minio.minio.svc.cluster.local:9000/","pathStyleAccess":true,"storageType":"S3","allowedLocations":["s3://redpanda"]}}')
[[ "$HTTP_STATUS" =~ ^2 ]] || { echo "Failed to create catalog (HTTP $HTTP_STATUS)"; exit 1; }

# List the current catalogs to validate that our creation was successful
curl -s -X GET http://$POLARIS_HOST:8181/api/management/v1/catalogs \
  -H "Authorization: Bearer $TOKEN" | jq

# Create a catalog admin role
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT http://$POLARIS_HOST:8181/api/management/v1/catalogs/redpanda_catalog/catalog-roles/catalog_admin/grants \
  -H "Authorization: Bearer $TOKEN" \
  --json '{"grant":{"type":"catalog", "privilege":"CATALOG_MANAGE_CONTENT"}}')
[[ "$HTTP_STATUS" =~ ^2 ]] || { echo "Failed to grant catalog admin role (HTTP $HTTP_STATUS)"; exit 1; }

# Create a data engineer role
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://$POLARIS_HOST:8181/api/management/v1/principal-roles \
  -H "Authorization: Bearer $TOKEN" \
  --json '{"principalRole":{"name":"data_engineer"}}')
[[ "$HTTP_STATUS" =~ ^2 ]] || { echo "Failed to create data_engineer role (HTTP $HTTP_STATUS)"; exit 1; }

# Connect the roles
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT http://$POLARIS_HOST:8181/api/management/v1/principal-roles/data_engineer/catalog-roles/redpanda_catalog \
  -H "Authorization: Bearer $TOKEN" \
  --json '{"catalogRole":{"name":"catalog_admin"}}')
[[ "$HTTP_STATUS" =~ ^2 ]] || { echo "Failed to connect roles (HTTP $HTTP_STATUS)"; exit 1; }

# Give root the data engineer role
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT http://$POLARIS_HOST:8181/api/management/v1/principals/root/principal-roles \
  -H "Authorization: Bearer $TOKEN" \
  --json '{"principalRole": {"name":"data_engineer"}}')
[[ "$HTTP_STATUS" =~ ^2 ]] || { echo "Failed to assign data_engineer role to root (HTTP $HTTP_STATUS)"; exit 1; }

# Get the roles for root to show the RBAC configuration is sufficient
curl -s -X GET http://$POLARIS_HOST:8181/api/management/v1/principals/root/principal-roles -H "Authorization: Bearer $TOKEN" | jq

# Install Redpanda

helm repo add redpanda https://charts.redpanda.com
helm repo update

cat << EOF | helm upgrade --install redpanda redpanda/redpanda \
  --version 25.1.1 \
  --namespace $REDPANDA_NAMESPACE \
  --create-namespace \
  --wait \
  -f -
image:
  repository: docker.redpanda.com/redpandadata/redpanda
  tag: v25.3.9
external:
  enabled: true
  service:
    enabled: false
  addresses:
  - localhost
listeners:
  kafka:
    external:
      default:
        enabled: true
        port: 9094
        advertisedPorts:
        - 9094
statefulset:
  replicas: 1
config:
  cluster:
    default_topic_replications: 1
    iceberg_enabled: true
    iceberg_catalog_type: rest
    iceberg_rest_catalog_endpoint: http://polaris.$POLARIS_NAMESPACE.svc.cluster.local:8181/api/catalog/
    iceberg_rest_catalog_oauth2_server_uri: http://polaris.$POLARIS_NAMESPACE.svc.cluster.local:8181/api/catalog/v1/oauth/tokens
    iceberg_rest_catalog_authentication_mode: oauth2
    iceberg_rest_catalog_client_id: root
    iceberg_rest_catalog_client_secret: pass
    iceberg_rest_catalog_warehouse: redpanda_catalog
    iceberg_rest_catalog_oauth2_scope: "PRINCIPAL_ROLE:ALL"
    iceberg_target_lag_ms: 10000
    iceberg_disable_snapshot_tagging: true
storage:
  tiered:
    config:
      cloud_storage_enabled: true
      cloud_storage_bucket: redpanda
      cloud_storage_api_endpoint: local-minio.$MINIO_NAMESPACE.svc.cluster.local
      cloud_storage_api_endpoint_port: 9000
      cloud_storage_disable_tls: true
      cloud_storage_region: local
      cloud_storage_access_key: ${MINIO_USER}
      cloud_storage_secret_key: ${MINIO_PASSWORD}
      cloud_storage_segment_max_upload_interval_sec: 30
      cloud_storage_url_style: path
      cloud_storage_enable_remote_write: true
      cloud_storage_enable_remote_read: true
tls:
  enabled: false
auth:
  sasl:
    enabled: false
EOF

kubectl port-forward pod/redpanda-0 -n $REDPANDA_NAMESPACE 8081 9094 9644 &
echo $! > port-forward.pid
kubectl port-forward svc/polaris -n $POLARIS_NAMESPACE 8181:8181 &
echo $! > polaris-port-forward.pid
rpk profile create local-bcced7fb -s brokers=localhost:9094 -s admin.hosts=localhost:9644 || rpk profile use local-bcced7fb

# Create a Ubuntu pod to run DuckDB

kubectl create namespace $DUCKDB_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: duckdb
  namespace: $DUCKDB_NAMESPACE
  labels:
    app: ubuntu
spec:
  containers:
  - image: ubuntu
    command:
      - sh
      - -c
      - "apt update && apt install -y curl && curl https://install.duckdb.org | DUCKDB_VERSION=$DUCKDB_VERSION sh && sleep infinity"
    imagePullPolicy: IfNotPresent
    name: ubuntu
  restartPolicy: Always
EOF

kubectl wait --for=condition=ready pod/duckdb -n $DUCKDB_NAMESPACE --timeout=300s

# Configure the DuckDB init sql
export MINIO_ENDPOINT=local-minio.$MINIO_NAMESPACE.svc.cluster.local:9000
export POLARIS_ENDPOINT=http://polaris.$POLARIS_NAMESPACE.svc.cluster.local:8181/api/catalog
export MINIO_USER=$(kubectl get secret --namespace $MINIO_NAMESPACE local-minio -o jsonpath="{.data.root-user}" | base64 -d)
export MINIO_PASSWORD=$(kubectl get secret --namespace $MINIO_NAMESPACE local-minio -o jsonpath="{.data.root-password}" | base64 -d)
envsubst < resources/init.sql > resources/init-env.sql
kubectl cp -n $DUCKDB_NAMESPACE resources/init-env.sql duckdb:/root

echo
echo Minio credentials:
echo user: ${MINIO_USER}
echo password: ${MINIO_PASSWORD}
echo

# Install Spark

kubectl create namespace $SPARK_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

export POLARIS_ENDPOINT_INTERNAL=http://polaris.$POLARIS_NAMESPACE.svc.cluster.local:8181/api/catalog

cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: spark
  namespace: $SPARK_NAMESPACE
  labels:
    app: spark
spec:
  containers:
  - name: spark
    image: apache/spark:3.5.4-scala2.12-java17-python3-ubuntu
    command:
      - sh
      - -c
      - "sleep infinity"
    imagePullPolicy: IfNotPresent
    env:
    - name: MINIO_ENDPOINT
      value: "http://local-minio.$MINIO_NAMESPACE.svc.cluster.local:9000"
    - name: MINIO_USER
      value: "${MINIO_USER}"
    - name: MINIO_PASSWORD
      value: "${MINIO_PASSWORD}"
    - name: POLARIS_ENDPOINT
      value: "${POLARIS_ENDPOINT_INTERNAL}"
  restartPolicy: Always
EOF

kubectl wait --for=condition=ready pod/spark -n $SPARK_NAMESPACE --timeout=300s

# Download Iceberg and S3 JARs directly into Spark's classpath so spark-submit
# does not need Ivy/Maven at runtime
MAVEN=https://repo1.maven.org/maven2
kubectl exec -n $SPARK_NAMESPACE spark -- sh -c "
  curl -fsSL -o /opt/spark/jars/iceberg-spark-runtime-3.5_2.12-1.7.1.jar \
    $MAVEN/org/apache/iceberg/iceberg-spark-runtime-3.5_2.12/1.7.1/iceberg-spark-runtime-3.5_2.12-1.7.1.jar && \
  curl -fsSL -o /opt/spark/jars/hadoop-aws-3.3.4.jar \
    $MAVEN/org/apache/hadoop/hadoop-aws/3.3.4/hadoop-aws-3.3.4.jar && \
  curl -fsSL -o /opt/spark/jars/aws-java-sdk-bundle-1.12.262.jar \
    $MAVEN/com/amazonaws/aws-java-sdk-bundle/1.12.262/aws-java-sdk-bundle-1.12.262.jar
"

echo
echo Spark pod is ready in namespace $SPARK_NAMESPACE
echo

popd
