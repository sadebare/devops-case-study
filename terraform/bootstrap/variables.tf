variable "aws_region" {
  description = "AWS region for the state bucket. Must match aws_region in the main configuration."
  type        = string
  # Ireland. The closest AWS region to Nigeria with good latency over the
  # West Africa to Europe subsea cables, and a full set of AWS services.
  default = "eu-west-1"
}

variable "state_bucket_name" {
  description = "Globally unique name for the Terraform state bucket, e.g. \"<org>-terraform-state-<account id>\"."
  type        = string
}

variable "service_name" {
  description = "Must match service_name in the main configuration. Used to scope the terraform roles to its state and resources."
  type        = string
  default     = "items-api"
}

variable "github_repository" {
  description = "GitHub repository whose terraform workflow may plan and apply, as \"owner/name\"."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like \"owner/name\" (no wildcards)."
  }
}

variable "apply_environment" {
  description = "GitHub environment the terraform apply job runs in. Only that environment can assume the apply role."
  type        = string
  default     = "production"
}
