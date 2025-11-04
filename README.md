# Snowflake S3 Access Point Integration

Load data from S3 into Snowflake using **S3 Access Points** to restrict access to the `202511/` prefix only.

## Security

Four layers: Storage Integration → IAM Role → Access Point Policy (3 DENY statements) → Bucket Policy

See [SECURITY.md](SECURITY.md) for details.

## Usage

```bash
make apply  # Deploy infrastructure
make test   # Verify security (loads data + blocks secret/)
make upload # Upload sample data to 202511/
```

## References

- [Snowflake Storage Integration](https://docs.snowflake.com/en/user-guide/data-load-s3-config-storage-integration)
- [AWS S3 Access Points](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-points.html)
- [Terraform Provider for Snowflake](https://github.com/snowflakedb/terraform-provider-snowflake)
