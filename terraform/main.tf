# VPC Module
module "vpc" {
  source = "./modules/vpc"

  cluster_name       = local.cluster_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  environment        = var.environment
  karpenter_tags     = local.karpenter_tags
  tags               = local.common_tags
}

# IAM Module - Roles for EKS and Karpenter
module "iam" {
  source = "./modules/iam"

  cluster_name           = local.cluster_name
  karpenter_namespace    = "kube-system"
  oidc_provider_arn      = module.eks.oidc_provider_arn
  oidc_provider_url      = module.eks.oidc_provider_url
  node_instance_profile_name = "${local.cluster_name}-karpenter-node"
  tags                   = local.common_tags
}

# EKS Cluster Module
module "eks" {
  source = "./modules/eks"

  cluster_name       = local.cluster_name
  cluster_version    = var.eks_cluster_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  cluster_role_arn   = module.iam.cluster_role_arn
  node_role_arn      = module.iam.node_role_arn
  environment        = var.environment
  tags               = local.common_tags

  depends_on = [module.vpc, module.iam]
}

# Karpenter Module
module "karpenter" {
  source = "./modules/karpenter"

  count = var.enable_karpenter ? 1 : 0

  cluster_name              = local.cluster_name
  cluster_endpoint          = module.eks.cluster_endpoint
  karpenter_irsa_role_arn   = module.iam.karpenter_irsa_role_arn
  karpenter_instance_profile = module.iam.karpenter_instance_profile_name
  enable_graviton           = var.enable_graviton
  enable_spot_instances     = var.enable_spot_instances
  availability_zones        = var.availability_zones
  tags                      = local.common_tags

  depends_on = [module.eks]
}
