SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

source ../../config

kubectl cp -n $SPARK_NAMESPACE delete-record.py spark:/opt/spark/delete-record.py
kubectl exec -it -n $SPARK_NAMESPACE spark -- \
  /opt/spark/bin/spark-submit \
  --master local[*] \
  /opt/spark/delete-record.py

popd
