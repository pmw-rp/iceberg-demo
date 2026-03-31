SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

# Register the schema
rpk registry schema create syslog-value --schema ./syslog.avsc --type avro

popd