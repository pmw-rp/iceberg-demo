SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

# Create a topic
rpk topic create demo1 -p1 -r1 --topic-config=redpanda.iceberg.mode=key_value

popd