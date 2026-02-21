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

# IAM Module - Basic roles (cluster and node roles)
module "iam" {
  source = "./modules/iam"

  cluster_name               = local.cluster_name
  karpenter_namespace        = "kube-system"
  oidc_provider_arn          = "" # Empty - no Karpenter role yet
  oidc_provider_url          = ""
  node_instance_profile_name = "${local.cluster_name}-karpenter-node"
  tags                       = local.common_tags
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

# Karpenter Controller IAM Role (created after EKS for IRSA)
resource "aws_iam_role" "karpenter_controller" {
  name = "${local.cluster_name}-karpenter-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(module.eks.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:karpenter"
            "${replace(module.eks.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags

  depends_on = [module.eks]
}

resource "aws_iam_policy" "karpenter_controller" {
  name        = "${local.cluster_name}-karpenter-controller"
  description = "IAM policy for Karpenter controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowScopedEC2InstanceActions"
        Effect = "Allow"
        Action = ["ec2:RunInstances"]
        Resource = [
          "arn:aws:ec2:*:*:launch-template/*",
          "arn:aws:ec2:*:*:security-group/*",
          "arn:aws:ec2:*:*:subnet/*",
          "arn:aws:ec2:*:*:network-interface/*",
          "arn:aws:ec2:*::image/*",
          "arn:aws:ec2:*::snapshot/*"
        ]
      },
      {
        Sid      = "AllowFleetCreation"
        Effect   = "Allow"
        Action   = ["ec2:CreateFleet", "ec2:CreateTags"]
        Resource = ["arn:aws:ec2:*:*:fleet/*", "arn:aws:ec2:*:*:instance/*", "arn:aws:ec2:*:*:volume/*", "arn:aws:ec2:*:*:network-interface/*", "arn:aws:ec2:*:*:launch-template/*", "arn:aws:ec2:*:*:spot-instances-request/*"]
      },
      {
        Sid      = "AllowLaunchTemplateManagement"
        Effect   = "Allow"
        Action   = ["ec2:CreateLaunchTemplate", "ec2:DescribeLaunchTemplates", "ec2:DeleteLaunchTemplate"]
        Resource = "*"
      },
      {
        Sid    = "AllowScopedEC2InstanceActionsWithTags"
        Effect = "Allow"
        Action = ["ec2:RunInstances", "ec2:CreateFleet"]
        Resource = ["arn:aws:ec2:*:*:instance/*", "arn:aws:ec2:*:*:spot-instances-request/*", "arn:aws:ec2:*:*:volume/*", "arn:aws:ec2:*::image/*", "arn:aws:ec2:*::snapshot/*", "arn:aws:ec2:*:*:network-interface/*"]
      },
      {
        Sid      = "AllowScopedResourceCreationTagging"
        Effect   = "Allow"
        Action   = "ec2:CreateTags"
        Resource = ["arn:aws:ec2:*:*:instance/*", "arn:aws:ec2:*:*:spot-instances-request/*", "arn:aws:ec2:*:*:volume/*", "arn:aws:ec2:*:*:launch-template/*"]
      },
      {
        Sid      = "AllowScopedDeletion"
        Effect   = "Allow"
        Action   = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
        Resource = ["arn:aws:ec2:*:*:instance/*", "arn:aws:ec2:*:*:launch-template/*"]
      },
      {
        Sid    = "AllowRegionalReadActions"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones", "ec2:DescribeImages", "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings", "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates", "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory", "ec2:DescribeSubnets"
        ]
        Resource = "*"
      },
      {
        Sid      = "AllowSSMReadActions"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = "arn:aws:ssm:*:*:parameter/aws/service/*"
      },
      {
        Sid      = "AllowPricingReadActions"
        Effect   = "Allow"
        Action   = "pricing:GetProducts"
        Resource = "*"
      },
      {
        Sid      = "AllowPassingInstanceRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = module.iam.node_role_arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },
      {
        Sid    = "AllowInstanceProfileManagement"
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile"
        ]
        Resource = "arn:aws:iam::*:instance-profile/*"
      },
      {
        Sid      = "AllowAPIServerEndpointDiscovery"
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = "arn:aws:eks:*:*:cluster/${local.cluster_name}"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  policy_arn = aws_iam_policy.karpenter_controller.arn
  role       = aws_iam_role.karpenter_controller.name
}

# Karpenter Module
module "karpenter" {
  source = "./modules/karpenter"

  count = var.enable_karpenter ? 1 : 0

  cluster_name               = local.cluster_name
  cluster_endpoint           = module.eks.cluster_endpoint
  karpenter_irsa_role_arn    = aws_iam_role.karpenter_controller.arn
  karpenter_instance_profile = module.iam.node_role_name
  enable_graviton            = var.enable_graviton
  enable_spot_instances      = var.enable_spot_instances
  availability_zones         = var.availability_zones
  tags                       = local.common_tags

  depends_on = [module.eks, aws_iam_role.karpenter_controller]
}
