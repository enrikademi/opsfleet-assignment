# Architecture Design for "Innovate Inc."

> **Cloud Provider:** Amazon Web Services (AWS)
> **Managed Kubernetes:** Amazon EKS
> **Last Updated:** February 2026

---

## 📋 Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Cloud Environment Structure](#2-cloud-environment-structure)
3. [High-Level Architecture Diagram](#3-high-level-architecture-diagram)
4. [Network Design](#4-network-design)
5. [Compute Platform (EKS)](#5-compute-platform-eks)
6. [Database Strategy](#6-database-strategy)
7. [Security](#7-security)
8. [CI/CD Pipeline](#8-cicd-pipeline)
9. [Observability & Monitoring](#9-observability--monitoring)
10. [Cost Optimization](#10-cost-optimization)
11. [Scalability Strategy](#11-scalability-strategy)
12. [Disaster Recovery](#12-disaster-recovery)
13. [Technology Decisions Summary](#13-technology-decisions-summary)

---

## 1. Executive Summary

Innovate Inc. is building a web application (Python/Flask API + React SPA + PostgreSQL) that starts with low traffic but must scale to millions of users. This document outlines a **cloud-native, scalable, and secure** architecture on AWS leveraging managed services to minimize operational overhead for a small team.

### Key Design Principles:
- **Start small, scale fast** — cost-optimized for low traffic, ready for millions
- **Security first** — sensitive user data handled throughout
- **Developer velocity** — CI/CD from day one
- **Managed services** — minimize undifferentiated heavy lifting
- **Infrastructure as Code** — everything reproducible via Terraform

---

## 2. Cloud Environment Structure

### 2.1 Recommended: Multi-Account Strategy (AWS Organizations)

```
┌─────────────────────────────────────────────────────┐
│                   AWS Organizations                  │
│                 (Management Account)                 │
│                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │  Production  │  │   Staging   │  │    Dev      │ │
│  │   Account    │  │   Account   │  │   Account   │ │
│  │              │  │             │  │             │ │
│  │ Real users   │  │ Pre-prod    │  │ Engineers   │ │
│  │ Real data    │  │ Integration │  │ Experiments │ │
│  └─────────────┘  └─────────────┘  └─────────────┘ │
│                                                     │
│  ┌─────────────┐  ┌─────────────┐                  │
│  │  Security/  │  │   Shared    │                  │
│  │  Audit Acct │  │  Services   │                  │
│  │             │  │  (CI/CD,    │                  │
│  │ CloudTrail  │  │   ECR,      │                  │
│  │ GuardDuty   │  │   DNS)      │                  │
│  └─────────────┘  └─────────────┘                  │
└─────────────────────────────────────────────────────┘
```

### 2.2 Account Breakdown

| Account | Purpose | Justification |
|---------|---------|---------------|
| **Management** | AWS Organizations, consolidated billing, SCPs | Single pane of glass for governance |
| **Production** | Live environment, real user data | Strict isolation, limited access |
| **Staging** | Pre-production testing | Mirrors prod, safe testing ground |
| **Development** | Feature development, experiments | Engineers have more freedom |
| **Security/Audit** | CloudTrail logs, GuardDuty, centralized security | Immutable audit trail, no one can delete logs |
| **Shared Services** | CI/CD pipelines, ECR (container registry), Route 53 | Shared resources reduce duplication |

### 2.3 Why Multi-Account?

- **Blast radius isolation**: A security incident in Dev doesn't affect Production
- **Billing clarity**: Per-account cost tracking for each environment
- **IAM boundaries**: No cross-account access without explicit trust policies
- **Compliance**: Sensitive production data never touches development
- **Service quotas**: Each account has its own AWS service limits

### 2.4 Phase-Based Rollout

> **Start simple, evolve gradually:**
>
> **Phase 1 (MVP):** Production + Development accounts only
> **Phase 2 (Growth):** Add Staging + Shared Services
> **Phase 3 (Scale):** Full multi-account structure with Security/Audit

---

## 3. High-Level Architecture Diagram

### 3.1 Overall System Architecture

```
                         INTERNET
                            │
                            ▼
                   ┌────────────────┐
                   │   CloudFront   │  ← CDN + WAF
                   │   + WAF + ACM  │    (DDoS Protection)
                   └────────┬───────┘
                            │
               ┌────────────┴────────────┐
               │                         │
               ▼                         ▼
      ┌────────────────┐       ┌────────────────┐
      │   React SPA    │       │  Application   │
      │  (S3 + CF)     │       │  Load Balancer │
      │  Static Files  │       │  (HTTPS only)  │
      └────────────────┘       └───────┬────────┘
                                       │
                    ┌──────────────────┴──────────────────┐
                    │              VPC (10.0.0.0/16)       │
                    │                                      │
                    │  ┌────────────────────────────────┐  │
                    │  │    Private Subnet (Multi-AZ)   │  │
                    │  │                                │  │
                    │  │  ┌──────────────────────────┐  │  │
                    │  │  │      EKS CLUSTER         │  │  │
                    │  │  │                          │  │  │
                    │  │  │  ┌────────┐ ┌────────┐  │  │  │
                    │  │  │  │Flask   │ │Flask   │  │  │  │
                    │  │  │  │Pod     │ │Pod     │  │  │  │
                    │  │  │  │(x86)   │ │(ARM64) │  │  │  │
                    │  │  │  └────────┘ └────────┘  │  │  │
                    │  │  │                          │  │  │
                    │  │  │  ┌──────────────────┐    │  │  │
                    │  │  │  │    Karpenter      │    │  │  │
                    │  │  │  │  (Auto Scaling)   │    │  │  │
                    │  │  │  └──────────────────┘    │  │  │
                    │  │  └──────────────────────────┘  │  │
                    │  └────────────────────────────────┘  │
                    │                                      │
                    │  ┌────────────────────────────────┐  │
                    │  │    Data Subnet (Multi-AZ)      │  │
                    │  │                                │  │
                    │  │  ┌──────────────────────────┐  │  │
                    │  │  │   RDS PostgreSQL          │  │  │
                    │  │  │   (Multi-AZ, Encrypted)   │  │  │
                    │  │  └──────────────────────────┘  │  │
                    │  │                                │  │
                    │  │  ┌──────────────────────────┐  │  │
                    │  │  │   ElastiCache Redis       │  │  │
                    │  │  │   (Session/Cache)         │  │  │
                    │  │  └──────────────────────────┘  │  │
                    │  └────────────────────────────────┘  │
                    └──────────────────────────────────────┘
```

### 3.2 CI/CD Pipeline Flow

```
Developer ──push──► GitHub
                       │
                       ▼
              ┌─────────────────┐
              │   GitHub Actions │
              │                 │
              │  1. Run tests   │
              │  2. Build image │
              │  3. Push to ECR │
              │  4. Update Helm │
              └────────┬────────┘
                       │
          ┌────────────┴────────────┐
          │                         │
          ▼                         ▼
   ┌─────────────┐           ┌─────────────┐
   │   Staging   │           │ Production  │
   │   EKS       │  ──────►  │   EKS       │
   │  (auto)     │ (manual   │  (manual    │
   └─────────────┘  approve) └─────────────┘
```

### 3.3 Traffic Flow: User Request Journey

```
User Browser
    │
    │ HTTPS (443)
    ▼
CloudFront (CDN)
    │
    ├──[Static assets]──► S3 (React SPA HTML/JS/CSS)
    │
    └──[/api/* requests]──► Application Load Balancer
                                      │
                                      │ HTTP (80) internal
                                      ▼
                             EKS Ingress Controller
                             (AWS Load Balancer Controller)
                                      │
                                      ▼
                               Flask Service
                               (ClusterIP)
                                      │
                                      ▼
                               Flask Pods
                               (Auto-scaled by HPA + Karpenter)
                                      │
                                      ▼
                               RDS PostgreSQL
                               (Private subnet, encrypted)
```

---

## 4. Network Design

### 4.1 VPC Architecture

```
VPC: 10.0.0.0/16
│
├── Public Subnets (Internet-facing, Load Balancers only)
│   ├── us-east-1a: 10.0.0.0/24
│   ├── us-east-1b: 10.0.1.0/24
│   └── us-east-1c: 10.0.2.0/24
│
├── Private Subnets (Application layer - EKS nodes)
│   ├── us-east-1a: 10.0.10.0/23
│   ├── us-east-1b: 10.0.12.0/23
│   └── us-east-1c: 10.0.14.0/23
│
└── Data Subnets (Database layer - RDS, ElastiCache)
    ├── us-east-1a: 10.0.20.0/24
    ├── us-east-1b: 10.0.21.0/24
    └── us-east-1c: 10.0.22.0/24
```

**Key design decisions:**
- **3-tier subnet model** — public/private/data separation
- **3 Availability Zones** — high availability and fault tolerance
- **Private subnets for EKS nodes** — application servers never directly exposed
- **Data subnets isolated** — database only reachable from application layer
- **NAT Gateway per AZ** — no single point of failure for outbound traffic

### 4.2 Security Groups

```
┌──────────────────────────────────────────────────────────┐
│                    Security Group Design                  │
├────────────────────┬─────────────────────────────────────┤
│ ALB Security Group │ Inbound: 443 from 0.0.0.0/0         │
│                    │ Outbound: 8080 → EKS nodes SG        │
├────────────────────┼─────────────────────────────────────┤
│ EKS Nodes SG       │ Inbound: 8080 from ALB SG only       │
│                    │ Inbound: 443 from EKS Control Plane  │
│                    │ Outbound: 5432 → RDS SG               │
├────────────────────┼─────────────────────────────────────┤
│ RDS Security Group │ Inbound: 5432 from EKS Nodes SG only │
│                    │ No outbound internet                  │
├────────────────────┼─────────────────────────────────────┤
│ ElastiCache SG     │ Inbound: 6379 from EKS Nodes SG only │
│                    │ No outbound internet                  │
└────────────────────┴─────────────────────────────────────┘
```

### 4.3 Network Security Measures

| Layer | Control | Implementation |
|-------|---------|---------------|
| **Edge** | DDoS protection | AWS Shield Standard (free) + CloudFront |
| **Edge** | Web Application Firewall | AWS WAF rules (OWASP Top 10) |
| **DNS** | Private DNS | Route 53 Private Hosted Zones |
| **Transit** | Encryption in transit | TLS 1.2+ enforced everywhere |
| **VPC** | Network ACLs | Stateless packet filtering per subnet |
| **Instance** | Security Groups | Stateful, least-privilege rules |
| **Pod** | Network Policies | Kubernetes NetworkPolicy via Calico/Cilium |
| **API** | Endpoint security | EKS private endpoint (no public API) |

### 4.4 EKS Private Endpoint

```yaml
# EKS API server is private only — no public access
eks_endpoint_public_access  = false   # ← No public Kubernetes API
eks_endpoint_private_access = true    # ← Only accessible from within VPC
```

**Access to cluster:** Only via VPN, bastion host, or AWS Systems Manager Session Manager (SSM).

---

## 5. Compute Platform (EKS)

### 5.1 EKS Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    EKS CLUSTER                          │
│                                                         │
│  ┌─────────────────────┐  ┌─────────────────────────┐  │
│  │   System Node Group  │  │   Karpenter (Dynamic)   │  │
│  │  (Always-on)        │  │                         │  │
│  │                     │  │  ┌─────────┐ ┌───────┐  │  │
│  │  3x t3.medium       │  │  │Graviton │ │ x86   │  │  │
│  │  On-Demand          │  │  │ Spot    │ │ Spot  │  │  │
│  │  Multi-AZ           │  │  │ (ARM64) │ │(AMD64)│  │  │
│  │                     │  │  └─────────┘ └───────┘  │  │
│  │  Runs:              │  │                         │  │
│  │  - Karpenter        │  │  Scales 0 → ∞           │  │
│  │  - CoreDNS          │  │  based on demand        │  │
│  │  - AWS LB Ctrl      │  └─────────────────────────┘  │
│  └─────────────────────┘                               │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │             Application Workloads               │   │
│  │                                                 │   │
│  │  ┌─────────────────┐  ┌─────────────────────┐   │   │
│  │  │  Flask API       │  │   Background Jobs   │   │   │
│  │  │  Deployment      │  │   (Workers)         │   │   │
│  │  │  replicas: 3-50  │  │   replicas: 1-20    │   │   │
│  │  │  HPA enabled     │  │   KEDA/HPA          │   │   │
│  │  └─────────────────┘  └─────────────────────┘   │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### 5.2 Node Groups Strategy

#### System Node Group (Managed, Always-On)
```
Purpose:    Critical cluster infrastructure
Instances:  t3.medium (x86)
Count:      2-3 nodes (min for HA)
Type:       On-Demand (reliability)
Runs:       Karpenter, CoreDNS, Metrics Server, ALB Controller
```

#### Karpenter Node Pools (Dynamic Scaling)

| NodePool | Architecture | Capacity | Use Case |
|----------|-------------|----------|----------|
| `general-arm64` | ARM64 (Graviton) | Spot → On-Demand | Stateless Flask API pods |
| `general-x86` | AMD64 (x86) | Spot → On-Demand | Any x86-required workloads |
| `memory-optimized` | ARM64/x86 | Spot → On-Demand | Data processing, caching |

**Instance Type Examples:**
```
Graviton (ARM64): t4g, m7g, c7g, r7g families
x86 (AMD64):      t3, m7i, c7i, r7i families
```

### 5.3 Application Deployment

#### Flask API Deployment
```yaml
# Simplified representation of the Flask deployment
kind: Deployment
metadata:
  name: flask-api
spec:
  replicas: 3
  template:
    spec:
      # Allow Karpenter to choose best available node
      nodeSelector:
        kubernetes.io/arch: arm64   # Prefer Graviton (cheaper)
      tolerations:
        - key: karpenter.sh/capacity-type
          value: spot               # Accept Spot instances
      containers:
      - name: flask-api
        image: <account>.dkr.ecr.us-east-1.amazonaws.com/innovateinc/api:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "250m"
            memory: "256Mi"
          limits:
            cpu: "1000m"
            memory: "512Mi"
        # Health checks
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
        # Secrets via AWS Secrets Manager / K8s Secrets
        env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
```

#### Horizontal Pod Autoscaler (HPA)
```yaml
kind: HorizontalPodAutoscaler
metadata:
  name: flask-api-hpa
spec:
  scaleTargetRef:
    name: flask-api
  minReplicas: 3        # Always 3 for HA
  maxReplicas: 50       # Handles millions of users
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        averageUtilization: 70   # Scale at 70% CPU
  - type: Resource
    resource:
      name: memory
      target:
        averageUtilization: 80   # Scale at 80% memory
```

### 5.4 Containerization Strategy

#### Image Building
```
Code Push → GitHub Actions CI
                │
                ▼
         Build Docker Image
         (Multi-stage build)
                │
         ┌──────┴──────┐
         │             │
         ▼             ▼
      amd64          arm64
     (linux/amd64) (linux/arm64)
         │             │
         └──────┬──────┘
                ▼
         Multi-arch manifest
         Push to ECR:
         <acct>.dkr.ecr.us-east-1.amazonaws.com/
           innovateinc/api:latest
           innovateinc/api:v1.2.3
```

#### Dockerfile (Multi-stage, production-optimized)
```dockerfile
# Stage 1: Build
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# Stage 2: Runtime (minimal image)
FROM python:3.12-slim
WORKDIR /app
COPY --from=builder /root/.local /root/.local
COPY . .

# Run as non-root user (security)
RUN adduser --disabled-password --gecos '' appuser
USER appuser

EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "app:app"]
```

#### Image Security
- **ECR image scanning:** Automatic vulnerability scanning on push
- **Non-root containers:** All containers run as non-root
- **Read-only filesystems:** Where possible
- **Minimal base images:** `python:3.12-slim` not full `python:3.12`
- **Image signing:** Cosign for supply chain integrity

### 5.5 Kubernetes Add-ons

| Add-on | Purpose |
|--------|---------|
| **Karpenter** | Intelligent node auto-scaling |
| **AWS Load Balancer Controller** | Manage ALB/NLB from Kubernetes |
| **External DNS** | Auto-manage Route 53 records |
| **External Secrets Operator** | Sync AWS Secrets Manager → K8s Secrets |
| **Metrics Server** | Enable HPA |
| **AWS EBS CSI Driver** | Persistent volumes |
| **CoreDNS** | Cluster DNS |
| **Calico / Cilium** | Network policies |

---

## 6. Database Strategy

### 6.1 Recommended Service: Amazon RDS for PostgreSQL

**Choice: Amazon RDS PostgreSQL (not Aurora)**

> Initially RDS PostgreSQL. Migrate to **Aurora PostgreSQL Serverless v2** when traffic grows above 10,000+ concurrent users.

#### Phase 1: RDS PostgreSQL (Startup Phase)

```
┌─────────────────────────────────────────────────────┐
│              RDS PostgreSQL Multi-AZ                │
│                                                     │
│  ┌──────────────────┐      ┌──────────────────┐    │
│  │  Primary         │      │  Standby         │    │
│  │  (us-east-1a)    │ ════► │  (us-east-1b)    │    │
│  │  db.t3.medium    │      │  db.t3.medium    │    │
│  │  (Read + Write)  │      │  (Failover only) │    │
│  └──────────────────┘      └──────────────────┘    │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │  Read Replica (us-east-1c)                   │   │
│  │  db.t3.medium                                │   │
│  │  (Read-only traffic — analytics, reporting)  │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

**Justification for RDS over Aurora at startup:**
- Lower cost (no minimum capacity unit charges)
- Simpler operation
- Easier to reason about for a small team
- Easy migration path to Aurora when needed

#### Phase 2: Aurora PostgreSQL Serverless v2 (Growth Phase)

When the application reaches scale:
```
RDS PostgreSQL → Aurora PostgreSQL Serverless v2

Benefits:
- Scales compute automatically (0.5 → 128 ACUs)
- Global Database for multi-region
- Built-in HA (6 copies across 3 AZs)
- Up to 15 read replicas
- No maintenance windows impact
```

### 6.2 Database Configuration

```hcl
# Terraform representation
resource "aws_db_instance" "main" {
  engine         = "postgres"
  engine_version = "16.4"           # Latest PostgreSQL 16
  instance_class = "db.t3.medium"   # Start small

  allocated_storage     = 100       # 100 GB initial
  max_allocated_storage = 1000      # Auto-scale up to 1 TB

  multi_az               = true     # HA failover
  storage_encrypted      = true     # Encrypted at rest (KMS)
  deletion_protection    = true     # Prevent accidents

  backup_retention_period = 35      # 35 days backups
  backup_window           = "03:00-04:00"   # Off-peak hours

  # Performance Insights
  performance_insights_enabled = true
  monitoring_interval          = 60  # Enhanced monitoring

  # No public access
  publicly_accessible = false
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
}
```

### 6.3 High Availability

| Scenario | Solution | RTO | RPO |
|----------|----------|-----|-----|
| **AZ failure** | Multi-AZ automatic failover | < 2 min | ~0 |
| **Instance failure** | RDS Multi-AZ standby | < 2 min | ~0 |
| **Region failure** | Cross-region read replica → promote | ~30 min | < 5 min |
| **Data corruption** | Point-in-time recovery (PITR) | ~1 hour | < 5 min |
| **Accidental delete** | Automated snapshots (35 days) | ~1 hour | < 24 hr |

### 6.4 Backup Strategy

```
Backup Type           │ Frequency   │ Retention  │ Storage
──────────────────────┼─────────────┼────────────┼─────────────────
Automated RDS backups │ Daily       │ 35 days    │ S3 (same region)
Manual snapshots      │ Pre-deploy  │ 90 days    │ S3 (same region)
Cross-region copy     │ Daily       │ 30 days    │ S3 (DR region)
Point-in-time (PITR)  │ Continuous  │ 35 days    │ S3 (auto)
```

### 6.5 Connection Management

```
Flask App → Connection Pooling (PgBouncer) → RDS PostgreSQL

PgBouncer in EKS:
- Pool mode: transaction
- Max connections: 100 (per app pod)
- DB max connections: 500 (RDS limit)
- Prevents "too many connections" errors at scale
```

### 6.6 Session Caching (ElastiCache Redis)

```
Flask API → ElastiCache Redis (session/cache)

Configuration:
- Engine: Redis 7.x
- Node type: cache.t4g.micro → cache.r7g.large (as needed)
- Multi-AZ with automatic failover
- Encryption at rest and in transit
- Use cases:
  - Session tokens
  - API response caching
  - Rate limiting counters
  - Background job queues
```

---

## 7. Security

### 7.1 Security Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│                   SECURITY LAYERS                    │
├──────────────────────────────────────────────────────┤
│ L1: Edge       │ CloudFront WAF, AWS Shield          │
├──────────────────────────────────────────────────────┤
│ L2: Network    │ VPC, Security Groups, NACLs,        │
│                │ Private Subnets, Network Policies   │
├──────────────────────────────────────────────────────┤
│ L3: Identity   │ IAM least privilege, IRSA,          │
│                │ MFA enforcement, AWS SSO             │
├──────────────────────────────────────────────────────┤
│ L4: Data       │ Encryption at rest (KMS),           │
│                │ TLS in transit, Secrets Manager      │
├──────────────────────────────────────────────────────┤
│ L5: App        │ RBAC in Kubernetes, Pod Security    │
│                │ Standards, non-root containers       │
├──────────────────────────────────────────────────────┤
│ L6: Detection  │ GuardDuty, CloudTrail, Falco,       │
│                │ Security Hub, Config Rules           │
└──────────────────────────────────────────────────────┘
```

### 7.2 Key Security Controls

#### IAM & Access
- **Principle of least privilege** for all IAM roles
- **IRSA (IAM Roles for Service Accounts)** — no hardcoded credentials in pods
- **MFA required** for all human users
- **AWS SSO** for centralized access management
- **No long-lived access keys** — use IAM roles and instance profiles

#### Secrets Management
```
Kubernetes Secrets         ← External Secrets Operator ← AWS Secrets Manager
(used by pods)                  (syncs automatically)       (source of truth)

Database passwords, API keys, OAuth secrets → stored ONLY in Secrets Manager
```

#### Kubernetes RBAC
```yaml
# Example: Developer RBAC - cannot see production secrets
kind: Role
metadata:
  name: developer
  namespace: production
rules:
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]    # Read-only in prod
- apiGroups: [""]
  resources: ["pods", "logs"]
  verbs: ["get", "list", "watch"]
# Explicitly NO access to secrets
```

#### Data Protection
- **RDS:** Encrypted at rest using AWS KMS, customer-managed key
- **S3:** Server-side encryption (SSE-S3 or SSE-KMS)
- **EBS volumes:** Encrypted at rest
- **Secrets Manager:** Automatic rotation for DB credentials (90-day cycle)
- **TLS everywhere:** Certificate Manager for free TLS certs

#### GDPR / Data Compliance Considerations
- Data residency: Single region deployment (EU region if needed)
- Data retention policies via S3 lifecycle rules
- Audit logging via CloudTrail (immutable, stored in Security account)
- Right to be forgotten: Application-level data deletion capability

---

## 8. CI/CD Pipeline

### 8.1 Pipeline Design

```
Developer Laptop
      │
      │ git push feature/new-feature
      ▼
  GitHub Repository
      │
      ├── Pull Request Created
      │         │
      │         ▼
      │   GitHub Actions (PR checks)
      │   ├── Run unit tests (pytest)
      │   ├── Code linting (flake8, black)
      │   ├── Security scan (Bandit, Trivy)
      │   └── Docker build test
      │
      │ PR Approved + Merged to main
      │         │
      │         ▼
      │   GitHub Actions (CI Pipeline)
      │   ├── Run all tests
      │   ├── Build multi-arch Docker image
      │   │   (linux/amd64 + linux/arm64)
      │   ├── Push to ECR
      │   │   ├── :latest
      │   │   └── :<git-sha>
      │   └── Trigger deploy to Staging
      │
      │   Auto Deploy to Staging
      │   ├── kubectl set image (or ArgoCD sync)
      │   ├── Smoke tests
      │   └── Integration tests
      │
      │   Manual Approval Gate (Team Lead)
      │         │
      │         ▼
      │   Deploy to Production
      │   ├── Blue/Green or Rolling update
      │   ├── Canary: 10% traffic → 100%
      │   └── Automated rollback on errors
      ▼
  Production Kubernetes Cluster
```

### 8.2 GitOps with ArgoCD (Recommended)

```
┌──────────────────────────────────────────────────────┐
│                    GitOps Flow                       │
│                                                      │
│  App Repo          Config Repo (Helm Charts)         │
│  (code changes) ─► (image tag updates)               │
│                            │                         │
│                            ▼                         │
│                       ArgoCD                         │
│                    (watches config repo)              │
│                            │                         │
│                   Detects drift/changes              │
│                            │                         │
│               ┌────────────┴────────────┐            │
│               │                         │            │
│               ▼                         ▼            │
│          Staging EKS              Production EKS     │
│          (auto-sync)              (manual approval)  │
└──────────────────────────────────────────────────────┘
```

### 8.3 Deployment Strategy

| Phase | Strategy | Benefit |
|-------|----------|---------|
| **MVP** | Rolling update | Simple, zero-downtime |
| **Growth** | Canary (10% → 100%) | Gradual rollout, catch issues early |
| **Scale** | Blue/Green | Instant switch, instant rollback |

---

## 9. Observability & Monitoring

### 9.1 Three Pillars of Observability

```
┌─────────────────────────────────────────────────────┐
│               OBSERVABILITY STACK                   │
├────────────────┬────────────────┬───────────────────┤
│    METRICS     │     LOGS       │     TRACES        │
│                │                │                   │
│ CloudWatch     │ CloudWatch     │ AWS X-Ray         │
│ Container      │ Logs           │                   │
│ Insights       │                │ (distributed      │
│                │ Fluent Bit →   │  tracing for      │
│ Prometheus +   │ CloudWatch     │  Flask API)       │
│ Grafana        │ Log Groups     │                   │
│ (in-cluster)   │                │                   │
└────────────────┴────────────────┴───────────────────┘
```

### 9.2 Key Metrics to Monitor

**Application Level:**
- Request latency (p50, p95, p99)
- Error rate (4xx, 5xx)
- Requests per second (RPS)
- Active users

**Infrastructure Level:**
- CPU / Memory utilization per pod/node
- Node provisioning time (Karpenter)
- Database connections, query latency
- Cache hit rate (Redis)

**Business Level:**
- User signups, active sessions
- API endpoint usage
- Cost per request

### 9.3 Alerting (CloudWatch Alarms)

```
Critical Alerts (Page on-call):
├── API error rate > 5% for 5 minutes
├── RDS CPU > 85% for 10 minutes
├── Pod crash loop > 3 times
└── EKS node unreachable

Warning Alerts (Slack notification):
├── API error rate > 1% for 5 minutes
├── RDS CPU > 60% for 15 minutes
├── Memory utilization > 80%
└── Karpenter failed to provision node
```

---

## 10. Cost Optimization

### 10.1 Cost Strategy

```
Cost Savings Strategy:

1. Spot Instances (60-90% savings)
   └── All Karpenter-provisioned nodes use Spot first
       Fallback to On-Demand only if no Spot available

2. Graviton ARM64 (20% savings vs x86)
   └── Flask API is Python — runs perfectly on ARM64
       Prefer Graviton NodePool for all stateless workloads

3. Karpenter Consolidation
   └── Automatically removes unused nodes
       Bin-packs pods to minimize node count

4. RDS Right-sizing
   └── Start: db.t3.medium (~$50/month)
       Monitor: scale up only when CPU/memory demand requires

5. S3 for Static Frontend
   └── No EC2/EKS compute needed for React SPA
       Served via CloudFront (~$0.01/GB)
```

### 10.2 Estimated Monthly Cost (Low-Traffic Phase)

| Component | Service | Est. Cost/Month |
|-----------|---------|----------------|
| EKS Cluster Control Plane | EKS | $72 |
| System Nodes (2x t3.medium) | EC2 On-Demand | $60 |
| API Pods (Karpenter, Spot t4g.small) | EC2 Spot | ~$10-20 |
| RDS PostgreSQL (db.t3.medium, Multi-AZ) | RDS | ~$80 |
| ElastiCache Redis (cache.t4g.micro) | ElastiCache | ~$15 |
| ALB | ELB | ~$20 |
| CloudFront + S3 (SPA) | CloudFront + S3 | ~$5 |
| NAT Gateways (3x) | VPC | ~$100 |
| Data Transfer | Various | ~$10 |
| **Total (MVP)** | | **~$370/month** |

> **At scale (millions of users):** The architecture scales linearly — Karpenter adds nodes as needed, Spot pricing keeps costs manageable.

### 10.3 Cost Monitoring

- **AWS Cost Explorer** — daily cost trends, service breakdown
- **AWS Budgets** — alert when monthly spend > threshold
- **Kubecost** — per-namespace/per-team cost attribution in Kubernetes
- **Tagging strategy** — every resource tagged with `env`, `team`, `service`

---

## 11. Scalability Strategy

### 11.1 Scaling Layers

```
User Request Load Increases
        │
        ▼ Layer 1: CloudFront
   CDN absorbs static traffic (React SPA)
   Cache API responses where appropriate
        │
        ▼ Layer 2: Application Load Balancer
   Distributes traffic across healthy pods
        │
        ▼ Layer 3: HPA (Horizontal Pod Autoscaler)
   Adds more Flask API pods
   (scales in seconds)
        │
        ▼ Layer 4: Karpenter
   Provisions new EC2 nodes for the pods
   (scales in ~2 minutes)
        │
        ▼ Layer 5: RDS Read Replicas
   Add read replicas for read-heavy traffic
   (scales in ~10 minutes)
```

### 11.2 Scale-to-Zero for Non-Production

```
Development environment:
├── EKS nodes: Karpenter scales to 0 at night
├── RDS: Use db.t3.micro (single-AZ)
├── Redis: cache.t4g.micro
└── Schedule: Stop at 8pm, start at 8am
    (saves ~60% of dev environment costs)
```

### 11.3 Multi-Region (Future: Scale Phase)

```
Phase 3 (millions of users):

         Global Route 53 (Latency-based routing)
                    │
         ┌──────────┴──────────┐
         │                     │
    us-east-1              eu-west-1
   (primary)               (EMEA users)
         │                     │
       EKS                   EKS
       RDS Primary    ←──── RDS Read Replica
                            (can promote if needed)
```

---

## 12. Disaster Recovery

### 12.1 DR Strategy: Warm Standby

```
Recovery Targets:
├── RTO (Recovery Time Objective):  < 30 minutes
└── RPO (Recovery Point Objective): < 5 minutes
```

### 12.2 DR Runbook

```
Scenario: Primary Region (us-east-1) complete failure

Step 1: Alert fires (CloudWatch/PagerDuty)          ~0 min
Step 2: On-call confirms region failure             ~5 min
Step 3: Promote RDS read replica in DR region       ~10 min
Step 4: Update Route 53 to point to DR region       ~2 min
Step 5: EKS cluster in DR region auto-scaled        ~5 min
Step 6: Smoke tests confirm DR region working       ~5 min
Step 7: Communicate to users (status page)          ~2 min
                                                 ─────────
Total:                                          ~29 minutes
```

### 12.3 DR Architecture

```
PRIMARY REGION (us-east-1)
├── EKS cluster (active)
├── RDS PostgreSQL (primary)
├── ElastiCache Redis (active)
└── S3 buckets (active)
         │
         │  Replication
         ▼
DISASTER RECOVERY REGION (us-west-2)
├── EKS cluster (warm — scaled down, ready to scale up)
├── RDS Read Replica (can promote to primary)
├── ElastiCache Redis (warm)
└── S3 buckets (cross-region replication enabled)
```

### 12.4 Backup Validation

- **Monthly DR drill** — actually failover to DR region, verify it works
- **Automated backup validation** — weekly Lambda function restores RDS snapshot to test instance
- **Recovery runbook** — documented, practiced, version-controlled in GitHub

---

## 13. Technology Decisions Summary

| Area | Choice | Justification |
|------|--------|---------------|
| **Cloud Provider** | AWS | Mature EKS, strong managed services ecosystem |
| **Kubernetes** | Amazon EKS | Managed control plane, AWS integrations |
| **Autoscaling** | Karpenter | Faster, more flexible than Cluster Autoscaler |
| **Container Registry** | Amazon ECR | Native EKS integration, image scanning, private |
| **Database** | RDS PostgreSQL → Aurora | Start simple, scale when needed |
| **Cache** | ElastiCache Redis | Managed, HA, multi-AZ, session/cache |
| **CDN** | CloudFront | Global, WAF integration, free TLS |
| **SPA Hosting** | S3 + CloudFront | Zero server cost, global distribution |
| **Load Balancer** | ALB (EKS LB Controller) | Native K8s ingress, path-based routing |
| **Secrets** | AWS Secrets Manager | Centralized, rotation, audit trail |
| **DNS** | Route 53 | Private hosted zones, health checks |
| **Monitoring** | CloudWatch + Grafana | Native AWS + rich dashboards |
| **Tracing** | AWS X-Ray | Flask middleware available |
| **CI/CD** | GitHub Actions + ArgoCD | GitOps, declarative, audit trail |
| **IaC** | Terraform | Multi-provider, large ecosystem |

---

## 📚 References

- [AWS EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [Karpenter Documentation](https://karpenter.sh/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [GDPR AWS Compliance](https://aws.amazon.com/compliance/gdpr-center/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [12 Factor App Methodology](https://12factor.net/)

---

*Architecture designed for Innovate Inc. — February 2026*
*Reviewed against AWS Well-Architected Framework: Security, Reliability, Performance, Cost Optimization, Operational Excellence, Sustainability pillars.*
