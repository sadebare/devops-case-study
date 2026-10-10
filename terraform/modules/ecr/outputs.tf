output "repository_arn" {
  description = "ARN of the repository."
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "Name of the repository."
  value       = aws_ecr_repository.this.name
}

output "repository_url" {
  description = "Repository URL to tag and push images to (<account>.dkr.ecr.<region>.amazonaws.com/<name>)."
  value       = aws_ecr_repository.this.repository_url
}
