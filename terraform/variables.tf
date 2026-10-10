variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  # Ireland. The closest AWS region to Nigeria with good latency over the
  # West Africa to Europe subsea cables, and a full set of AWS services.
  default = "eu-west-1"
}

variable "service_name" {
  description = "Name of the service. Used for the ECR repository and as a prefix for IAM resources."
  type        = string
  default     = "items-api"
}

variable "environment" {
  description = "Environment label used in tags."
  type        = string
  default     = "shared"
}

variable "github_repository" {
  description = "GitHub repository whose CI pipeline pushes images, as \"owner/name\"."
  type        = string
}

variable "github_oidc_subject_prefix" {
  description = "Start of the GitHub OIDC \"sub\" claim. Null means \"repo:<github_repository>\". Repositories with GitHub's immutable subject format need \"repo:<owner>@<owner id>/<name>@<repo id>\"."
  type        = string
  default     = null
}

variable "ci_allowed_refs" {
  description = "Git refs whose CI runs may push images."
  type        = list(string)
  default     = ["refs/heads/main"]
}

variable "create_github_oidc_provider" {
  description = "Create the account-wide GitHub OIDC provider. False by default because ./bootstrap creates it for the terraform roles."
  type        = bool
  default     = false
}

variable "ecr_max_image_count" {
  description = "Number of most recent images to keep in ECR."
  type        = number
  default     = 30
}

variable "ecr_untagged_expiry_days" {
  description = "Days after which untagged images are expired."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}
