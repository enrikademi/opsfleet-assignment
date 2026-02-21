# Architecture Documentation

## High-Level Architecture

This document provides detailed architecture information for the EKS + Karpenter + Graviton + Spot infrastructure.

## Network Architecture

### VPC Design

```
VPC: 10.0.0.0/16 (65,536 IPs)
├── Public Subnets (Internet-facing)
│   ├── us-east-1a: 10.0.0.0/20   (4,096 IPs)
│   ├── us-east-1b: 10.0.1.0/20   (4,096 IPs)
│   └── us-east-1c: 10.0.2.0/20   (4,096 IPs)
│
├── Private Subnets (EKS Nodes)
│   ├── us-east-1a: 10.0.16.0/20  (4,096 IPs)
│   ├── us-east-1b: 10.0.17.0/20  (4,096 IPs)
│   └── us-east-1c: 10.0.18.0/20  (4,096 IPs)
│
└── Data Subnets (Databases, isolated)
    ├── us-east-1a: 10.0.32.0/20  (4,096 IPs)
    ├── us-east-1b: 10.0.33.0/20  (4,096 IPs)
    └── us-east-1c: 10.0.34.0/20  (4,096 IPs)
```

### Subnet Strategy

**Public Subnets** (`10.0.0.0/20` - `10.0.2.0/20`):
- Internet Gateway attached
- Used for: Load Balancers, NAT Gateways, Bastion hosts (future)
- Tagged for ELB discovery: `kubernetes.io/role/elb=1`

**Private Subnets** (`10.0.16.0/20` - `10.0.18.0/20`):
- No direct internet access (via NAT Gateway)
- Used for: EKS nodes (both managed and Karpenter-provisioned)
- Tagged for Karpenter discovery: `karpenter.sh/discovery=<cluster-name>`
- Tagged for internal ELB: `kubernetes.io/role/internal-elb=1`

**Data Subnets** (`10.0.32.0/20` - `10.0.34.0/20`):
- Completely isolated (no NAT Gateway)
- Used for: RDS, ElastiCache, other data services (future)
- Access only via VPC endpoints or private connectivity

### Traffic Flow

```
┌──────────────┐
│   Internet   │
└──────┬───────┘
       │
       ▼
┌──────────────────┐
│ Internet Gateway │
└──────┬───────────┘
       │
       ▼
┌─────────────────────┐
│  Public Subnets     │
│  ┌───────────────┐  │
│  │ NAT Gateways  │  │
│  │ (3x, per AZ)  │  │
│  └───────┬───────┘  │
└──────────┼──────────┘
           │
           ▼
┌─────────────────────────────────┐
│     Private Subnets             │
│  ┌───────────────────────────┐  │
│  │    EKS Worker Nodes       │  │
│  │  ┌─────────────────────┐  │  │
│  │  │  System Node Group  │  │  │
│  │  │  (t4g.medium ARM64) │  │  │
│  │  └─────────────────────┘  │  │
│  │  ┌─────────────────────┐  │  │
│  │  │ Karpenter Nodes     │  │  │
│  │  │ (Dynamic, Multi-Arch)│ │  │
│  │  └─────────────────────┘  │  │
│  └───────────────────────────┘  │
└─────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────┐
│      Data Subnets               │
│  (RDS, ElastiCache - Future)    │
└─────────────────────────────────┘
```

## EKS Cluster Architecture

### Control Plane

- **Managed by AWS**: Multi-AZ, highly available
- **Version**: 1.31 (configurable)
- **Endpoint Access**: 
  - Public: Enabled (configurable CIDR)
  - Private: Enabled (for nodes)
- **Logging**: All types enabled (api, audit, authenticator, controllerManager, scheduler)

### Data Plane

#### System Node Group (Managed)
- **Purpose**: Run critical system components (CoreDNS, Karpenter, etc.)
- **Instance Type**: `t4g.medium` (Graviton, ARM64)
- **Capacity Type**: On-Demand (for reliability)
- **Scaling**: 1-3 nodes (desired: 2)
- **AMI**: AL2_ARM_64 (Amazon Linux 2 for ARM)

#### Karpenter-Provisioned Nodes (Dynamic)
- **Purpose**: Run application workloads
- **Provisioning**: On-demand based on pod requirements
- **Scaling**: 0-1000 CPUs per NodePool (configurable)

### Node Pools

#### 1. Graviton Spot NodePool (`graviton-spot`)

**Configuration**:
```yaml
Architecture: arm64
Capacity Type: spot (primary), on-demand (fallback)
Instance Families: t4g, m7g, m6g, c7g, c6g, r7g, r6g
Instance Categories: c (compute), m (general), r (memory), t (burstable)
Availability Zones: All 3 AZs
Consolidation: Enabled (after 1 minute of underutilization)
Weight: 10 (higher priority)
```

**Use Cases**:
- Cost-sensitive workloads
- Stateless applications
- Batch processing
- CI/CD workloads

**Cost Savings**:
- Graviton: 40% better price-performance vs x86
- Spot: Up to 90% savings vs On-Demand
- **Combined**: Up to 94% savings vs x86 On-Demand

#### 2. x86 Spot NodePool (`x86-spot`)

**Configuration**:
```yaml
Architecture: amd64
Capacity Type: spot (primary), on-demand (fallback)
Instance Families: t3, t3a, m7i, m6i, m5, c7i, c6i, c5, r7i, r6i, r5
Instance Categories: c, m, r, t
Availability Zones: All 3 AZs
Consolidation: Enabled
Weight: 5 (lower priority than Graviton)
```

**Use Cases**:
- Legacy workloads requiring x86
- Applications without ARM64 support
- Specific x86 dependencies

## Karpenter Architecture

### How Karpenter Works

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Scheduler                     │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
              ┌──────────────┐
              │ Pod (Pending)│
              └──────┬───────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              Karpenter Controller                           │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ 1. Detect pending pods                               │   │
│  │ 2. Analyze pod requirements (CPU, memory, arch, etc.)│   │
│  │ 3. Match against NodePools                           │   │
│  │ 4. Select optimal instance type                      │   │
│  │ 5. Check Spot availability                           │   │
│  │ 6. Provision EC2 instance                            │   │
│  └──────────────────────────────────────────────────────┘   │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                    AWS EC2 API                              │
│  • Launch instance with EC2NodeClass config                 │
│  • Apply security groups (Karpenter discovery tag)          │
│  • Use subnets (Karpenter discovery tag)                    │
│  • Attach IAM instance profile                              │
│  • Configure user data (bootstrap script)                   │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              New Node Joins Cluster                         │
│  • Node registers with EKS control plane                    │
│  • Karpenter labels applied                                 │
│  • Pod scheduled to new node                                │
│  • Pod starts running                                       │
└─────────────────────────────────────────────────────────────┘

Time: 30-60 seconds from pending pod to running
```

### Karpenter vs Cluster Autoscaler

| Feature | Karpenter | Cluster Autoscaler |
|---------|-----------|-------------------|
| **Provisioning Speed** | 30-60 seconds | 3-5 minutes |
| **Instance Selection** | Optimal per workload | Fixed node group types |
| **Spot Support** | Native, intelligent | Limited |
| **Consolidation** | Automatic | Manual/limited |
| **Multi-Architecture** | Native | Complex setup |
| **Cost Optimization** | Excellent | Good |

## IAM Architecture

### IRSA (IAM Roles for Service Accounts)

```
┌──────────────────────────────────────────────────────────┐
│                    EKS Cluster                           │
│  ┌────────────────────────────────────────────────────┐  │
│  │              OIDC Provider                         │  │
│  │  (Federated identity for Kubernetes)               │  │
│  └────────────────┬───────────────────────────────────┘  │
└───────────────────┼──────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────┐
│                  AWS IAM                                │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Karpenter Controller Role (IRSA)               │   │
│  │  • Trusted by: OIDC Provider                     │   │
│  │  • Condition: ServiceAccount = karpenter         │   │
│  │  • Permissions:                                  │   │
│  │    - ec2:RunInstances, CreateFleet               │   │
│  │    - ec2:TerminateInstances                      │   │
│  │    - ec2:DescribeInstances, DescribeSubnets      │   │
│  │    - iam:PassRole (for node role)                │   │
│  │    - pricing:GetProducts                         │   │
│  └──────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Node Role                                       │   │
│  │  • Trusted by: ec2.amazonaws.com                 │   │
│  │  • Attached to: Instance Profile                 │   │
│  │  • Permissions:                                  │   │
│  │    - AmazonEKSWorkerNodePolicy                   │   │
│  │    - AmazonEKS_CNI_Policy                        │   │
│  │    - AmazonEC2ContainerRegistryReadOnly          │   │
│  │    - AmazonSSMManagedInstanceCore                │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### Security Boundaries

1. **Cluster Role**: EKS control plane operations
2. **Node Role**: Node-level AWS API access (ECR, EC2, SSM)
3. **Karpenter Controller Role**: Node provisioning/deprovisioning
4. **Pod Roles** (future): Application-specific AWS access via IRSA

## Graviton Architecture

### Why Graviton?

**AWS Graviton3 Processors**:
- Custom ARM64 processors designed by AWS
- 25% better compute performance than Graviton2
- 60% better energy efficiency
- 40% better price-performance than x86

### Instance Families

| Family | Use Case | vCPU Range | Memory Range |
|--------|----------|------------|--------------|
| **t4g** | Burstable, dev/test | 2-8 | 0.5-32 GB |
| **m7g** | General purpose | 1-64 | 4-256 GB |
| **c7g** | Compute optimized | 1-64 | 2-128 GB |
| **r7g** | Memory optimized | 1-64 | 8-512 GB |

### Multi-Architecture Support

```
┌────────────────────────────────────────────────────────────┐
│              Container Image (Multi-Arch)                  │
│  ┌──────────────────────┐  ┌──────────────────────┐        │
│  │  Manifest: amd64     │  │  Manifest: arm64     │        │
│  │  (x86 binary)        │  │  (ARM binary)        │        │
│  └──────────────────────┘  └──────────────────────┘        │
└────────────────────────────────────────────────────────────┘
                    │                        │
                    ▼                        ▼
         ┌─────────────────┐      ┌─────────────────┐
         │  x86 Node       │      │ Graviton Node   │
         │  (m7i.large)    │      │ (m7g.large)     │
         └─────────────────┘      └─────────────────┘
```

**Docker automatically pulls the correct architecture image based on node architecture.**

## Cost Optimization Strategy

### 1. Instance Selection Hierarchy

Karpenter evaluates in this order:

```
1. Graviton Spot (graviton-spot NodePool, weight: 10)
   └─> Cheapest option (up to 94% savings)
   
2. x86 Spot (x86-spot NodePool, weight: 5)
   └─> Fallback if Graviton unavailable
   
3. Graviton On-Demand
   └─> If Spot capacity unavailable
   
4. x86 On-Demand
   └─> Last resort
```

### 2. Consolidation

Karpenter continuously evaluates:
- Can pods be packed more efficiently?
- Are nodes underutilized?
- Can we replace multiple small nodes with one larger node?

**Consolidation triggers**:
- Node empty for 1 minute
- Node underutilized (can be consolidated)

### 3. Spot Interruption Handling

```
┌────────────────────────────────────────────────────────┐
│  AWS EC2 Spot Interruption (2-minute notice)          │
└────────────────────┬───────────────────────────────────┘
                     │
                     ▼
┌────────────────────────────────────────────────────────┐
│  Karpenter Detects Interruption                       │
└────────────────────┬───────────────────────────────────┘
                     │
                     ▼
┌────────────────────────────────────────────────────────┐
│  1. Cordon node (no new pods)                         │
│  2. Provision replacement capacity                    │
│  3. Drain pods gracefully                             │
│  4. Wait for new nodes to be ready                    │
│  5. Pods rescheduled to new nodes                     │
└────────────────────────────────────────────────────────┘
```

## Scalability

### Horizontal Scaling

- **Cluster**: Supports up to 1000 nodes per cluster (AWS limit)
- **NodePools**: Configurable CPU/memory limits (default: 1000 CPUs)
- **Pods per Node**: 
  - t4g.medium: 17 pods
  - m7g.large: 29 pods
  - m7g.xlarge: 58 pods

### Vertical Scaling

Karpenter automatically selects appropriate instance sizes based on:
- Pod resource requests
- Available instance types
- Cost optimization
- Spot availability

## Monitoring and Observability

### Metrics

**Karpenter Metrics** (Prometheus format):
- `karpenter_nodes_created`
- `karpenter_nodes_terminated`
- `karpenter_pods_state{state="pending"}`
- `karpenter_nodeclaims_created`
- `karpenter_interruption_actions_performed`

**EKS Metrics**:
- Control plane logs → CloudWatch
- Node metrics → CloudWatch Container Insights (optional)
- VPC Flow Logs → CloudWatch

### Logging

1. **EKS Control Plane Logs**:
   - API server
   - Audit logs
   - Authenticator
   - Controller manager
   - Scheduler

2. **Karpenter Logs**:
   ```bash
   kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter
   ```

3. **VPC Flow Logs**:
   - All network traffic
   - 7-day retention
   - Useful for security analysis

## Disaster Recovery

### High Availability

- **Control Plane**: Multi-AZ by AWS
- **Nodes**: Spread across 3 AZs
- **Karpenter**: 2 replicas with anti-affinity
- **NAT Gateways**: 1 per AZ (no single point of failure)

### Backup Strategy

**Infrastructure as Code**:
- All infrastructure defined in Terraform
- Can recreate entire cluster in 15-20 minutes
- Version controlled

**Application Data** (future):
- RDS automated backups
- EBS snapshots for persistent volumes
- S3 versioning for static assets

### RTO/RPO

- **RTO** (Recovery Time Objective): < 30 minutes
- **RPO** (Recovery Point Objective): < 5 minutes (for data services)

## Security Architecture

### Defense in Depth

```
Layer 1: Network
├── VPC isolation
├── Private subnets for nodes
├── Security groups (least privilege)
└── VPC Flow Logs

Layer 2: Compute
├── IMDSv2 enforced
├── Encrypted EBS volumes
├── No SSH keys
└── SSM Session Manager for access

Layer 3: Identity
├── IRSA for pod-level permissions
├── IAM roles with least privilege
├── OIDC provider for federation
└── No long-lived credentials

Layer 4: Application
├── Pod Security Standards (future)
├── Network Policies (future)
├── Secrets encryption (future)
└── Image scanning (future)

Layer 5: Audit
├── CloudTrail (all API calls)
├── EKS audit logs
├── VPC Flow Logs
└── GuardDuty (future)
```

## Future Enhancements

### Phase 2
- [ ] Application Load Balancer with WAF
- [ ] RDS PostgreSQL (Multi-AZ)
- [ ] ElastiCache Redis
- [ ] VPC Endpoints (ECR, S3, etc.)

### Phase 3
- [ ] Pod Security Standards enforcement
- [ ] Network Policies
- [ ] Secrets encryption with KMS
- [ ] Container image scanning (ECR)

### Phase 4
- [ ] Service Mesh (Istio/Linkerd)
- [ ] GitOps (ArgoCD/Flux)
- [ ] Observability stack (Prometheus, Grafana, Loki)
- [ ] Cost monitoring (Kubecost)

---

**Last Updated**: 2024-01-15
