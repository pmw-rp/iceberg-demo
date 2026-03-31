-- Show all snapshots so we can see the history
SELECT sequence_number, snapshot_id, timestamp_ms
FROM iceberg_snapshots(iceberg_catalog.redpanda.syslog)
ORDER BY sequence_number;

-- Time travel to snapshot $SNAPSHOT_ID (before the delete) — the record is still there
SET unsafe_enable_version_guessing = true;
SELECT message, host, severity
FROM iceberg_scan('s3://redpanda/redpanda/syslog', snapshot_from_id=$SNAPSHOT_ID)
WHERE message = 'tnpjdzarwhusw';
