#!/bin/bash

# Snowflake Worksheet Runner
# This script runs SQL files against your Snowflake account

set -e

# Configuration from main.tf
ACCOUNT="xbjfxng-qm18685"
USER="TERRAFORM_SVC"
ROLE="ACCOUNTADMIN"
PRIVATE_KEY_PATH="keys/snowflake_tf_snow_key.p8"
SNOWSQL_PATH="/Applications/SnowSQL.app/Contents/MacOS/snowsql"

# Check if SQL file is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <sql_file>"
    echo "Example: $0 load_data_worksheet.sql"
    exit 1
fi

SQL_FILE="$1"

# Check if file exists
if [ ! -f "$SQL_FILE" ]; then
    echo "Error: File '$SQL_FILE' not found"
    exit 1
fi

# Check if private key exists
if [ ! -f "$PRIVATE_KEY_PATH" ]; then
    echo "Error: Private key not found at '$PRIVATE_KEY_PATH'"
    exit 1
fi

echo "=========================================="
echo "Running Snowflake Worksheet"
echo "=========================================="
echo "Account:  $ACCOUNT"
echo "User:     $USER"
echo "Role:     $ROLE"
echo "SQL File: $SQL_FILE"
echo "=========================================="
echo ""

# Run the SQL file
"$SNOWSQL_PATH" \
    -a "$ACCOUNT" \
    -u "$USER" \
    -r "$ROLE" \
    --authenticator SNOWFLAKE_JWT \
    --private-key-path "$PRIVATE_KEY_PATH" \
    -f "$SQL_FILE"

echo ""
echo "=========================================="
echo "Worksheet execution completed"
echo "=========================================="
