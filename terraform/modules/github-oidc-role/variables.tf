variable "role_name" {
  description = "Name of the IAM role assumed by GitHub Actions."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the role, as \"owner/name\"."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like \"owner/name\" (no wildcards)."
  }
}

variable "allowed_refs" {
  description = "Git refs whose workflow runs may assume the role. Pull request runs have a different subject and are therefore excluded."
  type        = list(string)
  default     = ["refs/heads/main"]

  validation {
    condition     = length(var.allowed_refs) > 0 && alltrue([for r in var.allowed_refs : startswith(r, "refs/") && !strcontains(r, "*")])
    error_message = "allowed_refs must be a non-empty list of full refs (refs/heads/..., refs/tags/...) without wildcards."
  }
}

variable "ecr_repository_arns" {
  description = "ECR repositories the role may push to."
  type        = list(string)

  validation {
    condition     = length(var.ecr_repository_arns) > 0
    error_message = "At least one ECR repository ARN is required."
  }
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. An AWS account can hold only one per URL, so set this to false if it already exists and it will be looked up instead."
  type        = bool
  default     = true
}

variable "max_session_duration" {
  description = "Maximum session length in seconds. One hour is the IAM minimum and is plenty for a CI job."
  type        = number
  default     = 3600
}

variable "tags" {
  description = "Tags applied to the IAM resources."
  type        = map(string)
  default     = {}
}
