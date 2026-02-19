variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  type        = string
}

variable "karpenter_irsa_role_arn" {
  description = "ARN of the IAM role for Karpenter (IRSA)"
  type        = string
}

variable "karpenter_instance_profile" {
  description = "Name of the instance profile for Karpenter nodes"
  type        = string
}

variable "karpenter_version" {
  description = "Version of Karpenter to install"
  type        = string
  default     = "1.0.7"
}

variable "enable_graviton" {
  description = "Enable Graviton (ARM64) instance support"
  type        = bool
  default     = true
}

variable "enable_spot_instances" {
  description = "Enable Spot instances for cost optimization"
  type        = bool
  default     = true
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "graviton_instance_families" {
  description = "List of Graviton instance families to use"
  type        = list(string)
  default     = ["t4g", "m7g", "m6g", "c7g", "c6g", "r7g", "r6g"]
}

variable "x86_instance_families" {
  description = "List of x86 instance families to use"
  type        = list(string)
  default     = ["t3", "t3a", "m7i", "m6i", "m5", "c7i", "c6i", "c5", "r7i", "r6i", "r5"]
}

variable "graviton_node_pool_cpu_limit" {
  description = "CPU limit for Graviton node pool"
  type        = string
  default     = "1000"
}

variable "graviton_node_pool_memory_limit" {
  description = "Memory limit for Graviton node pool"
  type        = string
  default     = "1000Gi"
}

variable "x86_node_pool_cpu_limit" {
  description = "CPU limit for x86 node pool"
  type        = string
  default     = "1000"
}

variable "x86_node_pool_memory_limit" {
  description = "Memory limit for x86 node pool"
  type        = string
  default     = "1000Gi"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
