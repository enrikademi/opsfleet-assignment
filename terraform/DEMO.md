# 🎬 Live Demo Script - Multi-Architecture EKS with Karpenter

## Prerequisites
```bash
# Ensure kubectl is connected to your EKS cluster
aws eks update-kubeconfig --region us-east-1 --name opsfleet-dev-eks
```

---

## 📊 **DEMO 1: Show Infrastructure Overview**

### 1.1 Show EKS Cluster
```bash
kubectl cluster-info
kubectl get nodes
```

**Expected Output:**
- Shows EKS API endpoint
- Shows 2-3 nodes running

### 1.2 Show Karpenter is Running
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter
```

**Expected Output:**
- 2 Karpenter controller pods in `Running` state

### 1.3 Show NodePools (both architectures configured)
```bash
kubectl get nodepools
```

**Expected Output:**
```
NAME            AVAILABLE
graviton-spot   True
x86-spot        True
```

### 1.4 Show EC2NodeClasses
```bash
kubectl get ec2nodeclasses
```

**Expected Output:**
```
NAME       READY
graviton   True
x86        True
```

---

## 🔥 **DEMO 2: Show Both Architectures Working**

### 2.1 Show Current Nodes with Architecture
```bash
kubectl get nodes -o wide
```

**Look for:**
- **x86 nodes:** `x86_64` in KERNEL-VERSION column
- **Graviton nodes:** `aarch64` in KERNEL-VERSION column

### 2.2 Show Node Architecture Labels
```bash
kubectl get nodes -L kubernetes.io/arch
```

**Expected Output:**
```
NAME                           STATUS   ROLES    AGE   VERSION                ARCH
ip-10-0-58-135.ec2.internal    Ready    <none>   2h    v1.31.13-eks-ecaa3a6   amd64
ip-10-0-75-65.ec2.internal     Ready    <none>   2h    v1.31.13-eks-ecaa3a6   amd64
ip-10-0-85-213.ec2.internal    Ready    <none>   5m    v1.31.14-eks-70ce843   arm64
```

### 2.3 Show Detailed Node Info (for one Graviton node)
```bash
# Find a Graviton node
GRAVITON_NODE=$(kubectl get nodes -l kubernetes.io/arch=arm64 -o jsonpath='{.items[0].metadata.name}')
echo "Graviton Node: $GRAVITON_NODE"

# Show its details
kubectl describe node $GRAVITON_NODE | grep -E "Name:|kubernetes.io/arch|Instance Type|Kernel Version"
```

**Expected Output:**
- Architecture: arm64
- Kernel: aarch64
- Instance type (likely t4g.* or similar)

---

## 🚀 **DEMO 3: Deploy Workload to Graviton**

### 3.1 Show the Graviton Deployment Manifest
```bash
cat terraform/examples/graviton-deployment.yaml
```

**Highlight:**
```yaml
nodeSelector:
  kubernetes.io/arch: arm64  # <-- Forces ARM64/Graviton
  karpenter.sh/capacity-type: spot
  karpenter.sh/nodepool: graviton-spot
```

### 3.2 Deploy to Graviton
```bash
kubectl apply -f terraform/examples/graviton-deployment.yaml
```

### 3.3 Watch Karpenter Provision a New Node (if needed)
```bash
# Watch nodes (in one terminal)
watch -n 2 'kubectl get nodes -L kubernetes.io/arch'

# Watch pods (in another terminal)
watch -n 2 'kubectl get pods -o wide'
```

### 3.4 Verify Pods are on Graviton Nodes
```bash
kubectl get pods -o wide -l app=nginx-graviton
```

**Expected Output:**
```
NAME                              READY   STATUS    RESTARTS   AGE   IP            NODE                          
nginx-graviton-859d6d89fd-xxxxx   1/1     Running   0          2m    10.0.87.165   ip-10-0-85-213.ec2.internal
```

**Verify the node is ARM64:**
```bash
POD_NODE=$(kubectl get pod -l app=nginx-graviton -o jsonpath='{.items[0].spec.nodeName}')
kubectl get node $POD_NODE -L kubernetes.io/arch
```

**Expected:** Shows `arm64`

---

## 💻 **DEMO 4: Deploy Workload to x86**

### 4.1 Show the x86 Deployment Manifest
```bash
cat terraform/examples/x86-deployment.yaml
```

**Highlight:**
```yaml
nodeSelector:
  kubernetes.io/arch: amd64  # <-- Forces x86/AMD64
  karpenter.sh/capacity-type: spot
  karpenter.sh/nodepool: x86-spot
```

### 4.2 Deploy to x86
```bash
kubectl apply -f terraform/examples/x86-deployment.yaml
```

### 4.3 Verify Pods are on x86 Nodes
```bash
kubectl get pods -o wide -l app=nginx-x86
```

**Expected Output:**
```
NAME                         READY   STATUS    RESTARTS   AGE   IP            NODE                        
nginx-x86-669d8f47c4-xxxxx   1/1     Running   0          1m    10.0.72.165   ip-10-0-75-65.ec2.internal
```

**Verify the node is x86:**
```bash
POD_NODE=$(kubectl get pod -l app=nginx-x86 -o jsonpath='{.items[0].spec.nodeName}')
kubectl get node $POD_NODE -L kubernetes.io/arch
```

**Expected:** Shows `amd64`

---

## 📈 **DEMO 5: Show Auto-Scaling**

### 5.1 Scale Up Graviton Deployment
```bash
kubectl scale deployment nginx-graviton --replicas=10
```

### 5.2 Watch Karpenter Provision Additional Graviton Nodes
```bash
# Watch nodes being added
watch -n 2 'kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type'

# Watch Karpenter logs
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=20 -f
```

**Look for:** Messages about provisioning new nodes

### 5.3 Show All Pods Scheduled
```bash
kubectl get pods -l app=nginx-graviton -o wide
```

### 5.4 Scale Down (Show Consolidation)
```bash
kubectl scale deployment nginx-graviton --replicas=3
```

**Wait 30 seconds, then:**
```bash
kubectl get nodes
```

**Karpenter will eventually consolidate and remove unused nodes**

---

## 🎯 **DEMO 6: Show Cost Optimization**

### 6.1 Show Node Capacity Types (On-Demand vs Spot)
```bash
kubectl get nodes -L karpenter.sh/capacity-type,node.kubernetes.io/instance-type
```

**Expected Output:**
```
NAME                           CAPACITY-TYPE   INSTANCE-TYPE
ip-10-0-58-135.ec2.internal    on-demand       t3.small       (system node)
ip-10-0-75-65.ec2.internal     on-demand       t3.small       (system node)
ip-10-0-85-213.ec2.internal    spot            t4g.medium     (Karpenter Graviton)
```

### 6.2 Show NodePool Configuration
```bash
kubectl get nodepool graviton-spot -o yaml | grep -A 10 "requirements:"
```

**Highlight:**
- Spot instances (60-90% cheaper)
- Graviton instances (20% cheaper than x86 + better performance/watt)
- Multiple instance types for availability

---

## 🧹 **DEMO 7: Cleanup**

### 7.1 Delete Test Workloads
```bash
kubectl delete -f terraform/examples/graviton-deployment.yaml
kubectl delete -f terraform/examples/x86-deployment.yaml
```

### 7.2 Watch Karpenter Remove Unused Nodes
```bash
watch -n 5 'kubectl get nodes'
```

**Karpenter will automatically terminate Spot nodes after ~30 seconds of being empty**

---

## 💡 **KEY TALKING POINTS**

### Architecture Highlights:
1. **Multi-Architecture Support:**
   - x86 (AMD64) for compatibility
   - Graviton (ARM64) for cost savings (~20%) and performance

2. **Automatic Provisioning:**
   - Karpenter watches for pending pods
   - Automatically provisions right-sized nodes
   - Respects architecture requirements via `nodeSelector`

3. **Cost Optimization:**
   - Spot instances (60-90% cheaper than On-Demand)
   - Graviton instances (20% cheaper + better performance/watt)
   - Automatic consolidation (removes unused nodes)

4. **Production-Ready Features:**
   - IMDSv2 enforced (security)
   - Multi-AZ for high availability
   - Instance diversity for Spot resilience
   - Proper IRSA for least-privilege access

### Terraform Architecture:
1. **Modular Structure:**
   - Separate modules: VPC, IAM, EKS, Karpenter
   - Reusable and testable

2. **Security Best Practices:**
   - Private EKS API endpoint option
   - Security groups with least privilege
   - IRSA for pod-level permissions
   - IMDSv2 enforcement

3. **Documentation:**
   - Comprehensive README
   - Architecture diagrams
   - Example deployments
   - Quick start guide

---

## 🔍 **TROUBLESHOOTING COMMANDS**

### Check Karpenter Status
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=50
```

### Check NodePool Status
```bash
kubectl describe nodepool graviton-spot
kubectl describe nodepool x86-spot
```

### Check EC2NodeClass Status
```bash
kubectl describe ec2nodeclass graviton
kubectl describe ec2nodeclass x86
```

### Check Pod Scheduling Issues
```bash
kubectl describe pod <pod-name>
kubectl get events --sort-by='.lastTimestamp'
```

---

## 📸 **SCREENSHOT/RECORDING CHECKLIST**

✅ `kubectl get nodes -o wide` showing both architectures
✅ `kubectl get pods -o wide` showing pods on correct nodes
✅ `kubectl get nodepools` showing both configured
✅ Graviton deployment YAML with nodeSelector
✅ x86 deployment YAML with nodeSelector
✅ Karpenter logs showing node provisioning
✅ Cost comparison slide (Spot + Graviton savings)

---

## 🎤 **ELEVATOR PITCH (30 seconds)**

"I've built a production-ready EKS cluster with Karpenter that automatically provisions right-sized nodes based on workload requirements. It supports both x86 and Graviton architectures, using Spot instances for up to 90% cost savings. Developers simply add a nodeSelector to their deployments, and Karpenter handles the rest - provisioning nodes when needed and removing them when idle. The entire infrastructure is defined in modular Terraform with comprehensive documentation and example deployments."

---

## 🏆 **SUCCESS METRICS**

- ✅ Multi-architecture support (x86 + ARM64)
- ✅ Automatic scaling (0 to N nodes)
- ✅ Cost-optimized (Spot + Graviton)
- ✅ Production-ready (security, HA, monitoring)
- ✅ Well-documented (README, examples, architecture diagrams)
- ✅ Infrastructure as Code (Terraform, modular, reusable)
