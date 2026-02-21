# AWS EKS with Karpenter, Graviton, and Spot Instances

This Terraform project automates the deployment of a production-ready Amazon EKS cluster with Karpenter for intelligent autoscaling, leveraging AWS Graviton (ARM64) processors and Spot instances for optimal price-performance.

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS ACCOUNT                                    │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         VPC (10.0.0.0/16)                             │  │
│  │                                                                       │  │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐   │  │
│  │  │ Public Subnets   │  │ Private Subnets  │  │  Data Subnets    │   │  │
│  │  │  (Multi-AZ)      │  │  (Multi-AZ)      │  │  (Multi-AZ)      │   │  │
│  │  │                  │  │                  │  │                  │   │  │
│  │  │  ┌────────────┐  │  │  ┌────────────────────────────────┐   │   │  │
│  │  │  │ ALB/NLB    │  │  │  │      EKS CLUSTER              │   │   │  │
│  │  │  │ (Future)   │  │  │  │  ┌──────────────────────────┐ │   │   │  │
│  │  │  └────────────┘  │  │  │  │  KARPENTER CONTROLLER   │ │   │   │  │
│  │  │                  │  │  │  └──────────────────────────┘ │   │   │  │
│  │  │  ┌────────────┐  │  │  │                              │   │   │  │
│  │  │  │ NAT GW     │  │  │  │  ┌──────────────────────────┐ │   │   │  │
│  │  │  │ (Per AZ)   │  │  │  │  │ System Node Group        │ │   │   │  │
│  │  │  └────────────┘  │  │  │  │ (Graviton t4g.medium)    │ │   │   │  │
│  │  │                  │  │  │  │ On-Demand, ARM64         │ │   │   │  │
│  │  │  ┌────────────┐  │  │  │  └──────────────────────────┘ │   │   │  │
│  │  │  │ Internet   │  │  │  │                              │   │   │  │
│  │  │  │ Gateway    │  │  │  │  ┌──────────────────────────┐ │   │   │  │
│  │  │  └────────────┘  │  │  │  │ Karpenter-Provisioned   │ │   │   │  │
│  │  └──────────────────┘  │  │  │ Nodes (Dynamic)         │ │   │   │  │
│  │                        │  │  │                          │ │   │   │  │
│  │                        │  │  │ • Graviton (m7g, c7g)   │ │   │   │  │
│  │                        │  │  │ • x86 (m7i, c7i)        │ │   │   │  │
│  │                        │  │  │ • Spot + On-Demand      │ │   │   │  │
│  │                        │  │  │ • Multi-AZ              │ │   │   │  │
│  │                        │  │  └──────────────────────────┘ │   │   │  │
│  │                        │  └────────────────────────────────┘   │   │  │
│  │                        │                                       │   │  │
│  │                        │  ┌──────────────────┐                │   │  │
│  │                        │  │ RDS / ElastiCache│                │   │  │
│  │                        │  │    (Future)      │                │   │  │
│  │                        │  └──────────────────┘                │   │  │
│  │                        └───────────────────────────────────────┘   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## ✨ Features

- **🚀 EKS Cluster**: Latest Kubernetes version (1.31) with managed control plane
- **⚡ Karpenter**: Intelligent, cost-aware autoscaling that provisions nodes in seconds
- **💪 Graviton Support**: ARM64 instances (t4g, m7g, c7g, r7g) for 40% better price-performance
- **💰 Spot Instances**: Up to 90% cost savings with automatic fallback to On-Demand
- **🌐 Multi-AZ**: High availability across 3 availability zones
- **🔒 Security**: Private subnets, IRSA (IAM Roles for Service Accounts), encrypted EBS volumes
- **📊 Observability**: VPC Flow Logs, EKS control plane logs
- **🏗️ Modular Design**: Clean, reusable Terraform modules

## 📋 Prerequisites

Before you begin, ensure you have the following installed and configured:

- **Terraform** >= 1.6.0 ([Install](https://developer.hashicorp.com/terraform/downloads))
- **AWS CLI** >= 2.x ([Install](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))
- **kubectl** >= 1.28 ([Install](https://kubernetes.io/docs/tasks/tools/))
- **Helm** >= 3.12 (optional, for additional deployments) ([Install](https://helm.sh/docs/intro/install/))

### AWS Credentials

Configure your AWS credentials:

```bash
aws configure
```

Or export environment variables:

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

Ensure your AWS user/role has sufficient permissions to create:
- VPC, Subnets, Route Tables, NAT Gateways, Internet Gateways
- EKS Clusters, Node Groups
- IAM Roles, Policies, Instance Profiles
- EC2 Security Groups
- CloudWatch Log Groups

## 🚀 Quick Start

### 1. Clone and Navigate

```bash
git clone <your-repo-url>
cd terraform/
```

### 2. Configure Variables

Copy the example variables file and customize:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region         = "us-east-1"
project_name       = "opsfleet"
environment        = "dev"
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
eks_cluster_version = "1.31"
enable_karpenter    = true
enable_graviton     = true
enable_spot_instances = true
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Review the Plan

```bash
terraform plan
```

Expected resources: ~60-70 resources including:
- 1 VPC with 9 subnets (3 public, 3 private, 3 data)
- 3 NAT Gateways (one per AZ)
- 1 EKS Cluster
- 1 Managed Node Group (system nodes)
- IAM Roles and Policies
- Karpenter Helm release
- 2 Karpenter NodePools (Graviton + x86)
- 2 EC2NodeClasses

### 5. Deploy Infrastructure

```bash
terraform apply
```

⏱️ **Deployment time**: Approximately 15-20 minutes

### 6. Configure kubectl

Once deployment is complete, configure kubectl to access your cluster:

```bash
aws eks update-kubeconfig --region us-east-1 --name opsfleet-dev-eks
```

Verify cluster access:

```bash
kubectl get nodes
kubectl get pods -A
```

## 📦 Project Structure

```
terraform/
├── README.md                          # This file
├── versions.tf                        # Terraform and provider versions
├── providers.tf                       # AWS, Kubernetes, Helm providers
├── variables.tf                       # Input variables
├── locals.tf                          # Local values and computed variables
├── main.tf                            # Root module orchestration
├── outputs.tf                         # Output values
├── terraform.tfvars.example           # Example variables file
├── backend.tf.example                 # Example remote state configuration
├── .gitignore                         # Git ignore rules
│
├── modules/
│   ├── vpc/                           # VPC with public/private/data subnets
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── iam/                           # IAM roles for EKS and Karpenter
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── eks/                           # EKS cluster and managed node group
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── karpenter/                     # Karpenter installation and NodePools
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
└── examples/                          # Kubernetes deployment examples
    ├── graviton-deployment.yaml       # ARM64-specific deployment
    ├── x86-deployment.yaml            # x86-specific deployment
    ├── mixed-deployment.yaml          # Multi-arch deployment
    └── spot-only-deployment.yaml      # Spot-only deployment
```

## 🎯 Using the Cluster

### Deploying Workloads on Graviton (ARM64)

Karpenter will automatically provision ARM64 nodes when you deploy pods with the appropriate node selector:

```bash
kubectl apply -f examples/graviton-deployment.yaml
```

**Key configuration in the manifest:**

```yaml
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/arch: arm64
      containers:
      - name: nginx
        image: nginx:1.27-alpine  # Multi-arch image
```

**Verify deployment:**

```bash
# Check pods
kubectl get pods -l arch=arm64 -o wide

# Check nodes (you should see ARM64 nodes)
kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type

# Describe a node to see instance type (e.g., m7g.large)
kubectl describe node <node-name>
```

### Deploying Workloads on x86 (AMD64)

```bash
kubectl apply -f examples/x86-deployment.yaml
```

**Key configuration:**

```yaml
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/arch: amd64
```

### Deploying Multi-Architecture Workloads

For maximum flexibility and cost optimization, let Karpenter choose the best instance type:

```bash
kubectl apply -f examples/mixed-deployment.yaml
```

**Key configuration:**

```yaml
spec:
  template:
    spec:
      # No architecture constraint - Karpenter decides
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: karpenter.sh/capacity-type
                operator: In
                values:
                - spot  # Prefer Spot for cost savings
```

### Spot-Only Deployments (Maximum Cost Savings)

For fault-tolerant, stateless workloads:

```bash
kubectl apply -f examples/spot-only-deployment.yaml
```

**Key configuration:**

```yaml
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: karpenter.sh/capacity-type
                operator: In
                values:
                - spot  # Only Spot instances
```

## 🔍 Monitoring Karpenter

### View Karpenter Logs

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f
```

### Check NodePools

```bash
kubectl get nodepools
kubectl describe nodepool graviton-spot
kubectl describe nodepool x86-spot
```

### Check EC2NodeClasses

```bash
kubectl get ec2nodeclasses
kubectl describe ec2nodeclass graviton
kubectl describe ec2nodeclass x86
```

### Monitor Node Provisioning

```bash
# Watch nodes being created
kubectl get nodes -w

# See Karpenter events
kubectl get events -n kube-system --sort-by='.lastTimestamp' | grep -i karpenter
```

## 💰 Cost Optimization

This setup is designed for maximum cost efficiency:

| Component | Strategy | Estimated Savings |
|-----------|----------|-------------------|
| **System Nodes** | Graviton t4g.medium (ARM64) | 20% vs t3.medium |
| **Application Nodes** | Karpenter with Spot priority | Up to 90% vs On-Demand |
| **Graviton Instances** | m7g, c7g, r7g families | 40% better price-performance |
| **Multi-AZ NAT** | 3 NAT Gateways for HA | Can reduce to 1 for dev ($90/mo savings) |
| **Right-sizing** | Karpenter auto-consolidation | 10-30% reduction in node count |

**Example monthly cost (dev environment, light usage):**
- EKS Control Plane: $73
- 2x t4g.medium (system nodes): ~$30
- NAT Gateways (3x): ~$100
- Data transfer: ~$20
- **Total: ~$223/month**

With Spot + Graviton for application workloads, you can run significant workloads for minimal additional cost.

## 🔒 Security Best Practices

This infrastructure implements several security best practices:

- ✅ **Private Subnets**: EKS nodes run in private subnets with no direct internet access
- ✅ **IRSA**: IAM Roles for Service Accounts for fine-grained pod permissions
- ✅ **Encrypted EBS**: All node volumes encrypted at rest
- ✅ **IMDSv2**: Enforced on all nodes (token-required)
- ✅ **Security Groups**: Managed by EKS with least-privilege rules
- ✅ **Control Plane Logging**: All log types enabled (api, audit, authenticator, etc.)
- ✅ **VPC Flow Logs**: Network traffic monitoring
- ✅ **No SSH Keys**: Use AWS Systems Manager Session Manager for node access

### Accessing Nodes (Without SSH)

```bash
# List nodes
kubectl get nodes

# Get node instance ID
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*karpenter*" \
  --query 'Reservations[*].Instances[*].[InstanceId,PrivateIpAddress,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# Connect via SSM
aws ssm start-session --target <instance-id>
```

## 🧪 Testing the Setup

### 1. Deploy Test Workload

```bash
kubectl apply -f examples/mixed-deployment.yaml
```

### 2. Scale Up

```bash
kubectl scale deployment nginx-mixed --replicas=20
```

Watch Karpenter provision new nodes:

```bash
kubectl get nodes -w
```

### 3. Check Node Types

```bash
kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type,node.kubernetes.io/instance-type
```

You should see a mix of:
- **Architecture**: arm64 (Graviton) and amd64 (x86)
- **Capacity Type**: spot and on-demand
- **Instance Types**: t4g, m7g, c7g (Graviton) or t3, m7i, c7i (x86)

### 4. Test Spot Interruption Handling

Karpenter automatically handles Spot interruptions. To simulate:

```bash
# Karpenter will gracefully drain and replace the node
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

### 5. Scale Down

```bash
kubectl scale deployment nginx-mixed --replicas=3
```

Karpenter will consolidate nodes after 1 minute (configured in NodePool).

## 🛠️ Customization

### Change Instance Types

Edit `modules/karpenter/variables.tf`:

```hcl
variable "graviton_instance_families" {
  default = ["m7g", "c7g", "r7g"]  # Add or remove families
}
```

### Adjust Node Pool Limits

Edit `modules/karpenter/variables.tf`:

```hcl
variable "graviton_node_pool_cpu_limit" {
  default = "500"  # Reduce for cost control
}
```

### Disable Graviton or Spot

In `terraform.tfvars`:

```hcl
enable_graviton       = false  # Use only x86
enable_spot_instances = false  # Use only On-Demand
```

### Change EKS Version

```hcl
eks_cluster_version = "1.30"  # Or latest available
```

## 🔄 Updating the Cluster

### Update Terraform Configuration

```bash
# Pull latest changes
git pull

# Review changes
terraform plan

# Apply updates
terraform apply
```

### Update EKS Version

1. Update `eks_cluster_version` in `terraform.tfvars`
2. Apply changes:

```bash
terraform apply
```

3. Update node groups (Karpenter will handle this automatically)

### Update Karpenter

1. Update `karpenter_version` in `modules/karpenter/variables.tf`
2. Apply:

```bash
terraform apply
```

## 🧹 Cleanup

To destroy all resources:

```bash
# Delete all workloads first
kubectl delete all --all -n default

# Wait for Karpenter to clean up nodes
sleep 60

# Destroy infrastructure
terraform destroy
```

⚠️ **Warning**: This will delete:
- EKS cluster and all workloads
- All nodes (managed and Karpenter-provisioned)
- VPC and networking components
- IAM roles and policies

## 📚 Additional Resources

- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Karpenter Documentation](https://karpenter.sh/)
- [AWS Graviton](https://aws.amazon.com/ec2/graviton/)
- [EKS Spot Best Practices](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html#managed-node-group-capacity-types-spot)

## 🐛 Troubleshooting

### Issue: Karpenter not provisioning nodes

**Check Karpenter logs:**

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=100
```

**Common causes:**
- Insufficient IAM permissions
- No matching NodePool for pod requirements
- Instance type not available in AZ
- Spot capacity unavailable (will fallback to On-Demand)

### Issue: Pods stuck in Pending

**Check pod events:**

```bash
kubectl describe pod <pod-name>
```

**Common causes:**
- No NodePool matches pod's node selectors
- Resource limits exceeded in NodePool
- Image not available for target architecture (arm64 vs amd64)

**Solution**: Ensure you're using multi-arch images or specify correct architecture.

### Issue: Terraform apply fails

**Common causes:**
- AWS credentials not configured
- Insufficient permissions
- Resource limits exceeded (e.g., VPC limit, EIP limit)
- Region doesn't support Graviton instances

**Check AWS limits:**

```bash
aws service-quotas list-service-quotas --service-code ec2
```

### Issue: kubectl connection refused

**Re-configure kubectl:**

```bash
aws eks update-kubeconfig --region us-east-1 --name opsfleet-dev-eks
```

**Check cluster status:**

```bash
aws eks describe-cluster --name opsfleet-dev-eks --region us-east-1
```

## 📝 Important Notes

### Multi-Architecture Images

When deploying workloads that can run on both x86 and ARM64:

✅ **Use multi-arch images:**
- `nginx:1.27-alpine`
- `redis:7-alpine`
- `postgres:16-alpine`
- Most official Docker Hub images

❌ **Avoid architecture-specific images:**
- Images built only for amd64
- Images with native dependencies not compiled for arm64

**Check image architecture:**

```bash
docker manifest inspect nginx:1.27-alpine | jq '.manifests[].platform'
```

### Spot Instance Considerations

Spot instances can be interrupted with 2-minute notice:

- ✅ **Good for**: Stateless apps, batch jobs, CI/CD workers, dev/test
- ❌ **Avoid for**: Databases, stateful apps (without proper handling), single-replica critical services

Karpenter handles interruptions gracefully by:
1. Receiving interruption notice
2. Cordoning the node
3. Draining pods to other nodes
4. Provisioning replacement capacity

### Cost Monitoring

Track your costs:

```bash
# Get current month costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=SERVICE
```

Set up AWS Budgets for alerts.

## 👥 Contributing

This is an assessment project, but suggestions are welcome!

## 📄 License

This project is provided as-is for demonstration purposes.

---

**Built with ❤️ for Opsfleet DevOps Assessment**

For questions or issues, please reach out to the team.
