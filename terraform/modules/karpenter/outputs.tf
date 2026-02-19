output "karpenter_release_name" {
  description = "Name of the Karpenter Helm release"
  value       = helm_release.karpenter.name
}

output "karpenter_namespace" {
  description = "Namespace where Karpenter is installed"
  value       = helm_release.karpenter.namespace
}

output "karpenter_version" {
  description = "Version of Karpenter installed"
  value       = helm_release.karpenter.version
}

output "graviton_node_pool_enabled" {
  description = "Whether Graviton node pool is enabled"
  value       = var.enable_graviton
}

output "spot_instances_enabled" {
  description = "Whether Spot instances are enabled"
  value       = var.enable_spot_instances
}
