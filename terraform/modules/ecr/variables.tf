variable "name" {
  description = "Name of the ECR repository."
  type        = string
}

variable "image_tag_mutability" {
  description = "IMMUTABLE stops a pushed tag from being overwritten, so a tag always means the same image."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["IMMUTABLE", "MUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be IMMUTABLE or MUTABLE."
  }
}

variable "scan_on_push" {
  description = "Run ECR basic vulnerability scanning on every push (in addition to the Trivy scan in CI)."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption at rest. Null uses AES256 with an AWS-owned key."
  type        = string
  default     = null
}

variable "untagged_expiry_days" {
  description = "Days after which untagged images (orphaned layers, failed pushes) are expired."
  type        = number
  default     = 7

  validation {
    condition     = var.untagged_expiry_days >= 1
    error_message = "untagged_expiry_days must be at least 1."
  }
}

variable "max_image_count" {
  description = "Number of most recent images to keep. Older images are expired."
  type        = number
  default     = 30

  validation {
    condition     = var.max_image_count >= 1
    error_message = "max_image_count must be at least 1."
  }
}

variable "force_delete" {
  description = "Allow the repository to be destroyed while it still contains images."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the repository."
  type        = map(string)
  default     = {}
}
