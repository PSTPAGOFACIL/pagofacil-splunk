variable "aws_region" {
  type        = string
  description = "AWS Server Region for Cloud Services"
  default     = "us-east-1"
}

variable "aws_account_id" {
  type        = string
  description = "The aws account id"
}

variable "environment" {
  type        = string
  description = "Project environment default tag"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "The Private subnet ids for the VPC link attaching to lambda"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID of target"
}

variable "pf_splunk_index" {
  type        = string
  description = "Index name for splunk for Pago Facil"
  default     = "pago_facil"
}

variable "pf_splunk_source_type" {
  type        = string
  description = "Source type for splunk"
  default     = "aws:pago_facil:application"
}