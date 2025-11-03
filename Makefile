.PHONY: apply
apply:
	terraform apply -auto-approve

cp:
	aws s3 cp sample_users.csv s3://snowflakeap-2025-eu-west-2/$(shell date +%Y%m)/sample_users.csv