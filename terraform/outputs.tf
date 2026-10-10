output "ecr_repository_url" {
  description = "Registry URL for the image. Use in k8s/kustomization.yaml (images[].newName)."
  value       = module.ecr.repository_url
}

output "ecr_repository_name" {
  description = "Set as the ECR_REPOSITORY repository variable in GitHub."
  value       = module.ecr.repository_name
}

output "ci_role_arn" {
  description = "Set as the AWS_ROLE_ARN repository variable in GitHub."
  value       = module.ci_role.role_arn
}

output "aws_region" {
  description = "Set as the AWS_REGION repository variable in GitHub."
  value       = var.aws_region
}
