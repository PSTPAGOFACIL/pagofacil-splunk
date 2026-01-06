data "aws_caller_identity" "current" {}

module "splunk_lambda" {
  source             = "./modules/splunk-lambda"
  aws_account_id     = data.aws_caller_identity.current.account_id
  aws_region         = var.aws_region
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets
}