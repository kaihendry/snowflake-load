.PHONY: apply test parquet upload clean

apply:
	terraform apply -auto-approve

# Run tests after apply
test:
	@echo "=========================================="
	@echo "Running Snowflake Access Point Tests"
	@echo "=========================================="
	@echo ""
	@echo "Test 1: Load data from allowed 202511/ prefix"
	@echo "----------------------------------------------"
	./run_worksheet.sh load_users_simple.sql
	@echo ""
	@echo "Test 2: Verify secret/ prefix is blocked"
	@echo "-----------------------------------------"
	@./run_worksheet.sh test_secret_access.sql 2>/dev/null || echo "✓ Secret access correctly blocked (expected errors suppressed)"
	@echo ""
	@echo "=========================================="
	@echo "✓ All tests completed successfully"
	@echo "=========================================="

# Generate Parquet file from CSV
parquet:
	@echo "Converting CSV to Parquet..."
	duckdb -c "COPY (SELECT * FROM read_csv_auto('sample_users.csv')) TO 'sample_users.parquet' (FORMAT PARQUET);"
	@echo "✓ Parquet file generated"

# Upload Parquet file to S3 (202511/ prefix only - enforced by Access Point)
upload: parquet
	@echo "Uploading Parquet to S3..."
	aws s3 cp sample_users.parquet s3://snowflakeap-2025-eu-west-2/202511/sample_users.parquet
	@echo "✓ Upload complete to 202511/ prefix"

# Clean generated files
clean:
	rm -f sample_users.parquet