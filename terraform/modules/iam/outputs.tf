output "cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role"
  value       = aws_iam_role.cluster.arn
}

output "node_role_arn" {
  description = "ARN of the EKS node IAM role"
  value       = aws_iam_role.node.arn
}

output "node_role_name" {
  description = "Name of the EKS node IAM role"
  value       = aws_iam_role.node.name
}

output "node_instance_profile_name" {
  description = "Name of the node instance profile"
  value       = aws_iam_instance_profile.node.name
}

output "node_instance_profile_arn" {
  description = "ARN of the node instance profile"
  value       = aws_iam_instance_profile.node.arn
}

output "karpenter_irsa_role_arn" {
  description = "ARN of the Karpenter controller IRSA role"
  value       = length(aws_iam_role.karpenter_controller) > 0 ? aws_iam_role.karpenter_controller[0].arn : ""
}

output "karpenter_irsa_role_name" {
  description = "Name of the Karpenter controller IRSA role"
  value       = length(aws_iam_role.karpenter_controller) > 0 ? aws_iam_role.karpenter_controller[0].name : ""
}

output "karpenter_instance_profile_name" {
  description = "Name of the Karpenter node instance profile"
  value       = aws_iam_instance_profile.karpenter_node.name
}

output "karpenter_instance_profile_arn" {
  description = "ARN of the Karpenter node instance profile"
  value       = aws_iam_instance_profile.karpenter_node.arn
}
