.PHONY: apply
apply:
	terraform apply -auto-approve

cp:
	aws s3 cp /Users/hendry/tmp/aws-partners-datasette/partners.csv s3://snowflakeap-2025-eu-west-2/$(shell date +%Y%m)/partners.csv