SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

# Alternative: load in previously generated telemetry
cat ./telemetry.json | rpk topic produce telemetry

popd