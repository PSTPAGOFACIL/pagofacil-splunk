resource "aws_iam_role" "lambda_splunk_role" {
  name = "lambda_splunk_forwarder_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Effect = "Allow",
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_splunk_secrets_policy" {
  name_prefix = "lambda-splunk-secret-access"
  description = "Fine-grained access policy for Lambda to access splunk secrets"
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : [
            "secretsmanager:GetSecretValue"
          ],
          "Resource" = [
            "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.environment}/pf_splunk_hec_url*",
            "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.environment}/pf_splunk_hec_token*"
          ]
        },
        {
          "Effect" : "Allow",
          "Action" : [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ],
          "Resource" : "arn:aws:logs:*:*:*"
        }
      ]
    }
  )
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "attach_lambda_secret_access" {
  role       = aws_iam_role.lambda_splunk_role.name
  policy_arn = aws_iam_policy.lambda_splunk_secrets_policy.arn
}

resource "aws_iam_role_policy_attachment" "AWSLambdaVPCAccessExecutionRole" {
  role       = aws_iam_role.lambda_splunk_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_security_group" "lambda_splunk_sg" {
  name        = "pf-${var.environment}-lambda-splunk-sg"
  description = "Allow Lambda to send logs to splunk"
  vpc_id      = var.vpc_id
  lifecycle {
    create_before_destroy = true
  }
}

#tfsec:ignore:aws-vpc-no-public-egress-sgr
resource "aws_security_group_rule" "lambda_https_egress" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.lambda_splunk_sg.id
}

#trivy:ignore:AVD-AWS-0086
#trivy:ignore:AVD-AWS-0087
#trivy:ignore:AVD-AWS-0088
#trivy:ignore:AVD-AWS-0091
#trivy:ignore:AVD-AWS-0093
#trivy:ignore:AVD-AWS-0132

resource "aws_s3_bucket" "lambda_splunk_code_bucket" {
  bucket = "pf-${var.environment}-splunk-lambdafunctioncode"
}

resource "aws_s3_bucket_versioning" "lambda_zip_versioning" {
  bucket = aws_s3_bucket.lambda_splunk_code_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
  lifecycle {
    create_before_destroy = true
  }
  depends_on = [aws_s3_bucket.lambda_splunk_code_bucket]

}

resource "aws_s3_object" "lambda_zip" {
  bucket = "pf-${var.environment}-splunk-lambdafunctioncode"
  key    = "splunk.zip"
  source = "${path.module}/splunk.zip"
  etag   = filemd5("${path.module}/splunk.zip")
  lifecycle {
    create_before_destroy = true
  }
  depends_on = [aws_s3_bucket.lambda_splunk_code_bucket]
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "bucket_access" {
  statement {
    principals {
      type        = "*"
      identifiers = ["*"]
    }

    effect = "Deny"

    actions = [
      "s3:*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }

    resources = [
      "${aws_s3_bucket.lambda_splunk_code_bucket.arn}",
      "${aws_s3_bucket.lambda_splunk_code_bucket.arn}/*"
    ]
  }
}

resource "aws_s3_bucket_policy" "bucket_access" {
  bucket = aws_s3_bucket.lambda_splunk_code_bucket.id
  policy = data.aws_iam_policy_document.bucket_access.json
}

module "splunk_forwarder_lambda" {
  source                 = "terraform-aws-modules/lambda/aws"
  version                = "~> 7.0"
  vpc_subnet_ids         = var.private_subnet_ids
  vpc_security_group_ids = [aws_security_group.lambda_splunk_sg.id]
  function_name          = "pf-${var.environment}-splunk-log-forwarder"
  description            = "cloudwatch to splunk-log-forwarder"
  handler                = "lambda.handler"
  runtime                = "nodejs18.x"
  create_package         = false
  s3_existing_package = {
    bucket = "pf-${var.environment}-splunk-lambdafunctioncode"
    key    = "splunk.zip"
  }
  memory_size = 256
  timeout     = 10
  environment_variables = {
    SPLUNK_HEC_URL    = "${var.environment}/pf_splunk_hec_url"
    SPLUNK_HEC_TOKEN  = "${var.environment}/pf_splunk_hec_token"
    SPLUNK_INDEX      = var.pf_splunk_index
    SPLUNK_SOURCETYPE = var.pf_splunk_source_type
    ENVIRONMENT       = var.environment
    ZIP_VERSION       = filemd5("${path.module}/splunk.zip")
  }
  create_role = false
  lambda_role = aws_iam_role.lambda_splunk_role.arn
  depends_on = [
    aws_security_group.lambda_splunk_sg,
    aws_s3_object.lambda_zip,
    aws_s3_bucket.lambda_splunk_code_bucket
  ]
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = module.splunk_forwarder_lambda.lambda_function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:*:*"
}

data "aws_cloudwatch_log_groups" "all_lambda_logs" {
  log_group_name_prefix = "/aws/lambda/"
}

data "aws_cloudwatch_log_groups" "all_apigateway_logs" {
  log_group_name_prefix = "/aws/apigateway/"
}

data "aws_cloudwatch_log_groups" "all_apigateway_execution_logs" {
  log_group_name_prefix = "API-Gateway-Execution-Logs"
}

locals {
  filtered_lambda_log_group_names = toset([
    for name in data.aws_cloudwatch_log_groups.all_lambda_logs.log_group_names :
    name
    if !strcontains(name, "splunk")
  ])
}

resource "aws_cloudwatch_log_subscription_filter" "splunk_log_forwarder_lambdas" {
  for_each        = local.filtered_lambda_log_group_names
  name            = "cloudwatch-to-splunk"
  log_group_name  = each.value
  destination_arn = module.splunk_forwarder_lambda.lambda_function_arn
  filter_pattern  = ""
  depends_on      = [aws_lambda_permission.allow_cloudwatch]
}

resource "aws_cloudwatch_log_subscription_filter" "splunk_log_forwarder_apigateways" {
  for_each        = data.aws_cloudwatch_log_groups.all_apigateway_logs.log_group_names
  name            = "cloudwatch-to-splunk"
  log_group_name  = each.value
  destination_arn = module.splunk_forwarder_lambda.lambda_function_arn
  filter_pattern  = ""
  depends_on      = [aws_lambda_permission.allow_cloudwatch]
}

resource "aws_cloudwatch_log_subscription_filter" "splunk_log_forwarder_apigateway_executions" {
  for_each        = data.aws_cloudwatch_log_groups.all_apigateway_execution_logs.log_group_names
  name            = "cloudwatch-to-splunk"
  log_group_name  = each.value
  destination_arn = module.splunk_forwarder_lambda.lambda_function_arn
  filter_pattern  = ""
  depends_on      = [aws_lambda_permission.allow_cloudwatch]
}

