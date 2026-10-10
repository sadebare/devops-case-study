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

variable "github_oidc_subject_prefix" {
  description = "Start of the GitHub OIDC \"sub\" claim. Null means \"repo:<github_repository>\". Repositories with GitHub's immutable subject format need \"repo:<owner>@<owner id>/<name>@<repo id>\"."
  type        = string
  default     = null

  validation {
    condition     = var.github_oidc_subject_prefix == null || can(regex("^repo:[^*]+$", var.github_oidc_subject_prefix))
    error_message = "github_oidc_subject_prefix must start with \"repo:\" and contain no wildcards."
  }
}

variable "apply_environment" {
  description = "GitHub environment the terraform apply job runs in. Only that environment can assume the apply role."
  type        = string
  default     = "production"
}
