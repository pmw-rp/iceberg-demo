SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

source ../../config

# Run Spark compaction job on the syslog Iceberg table
kubectl cp -n $SPARK_NAMESPACE compact.py spark:/opt/spark/compact.py
kubectl exec -it -n $SPARK_NAMESPACE spark -- \
  /opt/spark/bin/spark-submit \
  --master local[*] \
  /opt/spark/compact.py

popd
