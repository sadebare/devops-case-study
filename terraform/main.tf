module "ecr" {
  source = "./modules/ecr"

  name                 = var.service_name
  max_image_count      = var.ecr_max_image_count
  untagged_expiry_days = var.ecr_untagged_expiry_days
}

module "ci_role" {
  source = "./modules/github-oidc-role"

  role_name            = "${var.service_name}-github-actions"
  github_repository    = var.github_repository
  allowed_refs         = var.ci_allowed_refs
  ecr_repository_arns  = [module.ecr.repository_arn]
  create_oidc_provider = var.create_github_oidc_provider
}
