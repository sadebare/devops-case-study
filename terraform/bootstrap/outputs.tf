output "state_bucket_name" {
  description = "Put this in terraform/backend.hcl as `bucket`, and set it as the TF_STATE_BUCKET repository variable in GitHub."
  value       = module.state_bucket.bucket_name
}

output "state_bucket_arn" {
  description = "ARN of the state bucket."
  value       = module.state_bucket.bucket_arn
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider. The main configuration looks it up by URL."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "terraform_plan_role_arn" {
  description = "Set as the TF_PLAN_ROLE_ARN repository variable in GitHub."
  value       = aws_iam_role.terraform["plan"].arn
}

output "terraform_apply_role_arn" {
  description = "Set as the TF_APPLY_ROLE_ARN repository variable in GitHub."
  value       = aws_iam_role.terraform["apply"].arn
}
