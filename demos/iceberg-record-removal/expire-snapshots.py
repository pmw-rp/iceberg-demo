import os
from datetime import datetime, timezone
from pyspark.sql import SparkSession

spark = (
    SparkSession.builder
    .appName("iceberg-expire-snapshots")
    .config(
        "spark.sql.extensions",
        "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
    )
    .config("spark.sql.catalog.polaris", "org.apache.iceberg.spark.SparkCatalog")
    .config("spark.sql.catalog.polaris.type", "rest")
    .config("spark.sql.catalog.polaris.uri", os.environ["POLARIS_ENDPOINT"])
    .config("spark.sql.catalog.polaris.credential", "root:pass")
    .config("spark.sql.catalog.polaris.scope", "PRINCIPAL_ROLE:ALL")
    .config("spark.sql.catalog.polaris.warehouse", "redpanda_catalog")
    .config("spark.sql.catalog.polaris.header.Polaris-Realm", "POLARIS")
    .config("spark.sql.catalog.polaris.io-impl", "org.apache.iceberg.hadoop.HadoopFileIO")
    .config("spark.hadoop.fs.s3a.endpoint", os.environ["MINIO_ENDPOINT"])
    .config("spark.hadoop.fs.s3a.access.key", os.environ["MINIO_USER"])
    .config("spark.hadoop.fs.s3a.secret.key", os.environ["MINIO_PASSWORD"])
    .config("spark.hadoop.fs.s3a.path.style.access", "true")
    .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false")
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
    .config("spark.hadoop.fs.s3a.aws.credentials.provider",
            "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider")
    .config("spark.hadoop.fs.s3.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
    .config("spark.hadoop.fs.s3.endpoint", os.environ["MINIO_ENDPOINT"])
    .config("spark.hadoop.fs.s3.access.key", os.environ["MINIO_USER"])
    .config("spark.hadoop.fs.s3.secret.key", os.environ["MINIO_PASSWORD"])
    .config("spark.hadoop.fs.s3.path.style.access", "true")
    .config("spark.hadoop.fs.s3.connection.ssl.enabled", "false")
    .getOrCreate()
)

print("=== Snapshots before expiry ===")
spark.sql(
    "SELECT snapshot_id, committed_at, operation "
    "FROM polaris.redpanda.syslog.snapshots ORDER BY committed_at"
).show(truncate=False)

# Expire all snapshots older than now, retaining only the current one
now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)

print("=== Expiring all snapshots except the current one ===")
spark.sql(
    f"CALL polaris.system.expire_snapshots("
    f"  table => 'redpanda.syslog',"
    f"  older_than => TIMESTAMP '{datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')}',"
    f"  retain_last => 1"
    f")"
).show()

print("=== Snapshots after expiry — only current snapshot remains ===")
spark.sql(
    "SELECT snapshot_id, committed_at, operation "
    "FROM polaris.redpanda.syslog.snapshots ORDER BY committed_at"
).show(truncate=False)

print("=== Time travel to deleted snapshot is now impossible ===")
print("The original data files containing the deleted record have been removed from storage.")

spark.stop()
