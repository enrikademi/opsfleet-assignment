# Testing Checklist

Use this checklist to verify the infrastructure deployment before submitting.

## ✅ Pre-Deployment Checks

- [ ] AWS CLI configured and working
  ```bash
  aws sts get-caller-identity
  ```

- [ ] Terraform installed (>= 1.6.0)
  ```bash
  terraform version
  ```

- [ ] kubectl installed (>= 1.28)
  ```bash
  kubectl version --client
  ```

- [ ] Sufficient AWS permissions
  - EC2, VPC, EKS, IAM, CloudWatch

- [ ] AWS service limits checked
  - VPCs per region (default: 5)
  - EIPs per region (default: 5)
  - NAT Gateways per AZ (default: 5)

## ✅ Deployment Checks

### 1. Terraform Validation

- [ ] Initialize Terraform
  ```bash
  terraform init
  ```

- [ ] Validate configuration
  ```bash
  terraform validate
  ```

- [ ] Format check
  ```bash
  terraform fmt -check -recursive
  ```

- [ ] Plan review
  ```bash
  terraform plan
  ```
  - Expected: ~60-70 resources
  - No errors or warnings

### 2. Apply Infrastructure

- [ ] Deploy infrastructure
  ```bash
  terraform apply
  ```
  - Duration: 15-20 minutes
  - All resources created successfully

- [ ] Verify outputs
  ```bash
  terraform output
  ```
  - cluster_name
  - cluster_endpoint
  - configure_kubectl command

### 3. Cluster Access

- [ ] Configure kubectl
  ```bash
  aws eks update-kubeconfig --region us-east-1 --name $(terraform output -raw cluster_name)
  ```

- [ ] Verify cluster access
  ```bash
  kubectl cluster-info
  kubectl get nodes
  ```
  - Should see 2 system nodes (t4g.medium)

- [ ] Check all pods running
  ```bash
  kubectl get pods -A
  ```
  - All pods in Running state
  - No CrashLoopBackOff

### 4. Karpenter Verification

- [ ] Check Karpenter pods
  ```bash
  kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter
  ```
  - Should see 2 replicas running

- [ ] Check Karpenter logs (no errors)
  ```bash
  kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=50
  ```

- [ ] Verify NodePools
  ```bash
  kubectl get nodepools
  ```
  - Should see: graviton-spot, x86-spot

- [ ] Verify EC2NodeClasses
  ```bash
  kubectl get ec2nodeclasses
  ```
  - Should see: graviton, x86

- [ ] Describe NodePools
  ```bash
  kubectl describe nodepool graviton-spot
  kubectl describe nodepool x86-spot
  ```
  - Check configuration is correct

## ✅ Functional Testing

### Test 1: Graviton (ARM64) Deployment

- [ ] Deploy Graviton workload
  ```bash
  kubectl apply -f examples/graviton-deployment.yaml
  ```

- [ ] Wait for pods to be running
  ```bash
  kubectl get pods -l arch=arm64 -w
  ```

- [ ] Verify new ARM64 node provisioned
  ```bash
  kubectl get nodes -L kubernetes.io/arch,node.kubernetes.io/instance-type
  ```
  - Should see arm64 node (e.g., m7g.large, c7g.large)

- [ ] Check pod placement
  ```bash
  kubectl get pods -l arch=arm64 -o wide
  ```
  - Pods running on arm64 node

- [ ] Verify Karpenter logs
  ```bash
  kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=20 | grep -i "created"
  ```

### Test 2: x86 (AMD64) Deployment

- [ ] Deploy x86 workload
  ```bash
  kubectl apply -f examples/x86-deployment.yaml
  ```

- [ ] Wait for pods to be running
  ```bash
  kubectl get pods -l arch=amd64 -w
  ```

- [ ] Verify new x86 node provisioned
  ```bash
  kubectl get nodes -L kubernetes.io/arch,node.kubernetes.io/instance-type
  ```
  - Should see amd64 node (e.g., m7i.large, c7i.large)

- [ ] Check pod placement
  ```bash
  kubectl get pods -l arch=amd64 -o wide
  ```
  - Pods running on amd64 node

### Test 3: Mixed Deployment

- [ ] Deploy mixed workload
  ```bash
  kubectl apply -f examples/mixed-deployment.yaml
  ```

- [ ] Wait for pods to be running
  ```bash
  kubectl get pods -l arch=multi -w
  ```

- [ ] Verify pods on both architectures
  ```bash
  kubectl get pods -l arch=multi -o wide
  ```
  - Pods may be on arm64 or amd64 nodes

### Test 4: Scaling

- [ ] Scale up deployment
  ```bash
  kubectl scale deployment nginx-mixed --replicas=20
  ```

- [ ] Watch nodes being created
  ```bash
  kubectl get nodes -w
  ```
  - New nodes should appear within 60 seconds

- [ ] Check node count
  ```bash
  kubectl get nodes --no-headers | wc -l
  ```
  - Should increase

- [ ] Scale down deployment
  ```bash
  kubectl scale deployment nginx-mixed --replicas=2
  ```

- [ ] Wait for consolidation (2-3 minutes)
  ```bash
  watch kubectl get nodes
  ```
  - Nodes should be consolidated/removed

### Test 5: Spot Instance Verification

- [ ] Check capacity type labels
  ```bash
  kubectl get nodes -L karpenter.sh/capacity-type
  ```
  - Should see "spot" or "on-demand"

- [ ] Verify Spot usage in AWS Console
  - EC2 → Instances
  - Check "Lifecycle" column for "spot"

### Test 6: Service Connectivity

- [ ] Test service access (if applicable)
  ```bash
  kubectl get svc
  kubectl port-forward svc/nginx-mixed 8080:80
  curl localhost:8080
  ```

## ✅ Security Checks

- [ ] Verify nodes in private subnets
  ```bash
  aws ec2 describe-instances \
    --filters "Name=tag:karpenter.sh/managed-by,Values=$(terraform output -raw cluster_name)" \
    --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress,PrivateIpAddress]' \
    --output table
  ```
  - PublicIpAddress should be empty/null

- [ ] Verify IMDSv2 enforced
  ```bash
  aws ec2 describe-instances \
    --filters "Name=tag:karpenter.sh/managed-by,Values=$(terraform output -raw cluster_name)" \
    --query 'Reservations[*].Instances[*].[InstanceId,MetadataOptions.HttpTokens]' \
    --output table
  ```
  - Should show "required"

- [ ] Verify encrypted EBS volumes
  ```bash
  aws ec2 describe-volumes \
    --filters "Name=tag:karpenter.sh/managed-by,Values=$(terraform output -raw cluster_name)" \
    --query 'Volumes[*].[VolumeId,Encrypted]' \
    --output table
  ```
  - Encrypted should be "True"

- [ ] Check VPC Flow Logs enabled
  ```bash
  aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$(terraform output -raw vpc_id)"
  ```

- [ ] Verify EKS control plane logging
  ```bash
  aws eks describe-cluster --name $(terraform output -raw cluster_name) \
    --query 'cluster.logging.clusterLogging[0].enabled' \
    --output text
  ```
  - Should be "True"

## ✅ Cost Verification

- [ ] Check instance types used
  ```bash
  kubectl get nodes -L node.kubernetes.io/instance-type,karpenter.sh/capacity-type
  ```
  - Verify Graviton instances (t4g, m7g, c7g, r7g)
  - Verify Spot instances where possible

- [ ] Estimate monthly cost
  ```bash
  # Use AWS Cost Explorer or
  aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --group-by Type=SERVICE
  ```

## ✅ Monitoring Checks

- [ ] Check CloudWatch log groups
  ```bash
  aws logs describe-log-groups --log-group-name-prefix /aws/eks/$(terraform output -raw cluster_name)
  ```

- [ ] View recent EKS logs
  ```bash
  aws logs tail /aws/eks/$(terraform output -raw cluster_name)/cluster --follow
  ```

- [ ] Check Karpenter metrics (if Prometheus installed)
  ```bash
  kubectl port-forward -n kube-system svc/karpenter 8080:8080
  curl localhost:8080/metrics | grep karpenter_nodes
  ```

## ✅ Documentation Verification

- [ ] README.md is clear and complete
- [ ] QUICK_START.md provides fast reference
- [ ] ARCHITECTURE.md explains technical details
- [ ] PROJECT_SUMMARY.md summarizes the project
- [ ] Example manifests are well-commented
- [ ] All code is properly commented

## ✅ Cleanup Test

- [ ] Delete all workloads
  ```bash
  kubectl delete -f examples/
  ```

- [ ] Wait for Karpenter to clean up nodes
  ```bash
  watch kubectl get nodes
  ```
  - Only system nodes should remain

- [ ] Destroy infrastructure (optional - only if testing)
  ```bash
  terraform destroy
  ```
  - All resources should be deleted
  - No errors

## ✅ Final Checks

- [ ] No Terraform state files in Git
- [ ] No sensitive data in code
- [ ] .gitignore is comprehensive
- [ ] All documentation is up to date
- [ ] Code is formatted consistently
- [ ] No TODO comments in code
- [ ] All example manifests work

## 📊 Expected Results Summary

### Nodes
- **System nodes**: 2x t4g.medium (ARM64, On-Demand)
- **Karpenter nodes**: Dynamic based on workload
- **Architecture**: Both arm64 and amd64 supported
- **Capacity**: Spot preferred, On-Demand fallback

### Pods
- **Karpenter**: 2 replicas in kube-system
- **CoreDNS**: 2 replicas in kube-system
- **VPC CNI**: DaemonSet in kube-system
- **kube-proxy**: DaemonSet in kube-system

### Resources Created
- ~60-70 AWS resources
- 1 VPC with 9 subnets
- 3 NAT Gateways
- 1 Internet Gateway
- 1 EKS cluster
- Multiple IAM roles and policies
- 2 Karpenter NodePools
- 2 EC2NodeClasses

### Performance
- **Deployment time**: 15-20 minutes
- **Node provisioning**: 30-60 seconds
- **Scaling**: Near-instant (Karpenter)

### Cost (Dev Environment)
- **EKS Control Plane**: $73/month
- **System nodes**: ~$30/month
- **NAT Gateways**: ~$100/month
- **Application nodes**: Variable (Spot)
- **Total**: ~$223-253/month base

## 🎯 Success Criteria

✅ All infrastructure deployed successfully
✅ Cluster accessible via kubectl
✅ Karpenter running and functional
✅ Both ARM64 and x86 nodes can be provisioned
✅ Spot instances being used
✅ Pods can be scheduled on both architectures
✅ Scaling works (up and down)
✅ Consolidation works
✅ Security measures in place
✅ Documentation is comprehensive
✅ No errors in logs

## 📝 Notes

- Some tests may take 2-5 minutes (node provisioning, consolidation)
- Spot capacity may not always be available (will fallback to On-Demand)
- Cost estimates are approximate and vary by region/usage
- Always destroy test infrastructure to avoid unnecessary costs

---

**Last Updated**: January 2024

**Estimated Testing Time**: 30-45 minutes
