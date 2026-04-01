SELECT
    file_path,
    record_count,
    status
FROM iceberg_metadata(iceberg_catalog.redpanda.syslog);
