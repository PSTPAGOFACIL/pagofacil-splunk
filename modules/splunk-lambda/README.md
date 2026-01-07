CloudWatch to Splunk Log Forwarder (Terraform-managed)
This setup forwards ECS service logs from CloudWatch to Splunk using a Lambda function.
It's customized, lightweight, and deploys entirely via Terraform.

Overview:
- ECS services push logs to CloudWatch.
- A CloudWatch subscription filter triggers a Lambda.
- The Lambda reformats logs and sends them to Splunk via HEC.
- Code is zipped manually and deployed via S3.

Structure:
- lambda.js - main handler
- lib/mysplunklogger.js - helper that sends logs to Splunk
- splunk.zip - zipped code uploaded to S3 for Lambda
- Terraform manages:
- S3 upload (aws_s3_object)
- Lambda config (terraform-aws-lambda module)
- Environment variables
- IAM roles, security groups, etc.

Lambda Code Updates:
Since the module doesn't support source_code_hash, we use a workaround:

1. Code is zipped manually.
2. aws_s3_object uses:
etag = filemd5("${path.module}/splunk.zip")
3. Lambda module uses:
ZIP_VERSION = filemd5("${path.module}/splunk.zip")
This forces Lambda to redeploy when the zip changes.

Steps to Update Lambda Code:
1. Edit src/lambda.js or src/lib/.
2. Re-zip:
cd modules/splunk/src
zip -r ../splunk.zip lambda.js lib/
3. Commit the new splunk.zip.
4. Run:
terraform plan
terraform apply

Environment Detection:
- ENVIRONMENT var is passed into Lambda.
- Included in log payload as host (e.g., host=dev)
- Splunk filters logs using this field.

Log Enrichment:
Each log includes:
- event (original log)
- source (logStream)
- logGroup, logStream
- sourcetype, index
- host (environment)
- time (epoch timestamp)

Splunk Config:
- Token, URL, and index are shared across environments.
- Lambda retrieves them securely from Secrets Manager.

Key Notes for DevOps / Future folks who work on this repository:
- Always re-zip after code changes.
- Commit splunk.zip before Terraform runs.
- Keep ZIP_VERSION and etag in place - they ensure redeploy.
- For more control, migrate to aws_lambda_function (manual management).