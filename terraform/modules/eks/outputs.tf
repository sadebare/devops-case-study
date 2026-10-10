output "cluster_name" {
  description = "Name of the cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "URL of the Kubernetes API."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority" {
  description = "Base64 CA certificate of the cluster."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group EKS created for the control plane and nodes."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_role_arn" {
  description = "IAM role of the worker nodes."
  value       = aws_iam_role.node.arn
}
