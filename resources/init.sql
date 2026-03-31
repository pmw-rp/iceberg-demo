INSTALL iceberg;

LOAD iceberg;

.mode trash

CREATE SECRET s3_secret (
    TYPE s3,
    ENDPOINT '$MINIO_ENDPOINT',
    KEY_ID '$MINIO_USER',
    SECRET '$MINIO_PASSWORD',
    REGION 'dummy-region',
    URL_STYLE 'path',
    USE_SSL false
);

CREATE SECRET iceberg_secret (
    TYPE ICEBERG,
    TOKEN '$TOKEN'
);

ATTACH 'redpanda_catalog' AS iceberg_catalog (
  TYPE iceberg,
  SECRET 'iceberg_secret',
  ENDPOINT '$POLARIS_ENDPOINT',
  ACCESS_DELEGATION_MODE 'none'
);

.mode table
