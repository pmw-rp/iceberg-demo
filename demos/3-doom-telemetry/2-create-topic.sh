SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

# Create the topic
rpk topic create telemetry --topic-config=redpanda.iceberg.mode=value_schema_latest

popd