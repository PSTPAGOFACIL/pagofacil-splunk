variable "aws_region" {
  type        = string
  description = "AWS Server Region for Cloud Services"
  default     = "us-west-2"
}

variable "environment" {
  type        = string
  description = "Project environment default tag"
  default     = "dev"
}

variable "vpc_id" {
  type        = string
  description = "ID of main VPC"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs of private subnets within main VPC"
}