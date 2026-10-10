output "role_arn" {
  description = "ARN of the role for GitHub Actions to assume (set as the AWS_ROLE_ARN repository variable)."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the role."
  value       = aws_iam_role.this.name
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider the role trusts."
  value       = local.oidc_provider_arn
}
