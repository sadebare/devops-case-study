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
  subject_prefix       = var.github_oidc_subject_prefix
  allowed_refs         = var.ci_allowed_refs
  ecr_repository_arns  = [module.ecr.repository_arn]
  create_oidc_provider = var.create_github_oidc_provider
}

module "vpc" {
  source = "./modules/vpc"

  name = var.service_name
  cidr = var.vpc_cidr
}

module "eks" {
  source = "./modules/eks"

  name                 = var.service_name
  kubernetes_version   = var.eks_kubernetes_version
  subnet_ids           = module.vpc.private_subnet_ids
  public_access_cidrs  = var.eks_public_access_cidrs
  admin_principal_arns = var.eks_admin_principal_arns
  node_instance_types  = var.eks_node_instance_types
  node_count           = var.eks_node_count

  # The nodes can pull this one repository and nothing else of ours.
  ecr_repository_arns = [module.ecr.repository_arn]
}
