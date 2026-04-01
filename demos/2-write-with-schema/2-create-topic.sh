SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

# Create a topic
rpk topic create syslog -p1 -r1 --topic-config=redpanda.iceberg.mode=value_schema_id_prefix

popd