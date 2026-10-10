variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
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

variable "ci_allowed_refs" {
  description = "Git refs whose CI runs may push images."
  type        = list(string)
  default     = ["refs/heads/main"]
}

variable "create_github_oidc_provider" {
  description = "Create the account-wide GitHub OIDC provider. Set to false if the account already has one."
  type        = bool
  default     = true
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
