variable "bucket_name" {
  description = "Globally unique name for the Terraform state bucket."
  type        = string
}

variable "noncurrent_version_expiry_days" {
  description = "Days to keep superseded state versions before they are deleted."
  type        = number
  default     = 90
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption at rest. Null uses SSE-S3 (AES256)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the bucket."
  type        = map(string)
  default     = {}
}
