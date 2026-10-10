# EKS creates this log group itself if it is missing, but with no expiry.
# Creating it first keeps the retention under our control.
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_eks_cluster" "this" {
  name     = var.name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  # Who called the API, and who logged in. The "api" log type is far noisier
  # and rarely needed.
  enabled_cluster_log_types = ["audit", "authenticator"]

  # The add-ons below are EKS-managed instead, so they can be upgraded with
  # the cluster.
  bootstrap_self_managed_addons = false

  # Access entries only, no aws-auth ConfigMap. The creator (the CI apply
  # role) is not made an admin; admins are listed in admin_principal_arns.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true # nodes reach the API without leaving the VPC
    endpoint_public_access  = true # kubectl from a laptop; narrow the CIDRs below
    public_access_cidrs     = var.public_access_cidrs
  }

  # Standard support only. Extended support is charged at 6x the hourly rate,
  # so an old version gets upgraded instead of silently costing more.
  upgrade_policy {
    support_type = "STANDARD"
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]
}

resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  tags          = var.tags
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.admin[each.value].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# ---- add-ons ----------------------------------------------------------------
# No addon_version: EKS installs the default version for the cluster version.

# Networking must exist before nodes join, or they never become Ready.
# enableNetworkPolicy turns on the policy agent, which is what enforces
# the chart's NetworkPolicies. Without it those policies are silently ignored.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  configuration_values        = jsonencode({ enableNetworkPolicy = "true" })
  tags                        = var.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  tags                        = var.tags
}

# CoreDNS is a Deployment, so it needs nodes to schedule onto.
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  tags                        = var.tags

  depends_on = [aws_eks_node_group.this]
}

# ---- worker nodes -----------------------------------------------------------

resource "aws_launch_template" "node" {
  name_prefix            = "${var.name}-node-"
  description            = "Worker nodes of ${var.name}."
  update_default_version = true

  # IMDSv2 only, and a hop limit of 1 so pods cannot reach the instance
  # metadata service and borrow the node's IAM role.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name}-node" })
  }

  tags = var.tags
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.node_count
    min_size     = var.node_count
    max_size     = var.node_count + 1 # room for a surge node during upgrades
  }

  # Replace one node at a time, so the PodDisruptionBudget always has a node
  # to keep a replica on.
  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_iam_role_policy.node_ecr_pull,
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
  ]
}
