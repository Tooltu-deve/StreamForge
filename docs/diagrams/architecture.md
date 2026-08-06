# StreamForge — Architecture Diagrams

> Source of truth for the system design. Diagrams are written in Mermaid so they render on GitHub and stay diffable in Git. Grounded in the design doc §3.
>
> ⚠️ Route53 hosted zone lives in a **separate AWS account** (cross-account, currently deferred). GitOps manifests live in a **separate repo** `streamforge-gitops` (ADR-0002).

---

## 1. Data plane (user-facing flows)

```mermaid
flowchart LR
    User([User / Browser])
    R53["Route53<br/>(other account)"]
    WAF["AWS WAF<br/>web ACL"]

    subgraph edge["Edge / Delivery"]
        CF["CloudFront (CDN)<br/>single entry: web · /api/* · HLS"]
        ACM["ACM cert"]
    end

    Cognito["Cognito User Pool<br/>groups: free / premium"]

    subgraph s3["S3 (private)"]
        S3front["frontend<br/>React SPA"]
        S3raw["raw"]
        S3trans["transcoded<br/>HLS"]
    end

    subgraph eks["EKS — API services (behind ALB)"]
        ALB["ALB Ingress<br/>CloudFront-only<br/>(secret header + SG)"]
        Catalog["catalog-service"]
        Upload["upload-service"]
        Playback["playback-service"]
    end

    DDB[("DynamoDB<br/>metadata")]

    subgraph pipe["Async transcode pipeline"]
        EB["EventBridge"]
        SQS["SQS + DLQ"]
        Worker["transcode-worker<br/>FFmpeg · spot · KEDA"]
    end

    SM["Secrets Manager<br/>CloudFront private key"]

    User -->|DNS| R53
    User -->|HTTPS| WAF --> CF
    ACM -.-> CF
    CF -->|default| S3front
    CF -->|OAC| S3trans
    CF -->|/api/* origin| ALB
    User -->|login → JWT| Cognito
    ALB --> Catalog & Upload & Playback
    Catalog --> DDB
    Upload -->|presigned URL| S3raw
    Playback -->|verify tier| Cognito
    Playback -->|signed cookie| User
    Playback -.->|read key| SM

    S3raw -->|object created| EB --> SQS --> Worker
    Worker -->|HLS renditions| S3trans
    Worker -->|update status| DDB
```

**Legend:** solid = synchronous request; dotted = supporting/secret access; the pipeline (EventBridge→SQS→Worker) is **asynchronous**. All public inbound traffic enters through **AWS WAF → CloudFront**; the ALB accepts traffic **only from CloudFront** (origin secret header verified at the ALB + security-group scoping).

---

## 2. Platform plane (GitOps, CI/CD, DevSecOps, observability)

```mermaid
flowchart LR
    Dev([Developer])

    subgraph gh["GitHub"]
        AppRepo["App repo<br/>streamforge"]
        Actions["GitHub Actions<br/>OIDC — no long-lived keys"]
        ConfigRepo["Config repo<br/>streamforge-gitops"]
    end

    subgraph aws["AWS"]
        ECR["ECR"]
        SM["Secrets Manager / SSM"]
        Obs["Observability<br/>CloudWatch · X-Ray/ADOT · Grafana"]

        subgraph cluster["EKS cluster"]
            Argo["ArgoCD"]
            Rollouts["Argo Rollouts<br/>canary + auto-rollback"]
            Workloads["Workloads<br/>API services + worker"]
            Kyverno["Kyverno<br/>policy enforce"]
            ESO["External Secrets"]
            KEDA["KEDA"]
        end
    end

    Dev -->|push| AppRepo --> Actions
    Actions -->|build · Trivy scan · cosign sign| ECR
    Actions -->|bump image tag| ConfigRepo
    Argo -->|watch & sync| ConfigRepo
    Argo --> Rollouts --> Workloads
    ECR -->|pull image| Workloads
    Kyverno -.->|admit only signed images| Workloads
    ESO -->|inject secrets| Workloads
    ESO --> SM
    KEDA -.->|scale worker| Workloads
    Workloads -->|metrics · logs · traces| Obs
```

---

## 3. VPC / network layout

```mermaid
flowchart TB
    Internet(("Internet"))
    IGW["Internet Gateway"]

    subgraph vpc["VPC 10.0.0.0/16"]
        direction TB
        RNAT["Regional NAT Gateway<br/>1 ID · auto-expands across AZs · HA by default<br/>own AWS-managed route table → IGW · no public subnet needed"]
        subgraph azA["AZ ap-southeast-1a"]
            PubA["Public 10.0.0.0/24<br/>tag: role/elb · ALB"]
            PrivA["Private 10.0.10.0/24<br/>tag: role/internal-elb · nodes"]
        end
        subgraph azB["AZ ap-southeast-1b"]
            PubB["Public 10.0.1.0/24"]
            PrivB["Private 10.0.11.0/24<br/>nodes"]
        end
        VPCE["VPC Endpoints<br/>S3 gateway + ECR interface"]
    end

    Internet <--> IGW
    IGW <--> PubA & PubB
    PrivA -->|0.0.0.0/0| RNAT
    PrivB -->|0.0.0.0/0| RNAT
    RNAT --> IGW
    PrivA -.->|S3/ECR, no NAT| VPCE
    PrivB -.->|S3/ECR, no NAT| VPCE
```

**Notes:** EKS nodes (on-demand + spot) sit in **private** subnets; the internet-facing ALB in **public** subnets. Subnet tags are required for the AWS Load Balancer Controller and EKS auto-discovery. Egress uses a **Regional NAT Gateway** (GA Nov 2025): a single NAT ID that auto-expands/contracts across AZs by workload presence, giving **HA by default** with **zonal affinity** (no forced cross-AZ egress) and higher IP/port limits (32 IPs/AZ). It is a standalone resource with its own AWS-managed route table to the IGW, so **no public subnet is needed to host it**; private subnets in every AZ route `0.0.0.0/0` to the same regional NAT ID. Use **automatic mode** (AWS manages IPs + AZ expansion). VPC endpoints (S3/ECR) still bypass NAT to cut cost. *(Regional NAT does not support private NAT — not needed here.)*

---

## 4. Sequence — upload → transcode (async)

```mermaid
sequenceDiagram
    actor U as User
    participant UP as upload-service
    participant RAW as S3 raw
    participant EB as EventBridge
    participant Q as SQS
    participant W as transcode-worker (spot)
    participant TR as S3 transcoded
    participant DB as DynamoDB

    U->>UP: request upload
    UP-->>U: presigned URL
    U->>RAW: PUT video (direct)
    RAW->>EB: object-created event
    EB->>Q: enqueue job
    Note over W: KEDA scales worker by queue depth
    W->>Q: poll message
    W->>W: FFmpeg → HLS (240/480/720/1080p)
    W->>TR: write renditions
    W->>DB: status = ready
    W->>Q: delete message (idempotent)
```

---

## 5. Sequence — playback with tier check (signed cookie)

```mermaid
sequenceDiagram
    actor U as User
    participant PB as playback-service
    participant CG as Cognito (JWT)
    participant DB as DynamoDB
    participant CF as CloudFront
    participant TR as S3 transcoded

    U->>PB: request video (with JWT)
    PB->>CG: validate JWT → tier (free/premium)
    PB->>DB: read video.tier_required
    alt tier allowed
        PB-->>U: CloudFront signed cookie (short-lived)
        U->>CF: GET HLS segments (+ cookie)
        CF->>TR: fetch via OAC
        CF-->>U: stream
    else not allowed / cookie expired
        PB-->>U: 403 → frontend requests a new signature
    end
```
