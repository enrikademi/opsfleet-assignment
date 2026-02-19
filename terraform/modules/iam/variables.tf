variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "karpenter_namespace" {
  description = "Kubernetes namespace for Karpenter"
  type        = string
  default     = "kube-system"
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for EKS"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the OIDC provider for EKS"
  type        = string
}

variable "node_instance_profile_name" {
  description = "Name for the Karpenter node instance profile"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
