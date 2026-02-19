variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
}

variable "cluster_role_arn" {
  description = "ARN of the IAM role for the EKS cluster"
  type        = string
}

variable "node_role_arn" {
  description = "ARN of the IAM role for EKS nodes"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the cluster will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_enabled_log_types" {
  description = "List of control plane logging types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "workstation_cidr_blocks" {
  description = "List of CIDR blocks for workstation access"
  type        = list(string)
  default     = []
}

variable "create_managed_node_group" {
  description = "Whether to create a managed node group for system workloads"
  type        = bool
  default     = true
}

variable "system_node_group_desired_size" {
  description = "Desired number of nodes in the system node group"
  type        = number
  default     = 2
}

variable "system_node_group_min_size" {
  description = "Minimum number of nodes in the system node group"
  type        = number
  default     = 1
}

variable "system_node_group_max_size" {
  description = "Maximum number of nodes in the system node group"
  type        = number
  default     = 3
}

variable "system_node_group_instance_types" {
  description = "Instance types for the system node group"
  type        = list(string)
  default     = ["t4g.medium"]
}

variable "vpc_cni_addon_version" {
  description = "Version of the VPC CNI addon"
  type        = string
  default     = null
}

variable "coredns_addon_version" {
  description = "Version of the CoreDNS addon"
  type        = string
  default     = null
}

variable "kube_proxy_addon_version" {
  description = "Version of the kube-proxy addon"
  type        = string
  default     = null
}

variable "ebs_csi_addon_version" {
  description = "Version of the EBS CSI driver addon"
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
