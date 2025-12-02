provider "aws" {
  region = "your_region"
  access_key = "your_access_key"
  secret_key = "your_secret_key"
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
  default     = "your_aws_account_id"
}