SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

source ../../config

kubectl cp -n $SPARK_NAMESPACE expire-snapshots.py spark:/opt/spark/expire-snapshots.py
kubectl exec -it -n $SPARK_NAMESPACE spark -- \
  /opt/spark/bin/spark-submit \
  --master local[*] \
  /opt/spark/expire-snapshots.py

popd
