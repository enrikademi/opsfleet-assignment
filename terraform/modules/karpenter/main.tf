# Karpenter Helm Release
resource "helm_release" "karpenter" {
  namespace        = "kube-system"
  create_namespace = false
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_version
  wait             = true

  values = [
    yamlencode({
      settings = {
        clusterName     = var.cluster_name
        clusterEndpoint = var.cluster_endpoint
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = var.karpenter_irsa_role_arn
        }
      }
      controller = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "1000m"
            memory = "1Gi"
          }
        }
      }
      replicas = 2
      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
        }
      ]
      affinity = {
        nodeAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = {
            nodeSelectorTerms = [
              {
                matchExpressions = [
                  {
                    key      = "karpenter.sh/capacity-type"
                    operator = "NotIn"
                    values   = ["spot"]
                  }
                ]
              }
            ]
          }
        }
      }
    })
  ]
}

# Karpenter NodePool for Graviton (ARM64) + Spot
resource "kubectl_manifest" "karpenter_node_pool_graviton" {
  count = var.enable_graviton ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "graviton-spot"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "workload-type" = "general"
            "arch"          = "arm64"
          }
        }
        spec = {
          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["arm64"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = var.enable_spot_instances ? ["spot", "on-demand"] : ["on-demand"]
            },
            {
              key      = "karpenter.k8s.aws/instance-family"
              operator = "In"
              values   = var.graviton_instance_families
            },
            {
              key      = "karpenter.k8s.aws/instance-category"
              operator = "In"
              values   = ["c", "m", "r", "t"]
            },
            {
              key      = "topology.kubernetes.io/zone"
              operator = "In"
              values   = var.availability_zones
            }
          ]
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "graviton"
          }
          taints = []
        }
      }
      limits = {
        cpu    = var.graviton_node_pool_cpu_limit
        memory = var.graviton_node_pool_memory_limit
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
        budgets = [
          {
            nodes = "10%"
          }
        ]
      }
      weight = 10
    }
  })

  depends_on = [helm_release.karpenter]
}

# Karpenter NodePool for x86 + Spot
resource "kubectl_manifest" "karpenter_node_pool_x86" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "x86-spot"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "workload-type" = "general"
            "arch"          = "amd64"
          }
        }
        spec = {
          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = var.enable_spot_instances ? ["spot", "on-demand"] : ["on-demand"]
            },
            {
              key      = "karpenter.k8s.aws/instance-family"
              operator = "In"
              values   = var.x86_instance_families
            },
            {
              key      = "karpenter.k8s.aws/instance-category"
              operator = "In"
              values   = ["c", "m", "r", "t"]
            },
            {
              key      = "topology.kubernetes.io/zone"
              operator = "In"
              values   = var.availability_zones
            }
          ]
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "x86"
          }
          taints = []
        }
      }
      limits = {
        cpu    = var.x86_node_pool_cpu_limit
        memory = var.x86_node_pool_memory_limit
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
        budgets = [
          {
            nodes = "10%"
          }
        ]
      }
      weight = 5
    }
  })

  depends_on = [helm_release.karpenter]
}

# EC2NodeClass for Graviton instances
resource "kubectl_manifest" "karpenter_ec2_node_class_graviton" {
  count = var.enable_graviton ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "graviton"
    }
    spec = {
      amiFamily = "AL2023"
      amiSelectorTerms = [
        {
          alias = "al2023@latest"
        }
      ]
      role = var.karpenter_instance_profile
      subnetSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]
      securityGroupSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]
      userData = <<-EOT
        #!/bin/bash
        echo "Karpenter Graviton Node - ARM64"
      EOT
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "20Gi"
            volumeType          = "gp3"
            encrypted           = true
            deleteOnTermination = true
          }
        }
      ]
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpProtocolIPv6        = "disabled"
        httpPutResponseHopLimit = 1
        httpTokens              = "required"
      }
      tags = merge(
        var.tags,
        {
          Name                        = "${var.cluster_name}-karpenter-graviton"
          "karpenter.sh/discovery"    = var.cluster_name
          "karpenter.sh/managed-by"   = var.cluster_name
        }
      )
    }
  })

  depends_on = [helm_release.karpenter]
}

# EC2NodeClass for x86 instances
resource "kubectl_manifest" "karpenter_ec2_node_class_x86" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "x86"
    }
    spec = {
      amiFamily = "AL2023"
      amiSelectorTerms = [
        {
          alias = "al2023@latest"
        }
      ]
      role = var.karpenter_instance_profile
      subnetSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]
      securityGroupSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]
      userData = <<-EOT
        #!/bin/bash
        echo "Karpenter x86 Node - AMD64"
      EOT
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "20Gi"
            volumeType          = "gp3"
            encrypted           = true
            deleteOnTermination = true
          }
        }
      ]
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpProtocolIPv6        = "disabled"
        httpPutResponseHopLimit = 1
        httpTokens              = "required"
      }
      tags = merge(
        var.tags,
        {
          Name                        = "${var.cluster_name}-karpenter-x86"
          "karpenter.sh/discovery"    = var.cluster_name
          "karpenter.sh/managed-by"   = var.cluster_name
        }
      )
    }
  })

  depends_on = [helm_release.karpenter]
}
