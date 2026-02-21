# 🎬 Live Demo Script — EKS + Karpenter + Multi-Architecture

> **Cluster:** opsfleet-dev-eks | **Region:** us-east-1
> **Connect:** `aws eks update-kubeconfig --region us-east-1 --name opsfleet-dev-eks`

---

## ⚡ DEMO 1: Infrastructure Overview (2 min)

### Show the cluster is alive
```bash
kubectl cluster-info
kubectl get nodes -o wide
```

### Show BOTH architectures already running
```bash
kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type,node.kubernetes.io/instance-type
```
**Expected:**
```
NAME                          STATUS   ARCH    CAPACITY-TYPE   INSTANCE-TYPE
ip-10-0-58-135.ec2.internal   Ready    amd64                   t3.small
ip-10-0-75-65.ec2.internal    Ready    amd64                   t3.small
ip-10-0-85-213.ec2.internal   Ready    arm64   spot            t4g.small
```
**Say:** *"Two x86 system nodes always-on. One Graviton Spot node already provisioned by Karpenter — ARM64 kernel, 20% cheaper than x86."*

### Show Karpenter is running
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter
kubectl get nodepools
kubectl get ec2nodeclasses
```
**Say:** *"Two Karpenter pods running. Two NodePools configured — one for ARM64 Graviton, one for x86. Each tied to an EC2NodeClass that defines the AMI, security groups, and subnets."*

---

## 🏗️ DEMO 2: Multi-Architecture Proof (3 min)

### Deploy workloads to BOTH architectures simultaneously
```bash
kubectl apply -f examples/multiarch-proof.yaml
```

### Watch pods land on correct nodes (in separate terminal)
```bash
watch -n 2 'kubectl get pods -n multiarch -o wide'
```

### Wait until Running, then prove architecture from INSIDE the containers
```bash
# ARM64 — Graviton
kubectl exec -n multiarch deployment/app-graviton -- uname -m
# Expected: aarch64  ✅ This is ARM64 (Graviton)

# x86 — AMD64
kubectl exec -n multiarch deployment/app-x86 -- uname -m
# Expected: x86_64  ✅ This is x86
```

### The MOST impressive command — show both at once
```bash
echo "=== Architecture per pod ===" && \
kubectl get pods -n multiarch -o wide && echo "" && \
echo "--- ARM64 pods (Graviton) ---" && \
kubectl exec -n multiarch deployment/app-graviton -- uname -m && \
echo "--- x86 pods ---" && \
kubectl exec -n multiarch deployment/app-x86 -- uname -m
```

**Say:** *"The same container image, two different architectures. The developer just sets `nodeSelector: kubernetes.io/arch: arm64` — Karpenter handles everything else."*

---

## 📈 DEMO 3: Karpenter Auto-Scaling with HPA (5 min — most impressive!)

> **Open 4 terminals for this demo!**

### Terminal 1 — Watch pods scale
```bash
watch -n 2 'kubectl get pods -n karpenter-demo -o wide'
```

### Terminal 2 — Watch NEW NODES appear
```bash
watch -n 2 'kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type'
```

### Terminal 3 — Watch Karpenter logs (LIVE provisioning messages)
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f --tail=20
```

### Terminal 4 — Watch HPA
```bash
kubectl get hpa -n karpenter-demo -w
```

### NOW: Deploy the stress app and trigger scaling
```bash
# Deploy
kubectl apply -f examples/karpenter-stress-demo.yaml

# Wait for initial pods to be Running (~30 sec)
kubectl get pods -n karpenter-demo

# SCALE UP to force Karpenter to provision NEW nodes
kubectl scale deployment/stress-graviton -n karpenter-demo --replicas=10
kubectl scale deployment/stress-x86 -n karpenter-demo --replicas=10
```

### Watch Karpenter provision nodes in ~60 seconds
```bash
# Show node count increasing
kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type
```

**Karpenter log output you'll see (impressive to show):**
```
INFO  found provisionable pod(s)  {"pods": 8}
INFO  computed new nodeclaim  {"instance-type": "t4g.medium", "zone": "us-east-1a"}
INFO  created nodeclaim  {"NodeClaim": "graviton-spot-xxxxx"}
INFO  launched nodeclaim  {"provider-id": "aws:///us-east-1a/i-0xxxx", "instance-type": "t4g.medium"}
INFO  registered nodeclaim  {"Node": "ip-10-0-xx-xx.ec2.internal"}
INFO  initialized nodeclaim  {"allocatable": {"cpu":"1930m","memory":"3373Mi"}}
```
**Say:** *"Watch Karpenter detect unschedulable pods, call EC2 CreateFleet, provision a Graviton t4g.medium Spot instance, and register it — all within 60 seconds. No pre-defined node groups."*

### SCALE DOWN — Show consolidation
```bash
kubectl scale deployment/stress-graviton -n karpenter-demo --replicas=1
kubectl scale deployment/stress-x86 -n karpenter-demo --replicas=1
```

**Wait 30-60 seconds, then:**
```bash
kubectl get nodes
```
**Say:** *"Karpenter consolidates automatically. When nodes are underutilized, it moves pods to fewer nodes and terminates the empty ones. This is how we save costs — no idle capacity."*

---

## 💾 DEMO 4: StatefulSet + Persistent Storage (3 min)

> Shows understanding of StatefulSets vs Deployments — a senior-level concept

### Deploy StatefulSet with persistent volumes
```bash
kubectl apply -f examples/statefulset-demo.yaml

# Watch pods come up one-by-one (stateful ordering: 0 → 1 → 2)
kubectl get pods -n karpenter-demo -l app=stateful-app -w
```

### Show PVCs were automatically created (one per pod)
```bash
kubectl get pvc -n karpenter-demo
```
**Expected:**
```
NAME                    STATUS   VOLUME         CAPACITY   STORAGECLASS
data-stateful-app-0     Bound    pvc-xxx        1Gi        ebs-gp3
data-stateful-app-1     Bound    pvc-yyy        1Gi        ebs-gp3
data-stateful-app-2     Bound    pvc-zzz        1Gi        ebs-gp3
```
**Say:** *"Each pod gets its own dedicated EBS volume — that's the key difference from a Deployment. StatefulSet pods have stable identity: stateful-app-0, stateful-app-1, stateful-app-2."*

### Prove persistence survives pod restarts
```bash
# Write data to pod-0
kubectl exec -n karpenter-demo stateful-app-0 -- sh -c "echo 'Data written at: $(date)' > /data/proof.txt"
kubectl exec -n karpenter-demo stateful-app-0 -- cat /data/proof.txt

# Kill the pod
kubectl delete pod -n karpenter-demo stateful-app-0

# Watch it restart
kubectl get pods -n karpenter-demo -l app=stateful-app -w

# After restart — data is still there!
kubectl exec -n karpenter-demo stateful-app-0 -- cat /data/proof.txt
```
**Say:** *"The pod was killed and restarted, but the data persists on the EBS volume. This is how you'd run stateful workloads like databases or message queues on Kubernetes."*

---

## 🧹 DEMO 5: Cleanup (1 min)

```bash
kubectl delete -f examples/multiarch-proof.yaml
kubectl delete -f examples/karpenter-stress-demo.yaml
kubectl delete -f examples/statefulset-demo.yaml

# Watch Karpenter remove unused nodes
watch -n 5 'kubectl get nodes'
```
**Say:** *"Karpenter automatically terminates nodes that are no longer needed. Within a minute, we're back to just the system nodes — zero idle cost."*

---

## 🔑 KEY LOGS TO SHOW

### 1. Karpenter provisioned a node (proof of dynamic scaling)
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=50 | grep -E "provisioned|launched|registered|nodeclaim"
```

### 2. EBS CSI Driver working (for StatefulSet PVCs)
```bash
kubectl get pods -n kube-system -l app=ebs-csi-controller
kubectl get storageclass
```

### 3. Nodes across AZs (multi-AZ, HA)
```bash
kubectl get nodes -L topology.kubernetes.io/zone,kubernetes.io/arch
```

### 4. NodePool details (shows x86 and ARM64 config)
```bash
kubectl describe nodepool graviton-spot | grep -A 15 "Requirements"
kubectl describe nodepool x86-spot | grep -A 15 "Requirements"
```

### 5. Pod scheduling decision (why pod went to that node)
```bash
kubectl describe pod -n multiarch -l app=app-graviton | grep -A 10 "Events:"
```

---

## 🎤 TALKING POINTS PER DEMO

| Demo | What to Say |
|------|-------------|
| **Infrastructure** | *"EKS managed control plane — AWS handles etcd, API server, upgrades. We only manage nodes via Karpenter."* |
| **Multi-Arch** | *"Developer declares `nodeSelector: arm64` — infrastructure team handles the rest. Clean separation of concerns."* |
| **HPA + Karpenter** | *"HPA is horizontal pod scaling. Karpenter is horizontal node scaling. Together they handle everything from 10 to 10 million requests."* |
| **StatefulSet** | *"Deployment = stateless, pets vs cattle. StatefulSet = stateful, each pod has identity + its own storage. Used for databases, queues, caches."* |
| **Consolidation** | *"Karpenter's consolidation is the difference between paying for 10 nodes at 20% utilization vs 2 nodes at 90%. That's 5x cost reduction."* |

---

## 📊 COST IMPACT TO MENTION

```
System nodes (always on):    2x t3.small     = ~$30/month
Karpenter Graviton (Spot):   t4g.small Spot  = ~$4/month (vs $20 On-Demand)
Savings vs traditional:
  - Spot discount:            ~70% cheaper
  - Graviton discount:        ~20% cheaper
  - Auto-consolidation:       ~40% fewer nodes needed
  Total cost savings:         ~70-80% vs static On-Demand x86 nodes
```

---

## ✅ CHECKLIST: What You've Proved

- [x] EKS cluster with latest Kubernetes (v1.31)
- [x] Karpenter auto-provisioned Graviton Spot node
- [x] Workloads running on ARM64 — proven from inside container (`uname -m`)
- [x] Workloads running on x86 — proven from inside container (`uname -m`)
- [x] HPA scaled pods up → Karpenter provisioned new nodes
- [x] Karpenter consolidated and removed empty nodes
- [x] StatefulSet with per-pod PVC (EBS CSI Driver)
- [x] Data persisted across pod restart
- [x] Full infrastructure as Terraform code
- [x] Everything documented in README + ARCHITECTURE.md
