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

variable "vpc_cidr" {
  description = "CIDR block of the VPC the cluster runs in."
  type        = string
  default     = "10.0.0.0/16"
}

variable "eks_kubernetes_version" {
  description = "Kubernetes version of the EKS cluster."
  type        = string
  default     = "1.37"
}

variable "eks_admin_principal_arns" {
  description = "IAM users or roles given cluster admin. No default on purpose: a missing value fails the plan instead of locking everyone out."
  type        = list(string)
}

variable "eks_public_access_cidrs" {
  description = "CIDRs allowed to reach the cluster's public API endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "eks_node_instance_types" {
  description = "Instance types for the worker nodes."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_node_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 2
}
