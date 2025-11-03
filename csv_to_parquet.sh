#!/bin/bash

# CSV to Parquet Converter using DuckDB
# Usage: ./csv_to_parquet.sh input.csv [output.parquet]

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <input.csv> [output.parquet]"
    echo "Example: $0 sample_users.csv sample_users.parquet"
    exit 1
fi

INPUT_CSV="$1"
OUTPUT_PARQUET="${2:-${INPUT_CSV%.csv}.parquet}"

# Check if input file exists
if [ ! -f "$INPUT_CSV" ]; then
    echo "Error: Input file '$INPUT_CSV' not found"
    exit 1
fi

# Check if duckdb is installed
if ! command -v duckdb &> /dev/null; then
    echo "Error: duckdb is not installed"
    echo "Install with: brew install duckdb"
    exit 1
fi

echo "=========================================="
echo "Converting CSV to Parquet"
echo "=========================================="
echo "Input:  $INPUT_CSV"
echo "Output: $OUTPUT_PARQUET"
echo "=========================================="
echo ""

# Convert CSV to Parquet
duckdb -c "COPY (SELECT * FROM read_csv_auto('$INPUT_CSV')) TO '$OUTPUT_PARQUET' (FORMAT PARQUET);"

echo ""
echo "=========================================="
echo "Conversion completed successfully!"
echo "=========================================="
echo ""

# Show the schema
echo "Schema:"
duckdb -c "DESCRIBE SELECT * FROM '$OUTPUT_PARQUET';"

echo ""
echo "Preview (first 5 rows):"
duckdb -c "SELECT * FROM '$OUTPUT_PARQUET' LIMIT 5;"
