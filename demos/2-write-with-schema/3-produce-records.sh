SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

# Produce some records
cat ./syslogs.json | rpk topic produce syslog --schema-id=topic

popd