# Quick Start Guide

## ⚡ 5-Minute Setup

### Prerequisites Check

```bash
# Check Terraform
terraform version  # Should be >= 1.6.0

# Check AWS CLI
aws --version      # Should be >= 2.x

# Check AWS credentials
aws sts get-caller-identity

# Check kubectl
kubectl version --client
```

### Deploy

```bash
# 1. Clone and navigate
cd terraform/

# 2. Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your preferred settings

# 3. Initialize
terraform init

# 4. Deploy (takes ~15-20 minutes)
terraform apply -auto-approve

# 5. Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name opsfleet-dev-eks

# 6. Verify
kubectl get nodes
kubectl get pods -A
```

### Test Karpenter

```bash
# Deploy test workload
kubectl apply -f examples/mixed-deployment.yaml

# Watch Karpenter provision nodes
kubectl get nodes -w

# Check node types
kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type,node.kubernetes.io/instance-type

# Scale up
kubectl scale deployment nginx-mixed --replicas=20

# Scale down
kubectl scale deployment nginx-mixed --replicas=2
```

## 🎯 Common Tasks

### Deploy on Graviton (ARM64)

```bash
kubectl apply -f examples/graviton-deployment.yaml
kubectl get pods -l arch=arm64 -o wide
```

### Deploy on x86

```bash
kubectl apply -f examples/x86-deployment.yaml
kubectl get pods -l arch=amd64 -o wide
```

### Deploy on Spot Only

```bash
kubectl apply -f examples/spot-only-deployment.yaml
```

### View Karpenter Logs

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f
```

### Check NodePools

```bash
kubectl get nodepools
kubectl describe nodepool graviton-spot
```

### Access a Node (via SSM)

```bash
# Get instance ID
aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/managed-by,Values=opsfleet-dev-eks" \
  --query 'Reservations[*].Instances[*].[InstanceId,PrivateIpAddress]' \
  --output table

# Connect
aws ssm start-session --target <instance-id>
```

## 🧹 Cleanup

```bash
# Delete workloads
kubectl delete all --all -n default

# Wait for nodes to drain
sleep 60

# Destroy infrastructure
terraform destroy -auto-approve
```

## 🐛 Quick Troubleshooting

### Pods stuck in Pending

```bash
# Check pod events
kubectl describe pod <pod-name>

# Check Karpenter logs
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=50

# Check NodePools
kubectl get nodepools
```

### Karpenter not provisioning

```bash
# Check Karpenter status
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter

# Check IAM role
aws iam get-role --role-name opsfleet-dev-eks-karpenter-controller

# Check instance profile
aws iam get-instance-profile --instance-profile-name opsfleet-dev-eks-karpenter-node
```

### kubectl connection issues

```bash
# Reconfigure
aws eks update-kubeconfig --region us-east-1 --name opsfleet-dev-eks

# Check cluster status
aws eks describe-cluster --name opsfleet-dev-eks --region us-east-1 --query 'cluster.status'
```

## 📊 Cost Estimation

**Development Environment** (light usage):
- EKS Control Plane: $73/month
- 2x t4g.medium (system): ~$30/month
- 3x NAT Gateways: ~$100/month
- Application nodes (Spot): ~$20-50/month
- **Total: ~$223-253/month**

**Production Environment** (moderate usage):
- EKS Control Plane: $73/month
- 3x t4g.large (system): ~$90/month
- 3x NAT Gateways: ~$100/month
- Application nodes (Spot): ~$200-500/month
- **Total: ~$463-763/month**

## 🔗 Useful Commands

```bash
# Get all resources
kubectl get all -A

# Get nodes with labels
kubectl get nodes --show-labels

# Get nodes by architecture
kubectl get nodes -L kubernetes.io/arch

# Get nodes by capacity type
kubectl get nodes -L karpenter.sh/capacity-type

# Get Karpenter events
kubectl get events -n kube-system --sort-by='.lastTimestamp' | grep -i karpenter

# Describe a NodePool
kubectl describe nodepool graviton-spot

# Get EC2 instances managed by Karpenter
aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/managed-by,Values=opsfleet-dev-eks" \
  --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,PrivateIpAddress]' \
  --output table

# Check Spot interruption queue (if configured)
aws sqs get-queue-attributes \
  --queue-url $(aws sqs get-queue-url --queue-name opsfleet-dev-eks --query 'QueueUrl' --output text) \
  --attribute-names All
```

## 📚 Next Steps

1. ✅ Review [README.md](README.md) for detailed documentation
2. ✅ Review [ARCHITECTURE.md](ARCHITECTURE.md) for architecture details
3. ✅ Customize `terraform.tfvars` for your needs
4. ✅ Deploy your applications
5. ✅ Set up monitoring (Prometheus, Grafana)
6. ✅ Configure CI/CD pipelines
7. ✅ Implement GitOps (ArgoCD/Flux)

