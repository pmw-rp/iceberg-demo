SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

# Produce syslog records in three batches with a 60-second gap between each.
# Redpanda flushes Iceberg files on a ~10s lag, so each batch lands in its own
# Parquet file — giving us the small-file fragmentation that compaction fixes.

BATCH_SIZE=333

echo "Batch 1/3 — producing records 1-${BATCH_SIZE}..."
head -n $BATCH_SIZE syslogs.json | rpk topic produce syslog --schema-id=topic

echo "Waiting 60s for Redpanda to flush to Iceberg..."
sleep 60

echo "Batch 2/3 — producing records $((BATCH_SIZE + 1))-$((BATCH_SIZE * 2))..."
tail -n +$((BATCH_SIZE + 1)) syslogs.json | head -n $BATCH_SIZE | rpk topic produce syslog --schema-id=topic

echo "Waiting 60s for Redpanda to flush to Iceberg..."
sleep 60

echo "Batch 3/3 — producing remaining records..."
tail -n +$((BATCH_SIZE * 2 + 1)) syslogs.json | rpk topic produce syslog --schema-id=topic

echo "Waiting 60s for final flush to Iceberg..."
sleep 60

echo "Done. All records produced."

popd
