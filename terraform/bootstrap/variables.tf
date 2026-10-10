variable "aws_region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "eu-west-1"
}

variable "state_bucket_name" {
  description = "Globally unique name for the Terraform state bucket, e.g. \"<org>-terraform-state-<account id>\"."
  type        = string
}
