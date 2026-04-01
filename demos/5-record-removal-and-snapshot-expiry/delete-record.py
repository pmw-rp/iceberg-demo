import os
from pyspark.sql import SparkSession

spark = (
    SparkSession.builder
    .appName("iceberg-delete-record")
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

print("=== Record before deletion ===")
spark.sql(
    "SELECT * FROM polaris.redpanda.syslog WHERE message = 'tnpjdzarwhusw'"
).show(truncate=False)

print("=== Deleting record ===")
spark.sql(
    "DELETE FROM polaris.redpanda.syslog WHERE message = 'tnpjdzarwhusw'"
)

print("=== Confirming deletion ===")
spark.sql(
    "SELECT * FROM polaris.redpanda.syslog WHERE message = 'tnpjdzarwhusw'"
).show(truncate=False)

print("=== Record count after deletion ===")
spark.sql("SELECT count(*) AS record_count FROM polaris.redpanda.syslog").show()

spark.stop()
