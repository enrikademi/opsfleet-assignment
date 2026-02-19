locals {
  cluster_name = "${var.project_name}-${var.environment}-eks"
  
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Owner       = "DevOps"
    },
    var.tags
  )

  # Karpenter discovery tags
  karpenter_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }
}
