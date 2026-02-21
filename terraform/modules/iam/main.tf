# EKS Cluster IAM Role
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

# EKS Node IAM Role
resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_ecr_read_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.node.name
}

# Instance Profile for Nodes
resource "aws_iam_instance_profile" "node" {
  name = "${var.cluster_name}-node-instance-profile"
  role = aws_iam_role.node.name

  tags = var.tags
}

# Karpenter Controller IAM Role (IRSA)
# Only create if OIDC provider details are available
resource "aws_iam_role" "karpenter_controller" {
  count = var.oidc_provider_arn != "" ? 1 : 0
  
  name = "${var.cluster_name}-karpenter-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:${var.karpenter_namespace}:karpenter"
            "${replace(var.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_policy" "karpenter_controller" {
  count = var.oidc_provider_arn != "" ? 1 : 0
  
  name        = "${var.cluster_name}-karpenter-controller"
  description = "IAM policy for Karpenter controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowScopedEC2InstanceActions"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]
        Resource = [
          "arn:aws:ec2:*:*:launch-template/*",
          "arn:aws:ec2:*:*:security-group/*",
          "arn:aws:ec2:*:*:subnet/*",
          "arn:aws:ec2:*:*:network-interface/*"
        ]
      },
      {
        Sid    = "AllowScopedEC2InstanceActionsWithTags"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]
        Resource = [
          "arn:aws:ec2:*:*:instance/*",
          "arn:aws:ec2:*:*:spot-instances-request/*",
          "arn:aws:ec2:*:*:volume/*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedResourceCreationTagging"
        Effect = "Allow"
        Action = "ec2:CreateTags"
        Resource = [
          "arn:aws:ec2:*:*:instance/*",
          "arn:aws:ec2:*:*:spot-instances-request/*",
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:launch-template/*"
        ]
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = [
              "RunInstances",
              "CreateFleet",
              "CreateLaunchTemplate"
            ]
          }
        }
      },
      {
        Sid    = "AllowMachineMigrationTagging"
        Effect = "Allow"
        Action = "ec2:CreateTags"
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/karpenter.sh/managed-by" = var.cluster_name
          }
        }
      },
      {
        Sid    = "AllowScopedDeletion"
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate"
        ]
        Resource = [
          "arn:aws:ec2:*:*:instance/*",
          "arn:aws:ec2:*:*:launch-template/*"
        ]
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/karpenter.sh/managed-by" = var.cluster_name
          }
        }
      },
      {
        Sid    = "AllowRegionalReadActions"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = "*"
          }
        }
      },
      {
        Sid    = "AllowSSMReadActions"
        Effect = "Allow"
        Action = "ssm:GetParameter"
        Resource = "arn:aws:ssm:*:*:parameter/aws/service/*"
      },
      {
        Sid    = "AllowPricingReadActions"
        Effect = "Allow"
        Action = "pricing:GetProducts"
        Resource = "*"
      },
      {
        Sid    = "AllowPassingInstanceRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = aws_iam_role.node.arn
      },
      {
        Sid    = "AllowScopedInstanceProfileCreationActions"
        Effect = "Allow"
        Action = "iam:CreateInstanceProfile"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedInstanceProfileTagActions"
        Effect = "Allow"
        Action = "iam:TagInstanceProfile"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedInstanceProfileActions"
        Effect = "Allow"
        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/karpenter.sh/managed-by" = var.cluster_name
          }
        }
      },
      {
        Sid    = "AllowInstanceProfileReadActions"
        Effect = "Allow"
        Action = "iam:GetInstanceProfile"
        Resource = "*"
      },
      {
        Sid    = "AllowAPIServerEndpointDiscovery"
        Effect = "Allow"
        Action = "eks:DescribeCluster"
        Resource = "arn:aws:eks:*:*:cluster/${var.cluster_name}"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  count = var.oidc_provider_arn != "" ? 1 : 0
  
  policy_arn = aws_iam_policy.karpenter_controller[0].arn
  role       = aws_iam_role.karpenter_controller[0].name
}

# Karpenter Node IAM Role (for instances provisioned by Karpenter)
resource "aws_iam_instance_profile" "karpenter_node" {
  name = var.node_instance_profile_name
  role = aws_iam_role.node.name

  tags = var.tags
}
