SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

# Register the syslog Avro schema and create an Iceberg-enabled topic
rpk registry schema create syslog-value --schema ./syslog.avsc --type avro

rpk topic create syslog -p1 -r1 --topic-config=redpanda.iceberg.mode=value_schema_id_prefix

popd
