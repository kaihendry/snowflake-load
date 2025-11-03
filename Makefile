.PHONY: apply parquet upload clean

apply:
	terraform apply -auto-approve

# Generate Parquet file from CSV
parquet:
	@echo "Converting CSV to Parquet..."
	duckdb -c "COPY (SELECT * FROM read_csv_auto('sample_users.csv')) TO 'sample_users.parquet' (FORMAT PARQUET);"
	@echo "✓ Parquet file generated"

# Upload Parquet file to S3
upload: parquet
	@echo "Uploading Parquet to S3..."
	aws s3 cp sample_users.parquet s3://snowflakeap-2025-eu-west-2/$(shell date +%Y%m)/sample_users.parquet
	@echo "✓ Upload complete"

# Clean generated files
clean:
	rm -f sample_users.parquet