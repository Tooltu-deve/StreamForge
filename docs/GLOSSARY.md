# StreamForge — Glossary & Core Concepts

> **Who is this file for?** For you — someone about to build the StreamForge project but not yet familiar with much of the technical jargon. Read this file **before** diving into each phase so you understand the "why" and the "what" first, and only then move on to the "how".
>
> **How to read it:** Part 1 covers the foundational concepts that appear throughout — read it carefully once. From Part 2 onward, the content is split to match the 8 phases (Phase 0–7) in the design doc; for each phase, only learn the terms that phase needs. Don't try to cram it all at once.
>
> 🎯 = HARD / IMPORTANT knowledge, the easiest to get stuck on — prioritize understanding it deeply.

---

## Table of Contents

- [Part 1 — Foundations (read first, used throughout)](#part-1--foundations)
- [Part 2 — Phase 0: The foundation (repo, state, DNS, certificates)](#part-2--phase-0)
- [Part 3 — Phase 1: Core infrastructure (VPC, EKS, S3, DynamoDB, Cognito, ECR)](#part-3--phase-1)
- [Part 4 — Phase 2: Packaging & running the app (Docker, Helm, Ingress, DNS, TLS)](#part-4--phase-2)
- [Part 5 — Phase 3: Transcode pipeline (SQS, FFmpeg, HLS, KEDA, spot)](#part-5--phase-3)
- [Part 6 — Phase 4: GitOps & Progressive Delivery (ArgoCD, canary)](#part-6--phase-4)
- [Part 7 — Phase 5: Membership (Cognito group, signed cookie, payOS)](#part-7--phase-5)
- [Part 8 — Phase 6: DevSecOps (Trivy, cosign, Kyverno, IRSA, External Secrets)](#part-8--phase-6)
- [Part 9 — Phase 7: Observability (CloudWatch, X-Ray, Grafana, SLO, k6)](#part-9--phase-7)
- [Part 10 — Quick-reference table of all abbreviations](#part-10--quick-reference-table)

---

## Part 1 — Foundations

> These are the concepts that show up in every phase. Get this part solid and 70% of what follows will click into place on its own.

### Cloud / AWS — "rent infrastructure instead of buying machines"
Instead of buying a server and putting it at home, you **rent** resources (servers, storage, networking) from Amazon over the internet and pay for what you use. AWS is the largest cloud provider.
- **Region** — a cluster of data centers in a geographic area (e.g. `ap-southeast-1` = Singapore). The project picks Singapore because it's close to Vietnam → low latency.
- **Managed service** — AWS handles the heavy operational lifting (patching, backups, scaling) for you. E.g. DynamoDB, Cognito, SQS. 🎯 The project deliberately uses **lots of managed services** so you can focus on showcasing the *platform* rather than getting bogged down building your own database/queue.

### IaC — Infrastructure as Code
🎯 **The central concept of the whole project.** Instead of clicking around the AWS web console to create resources (easy to forget, not repeatable), you **write files describing the infrastructure** and then run a command to have AWS create exactly that. Benefits:
- **Reproducible** — rebuild it 100% identically, any time.
- **Versioned** — stored in Git, so you can see who changed what and roll back.
- **Ephemeral** — spin it up when learning/demoing (`apply`), tear it all down when done (`destroy`) → **cost near $0**. This is why the project costs almost nothing.

**Terraform** — the IaC tool the project uses. You write `.tf` files, then run:
- `terraform plan` — preview what AWS *will* create/change/delete (nothing done for real yet).
- `terraform apply` — execute the changes.
- `terraform destroy` — tear everything down.
- **Modularization** — package a group of resources (e.g. a "VPC module") for reuse, much like writing a function in programming.

### Container & Docker — "package the app together with its environment"
🎯 **The classic problem:** "It works on my machine but breaks on yours." **Containers** solve this by packaging the app + all its libraries + its configuration into a single "box" that runs identically everywhere.
- **Docker** — the tool for building and running containers.
- **Image** — a "frozen" snapshot of a container (like an installer file). A **container** = a running image.
- **Dockerfile** — the recipe for building an image.
- **Registry** — a store for images. On AWS you use **ECR** (Elastic Container Registry).

### Kubernetes (K8s) & EKS — "an operating system for containers at large scale"
🎯 **The hardest concept for newcomers, but the heart of the project.**

When you have dozens of containers running many replicas, who will: restart the ones that die? balance the load? upgrade with no downtime? → **Kubernetes** does that automatically. You declare "I want 3 replicas of catalog-service always running," and K8s handles the rest.

**EKS (Elastic Kubernetes Service)** = Kubernetes managed by AWS (you don't have to stand up the "brain" yourself).

The K8s "nouns" you need to memorize:
| Term | What it is (everyday explanation) |
|---|---|
| **Cluster** | The entire "farm" of servers running K8s. |
| **Node** | A single server (EC2) in the cluster — where containers actually run. |
| **Node group** | A group of nodes of the same type. The project has 2: *on-demand* (stable, for the API) and *spot* (cheap, for transcoding). |
| **Pod** | The smallest unit K8s runs — usually wrapping 1 container. Your app = a set of pods. |
| **Deployment** | Declares "run N replicas of this pod, and replace them automatically when they fail." |
| **Service (K8s)** | A "stable address" for reaching a group of pods (since pods are constantly created/destroyed and their IPs change). ⚠️ Not the same as an "AWS service". |
| **Manifest** | A YAML file describing the objects above (Deployment, Service, …). |
| **Namespace** | A "drawer" that subdivides the cluster to group resources together. |
| **kubectl** | The command-line tool for issuing commands to the cluster. |
| **Helm** | A "package manager" for K8s — bundles many manifests into a single parameterized *chart* that you install with one command. |

### Microservices — "split a big app into many small services"
Instead of one giant monolith, the app is split into many small, independent services, each handling one job. The project has: `catalog`, `upload`, `playback`, `membership`, `transcode-worker`. Benefits: you can deploy/scale/fix each one independently. (In this project the app is intentionally simple — "the platform is the star".)

### CI/CD — automated build & deploy
- **CI (Continuous Integration)** — every time you push code, it's automatically built + tested + security-scanned.
- **CD (Continuous Delivery/Deployment)** — automatically ships the vetted code to the running environment.
- **GitHub Actions** — the CI/CD tool the project uses (runs a "workflow" on every push).
- 🎯 **OIDC (OpenID Connect)** — a way for GitHub Actions to request access into AWS **without storing long-lived secret keys**. Instead, AWS *temporarily trusts* GitHub via a short-lived token. This is an important security best practice (it avoids leaking access keys).

### GitOps — "Git is the single source of truth"
🎯 The system's desired state is described entirely in Git. A tool (**ArgoCD**) continuously compares "what Git says" against "what the cluster is running" and **automatically reconciles** them. You no longer `kubectl apply` by hand — you **push to Git** and the system deploys itself. Every change is traceable, and rolling back = reverting a commit.

### YAML & JWT (2 formats you'll see everywhere)
- **YAML** — an easy-to-read config file format (K8s, Helm, and GitHub Actions all use it). Sensitive to indentation (spaces).
- **JWT (JSON Web Token)** — a digitally signed "ticket" that proves "who I am / what I'm allowed to do". After logging in via Cognito, the client carries this JWT when calling the API.

---

## Part 2 — Phase 0
### The foundation: repo structure, Terraform state, DNS, certificates

> Goal for this phase: the domain works and Terraform's "state" is stored safely. There's no app yet — this is the foundation.

### 🎯 Terraform State & Remote Backend — the infrastructure's "ledger"
Terraform remembers "what I've created" in a **state** file. If this file gets corrupted/lost, or 2 people edit it at the same time → the infrastructure goes haywire.
- **Remote backend** — store the state in a safe, central location instead of on a personal machine. The project uses **S3** (to store the state file) + a **DynamoDB lock** (a lock so only 1 person can run `apply` at a time, avoiding conflicts). This is why Phase 0 must create this S3+DynamoDB pair **first of all**.

### DNS & Route 53 — "the internet's phone book"
- **DNS** — the system that translates domain names (`app.streamforge.com`) into server IP addresses.
- **Route 53** — AWS's DNS service.
- **Hosted Zone** — a "record" holding all the DNS entries for a domain.
- 🎯 **NS record & delegate** — you buy a domain from another provider, then edit the **NS record** there to point at Route 53 → from then on AWS has full authority over the domain's DNS. This step is what enables automating certificates and DNS later on.
- **A record / CNAME** — records that point a domain name to an IP (A) or to another name (CNAME).

### ACM & TLS — "the HTTPS padlock"
- **TLS/SSL** — encrypts the connection, turning `http` into `https` (with the padlock).
- **Certificate** — a "proof of identity" showing the website is genuine, so the browser trusts it.
- **ACM (AWS Certificate Manager)** — issues & auto-renews certificates **for free**.
- 🎯 **DNS-validation** — ACM verifies you own the domain by asking you to create a special DNS record (automatic here, since Route 53 already manages the DNS).
- ⚠️ **Important note:** CloudFront *requires* its certificate to live in the **us-east-1** region, whereas the ALB uses a certificate in your own region (`ap-southeast-1`). That's why the project creates **2 certificates**.

---

## Part 3 — Phase 1
### Core infrastructure with Terraform: VPC, EKS, node groups, S3, DynamoDB, Cognito, ECR

> Goal: one `terraform apply` command stands up the entire platform from scratch.

### 🎯 VPC & networking — "your own fenced-off plot of land" on AWS
**VPC (Virtual Private Cloud)** = a virtual private network that isolates your resources. This is the most confusing part of the networking:
| Term | Explanation |
|---|---|
| **Subnet** | Divides the VPC into smaller zones. **Public subnet** (direct internet access) and **Private subnet** (hidden, safer). |
| **Availability Zone (AZ)** | A physically separate data center within a region. Spread resources across ≥2 AZs for fault tolerance. |
| **Internet Gateway** | The doorway for a public subnet to get in/out of the internet. |
| **NAT Gateway** | Lets a private subnet *reach out* to the internet (e.g. to download updates) while the internet *can't reach in*. ⚠️ Charged by the hour — remember to `destroy`. |
| **Security Group** | A resource-level "firewall": only allows specified ports/sources to connect. |
| **Route table** | A routing table: where packets should go. |

### Node group: on-demand vs spot
- **On-demand** — machines rented at the standard price, stable, never reclaimed. Used for the API services (which need to stay alive at all times).
- 🎯 **Spot** — AWS's "leftover" machines sold **70–90% cheaper**, but AWS can **reclaim them at any time** (with ~2 minutes' notice). Used for the transcode-worker because transcoding work can tolerate interruption (see Phase 3). This is a chance to showcase SRE skills: cost savings + handling interruptions safely.

### S3 — object storage
**S3 (Simple Storage Service)** — stores files (videos, images, HLS segments, even Terraform state). The project has several **buckets** (containers): *raw* (original uploaded videos), *transcoded* (processed videos), *frontend* (static web). 🎯 All buckets are **private** — no one accesses them directly, only through CloudFront (see Phase 2/5).

### DynamoDB — a managed NoSQL database
A **NoSQL key-value/document** database (not a traditional SQL table), fully managed by AWS, auto-scaling, and cheap. It stores **metadata**: the list of videos, transcode status, each video's `tier_required`, and watch status.

### Cognito — a managed sign-in service
**Amazon Cognito** handles all of sign-up/sign-in/JWT issuance for you.
- **User Pool** — the "user store".
- 🎯 **Cognito Group** — a group of users. The project uses groups to store the *tier*: `free` / `premium`. Upgrading a plan = moving the user into the `premium` group (see Phase 5).

### ECR — the Docker image store
**Elastic Container Registry** — where CI pushes images and EKS pulls them to run.

---

## Part 4 — Phase 2
### Packaging & running the app: Docker, Helm, Ingress, ALB, external-dns, cert-manager

> Goal: reach `app.<domain>` over HTTPS, upload and watch a video (not transcoded yet).

### Helm (recap — used heavily from here on)
"npm/apt for Kubernetes". Packages a service's manifests into a parameterized **chart** (e.g. number of replicas, image name) → install/upgrade with one command, reusable for every service.

### 🎯 Ingress & ALB — the "front door" bringing traffic from the internet into the cluster
- **Ingress** — a K8s object declaring HTTP routing rules: "`/catalog` goes to catalog-service, `/upload` goes to upload-service".
- **ALB (Application Load Balancer)** — AWS's load balancer, sitting in front of the cluster, receiving requests from the internet and distributing them to pods.
- **AWS Load Balancer Controller** — a component in the cluster that *automatically* creates an ALB from your Ingress declaration. (You write the Ingress → the controller stands up a real ALB on AWS.)

### external-dns — automatically create DNS records
A component that reads Ingress/Service objects in the cluster and **automatically creates DNS records** in Route 53 pointing to the ALB. No more clicking around in AWS every time a domain changes.

### cert-manager — automatically issue/renew TLS certificates *inside* the cluster
Automatically requests certificates and attaches them to Ingress for HTTPS, renewing them as they near expiry. (ACM handles the ALB/CloudFront at the AWS layer; cert-manager handles it inside the cluster — the two complement each other depending on the architecture.)

### Presigned URL — a "temporary ticket" to upload straight to S3
🎯 The `upload-service` doesn't receive the file through itself (that wastes bandwidth/memory). Instead it issues a **presigned URL** — a pre-signed, time-limited link — so the client can **upload directly to the S3 raw bucket**. Safe (expires quickly) and lightweight for the server.

### Probe — checking a pod's health
- **Liveness probe** — "is the pod still alive?" If not → K8s restarts it.
- **Readiness probe** — "is the pod ready to receive traffic yet?" If not → don't send requests to it for now.

---

## Part 5 — Phase 3
### Transcode pipeline (async): S3 event → SQS → FFmpeg worker (spot) → HLS → DynamoDB; KEDA

> Goal: once a video is uploaded, it's automatically transcoded and watchable as ABR streaming. This is the **central SRE story** of the portfolio.

### Transcode & FFmpeg — "change a video's format/quality"
- **Transcode** — convert the source video into multiple resolution/bitrate versions (240p…1080p) and a format suited to streaming.
- **FFmpeg** — the open-source video-processing tool that runs inside the worker container.

### 🎯 HLS & ABR — how video streams smoothly on the web
- **HLS (HTTP Live Streaming)** — a streaming standard that splits a video into many small **segments** (a few seconds each) + a **playlist** listing them.
- **ABR (Adaptive Bitrate)** — the player automatically picks the resolution based on network speed: weak network → 480p, strong network → 1080p, switching smoothly mid-stream. Because 1 video = many segments across many quality levels → this is why Phase 5 uses a signed **cookie** rather than a signed URL.
- **Rendition** — one specific quality version (e.g. "the 720p version").

### 🎯 Event-driven & async architecture — "don't make the user wait"
Transcoding takes a while, so it's done **asynchronously (async)**: the upload returns immediately, and the heavy work is processed in the background.
| Component | Role |
|---|---|
| **S3 event / EventBridge** | When a new file lands in the raw bucket, S3 *emits an event* to notify the system. **EventBridge** is AWS's "event transit hub". |
| **SQS (Simple Queue Service)** | A message **queue**. Each video that needs transcoding = 1 message waiting in line. A worker pulls one out and processes them one by one. This decouples receiving the work from processing it. |
| **transcode-worker** | A pod running FFmpeg that pulls a message from SQS, transcodes it, writes the result to the transcoded bucket + updates DynamoDB. |

### 🎯 Queue durability (very important for the SRE story)
- **Visibility timeout** — when a worker pulls a message, the message is "hidden" for a period so another worker won't pick up the same one. If the worker finishes → it deletes the message; if the worker dies (e.g. its spot instance is reclaimed) → once the timeout expires, the message **reappears** for another worker → **no job is lost**.
- **DLQ (Dead Letter Queue)** — a message that fails more than N times is pushed to a "dead" queue for separate investigation, so it doesn't clog the main queue.
- 🎯 **Idempotent** — the worker is designed so that **processing the same video twice still yields the correct result**, without breaking. This is mandatory when using spot (a job may be re-run).
- **Spot interruption handler** — when AWS is about to reclaim a spot node, this component **drains** (gracefully evacuates) the pods; the SQS message goes back to the queue → the job gets re-run on another node.

### 🎯 KEDA — autoscaling by "queue depth"
**KEDA (Kubernetes Event-Driven Autoscaling)** — automatically increases/decreases the number of workers **based on the number of messages waiting in SQS**:
- Long queue → spin up more workers to clear it faster.
- Empty queue → **scale-to-zero** (down to 0 workers) → no cost while idle.
- ⚠️ Distinguish this from K8s's default **HPA (Horizontal Pod Autoscaler)** (which scales by CPU/RAM) — KEDA scales by *events/queues*, and can do scale-to-zero. This is a technical highlight worth showing off.

---

## Part 6 — Phase 4
### GitOps (ArgoCD) + Progressive Delivery (Argo Rollouts canary, auto-rollback)

> Goal: pushing to Git deploys automatically; upgrades are made safely, "released gradually".

### 🎯 ArgoCD — the GitOps reconciler
A tool that runs in the cluster, continuously **comparing Git ↔ cluster**:
- **Sync** — pull the desired state from Git and apply it to the cluster.
- **Drift / OutOfSync** — detects that someone made a manual change that drifted the cluster away from Git → alerts / auto-corrects it.
- **App of Apps** — an organizing pattern: one "root ArgoCD app" manages many child apps.
- **Benefit:** Git is the source of truth, every change has a history, and rollback = `git revert`.

### 🎯 Progressive Delivery & Argo Rollouts
Instead of swapping 100% of the old version for the new one all at once (high risk), **release gradually**:
- **Canary deployment** — send the new version to a **small fraction of traffic** first (e.g. 10%), watch it, and if it's healthy, ramp up gradually 25% → 50% → 100%. ("Canary" refers to the canary birds miners once used to warn of danger.)
- **Argo Rollouts** — the tool that performs canary releases for K8s (in place of a regular Deployment).
- 🎯 **Metric-based auto-rollback** — Rollouts watches metrics (error rate, latency); if the new version drives errors up → it **automatically reverts to the old version**, with no human intervention. This is the "money" feature to talk about in an SRE interview.
- **Blue/Green** (a related concept) — run 2 environments in parallel and switch all traffic instantly from "blue" (old) to "green" (new); easy to roll back. Canary, by contrast, ramps up *gradually by %*.

---

## Part 7 — Phase 5
### Membership: Cognito group, tier_required, CloudFront signed cookie, payOS + webhook

> Goal: a complete free/premium plan mechanism, with upgrades via sandbox payment.

### 🎯 CloudFront & CDN — "distribute content close to the user"
- **CDN (Content Delivery Network)** — a network of servers placed all over, *caching* content near users → faster loads.
- **CloudFront** — AWS's CDN, sitting in front of S3 to serve video/web.
- 🎯 **OAC (Origin Access Control)** — a mechanism so that **only CloudFront can read S3**, blocking outsiders who call S3 directly. This lets S3 stay **private** while still serving public content in a controlled way.

### 🎯 Signed cookie vs Signed URL — controlling who can watch a video
The problem: only `premium` users may watch premium videos, but the content lives on CloudFront.
- **Signed URL** — sign *each* individual link. Inconvenient, because 1 HLS stream is made of **very many** segments.
- 🎯 **Signed cookie** — sign **once for an entire path prefix** (e.g. all of `/videos/abc/*`). The browser attaches this cookie to every segment request → sign once, watch the whole video. **This is why the project chose signed cookies.**
- **Key group + private key** — CloudFront verifies the signature using a key pair. The **private key** (the secret used to sign) is extremely sensitive → stored in **Secrets Manager** and pulled into the pod via **External Secrets** (see Phase 6).
- **Short-lived cookie** — once it expires → CloudFront returns a **403** → the frontend requests a fresh signature on its own. (Safe: a ticket that expires quickly does little harm if leaked.)

### tier_required & watch authorization
Each video is tagged with `tier_required: free | premium`. The `playback-service` compares the **user's tier** (read from the Cognito group in the JWT) against the **video's tier_required**; only if it's valid does it issue a signed cookie.

### 🎯 payOS, Webhook, Idempotency — the payment flow
- **payOS** — a Vietnamese domestic payment gateway (QR / bank transfer). The project uses the **sandbox** (a simulation, no real money).
- **Payment link** — the `membership-service` creates a link/QR for the user to pay.
- 🎯 **Webhook** — after the user finishes paying, payOS **proactively calls back** into your API to report "payment complete". (The reverse of you calling them.) The service receives the webhook and then upgrades the user to `premium`.
- 🎯 **Signature verification** — check that the webhook *really* came from payOS (and isn't an impostor calling to get a free upgrade). payOS signs the request; you verify the signature.
- 🎯 **Idempotent by order ID** — payOS may call the webhook **multiple times** for the same order (due to network retries). The service must ensure that repeated processing **doesn't upgrade/record it twice** — it relies on the `order ID` to recognize "this order has already been processed". The idempotent concept repeats exactly as in SQS (Phase 3).

---

## Part 8 — Phase 6
### DevSecOps: Trivy, cosign, Kyverno, External Secrets, IRSA least-privilege

> Goal: a secure software supply chain — security "baked into" the CI/CD and the cluster.

### DevSecOps & Supply chain security
- **DevSecOps** — embed security into *every step* of DevOps (not a check at the very end).
- **Supply chain** — the entire journey from code → image → running. Every link can be attacked → each stage needs protecting.

### The tools
| Tool | What it does |
|---|---|
| 🎯 **Trivy** | **Scans for vulnerabilities** in an image (old libraries with CVEs, secrets accidentally committed). Runs in CI, fails the build if there's a serious vulnerability. |
| 🎯 **cosign** | **Digitally signs** an image to prove "this image was built by a trusted pipeline and hasn't been swapped out". |
| 🎯 **Kyverno** | **Policy-as-Code** for K8s: sets rules like "only allow signed images to run", "ban the `:latest` tag", "forbid running as root". Violations → the cluster rejects them. |
| **External Secrets Operator** | Automatically pulls secrets from AWS **Secrets Manager/SSM** into K8s, so that **secrets don't live in Git**. (Used to get the CloudFront private key into the pod — Phase 5.) |

- **CVE** — the standard identifier for a known security vulnerability.
- **Policy-as-Code** — write security/compliance rules as code and have the machine enforce them automatically (like IaC, but for *policy*).

### 🎯 IRSA & Least-privilege — minimum permissions for each service
- **IAM** — AWS's authorization system (who is allowed to do what to which resources).
- **Least-privilege** — each component is granted only the **minimum permissions it actually needs**, no more. E.g. the `transcode-worker` may only: *read* the raw bucket + *write* the transcoded bucket + *delete* SQS messages — nothing more.
- 🎯 **IRSA (IAM Roles for Service Accounts)** — a way to assign an IAM role to **each K8s service account** (instead of granting a blanket permission to the whole node). This gives each pod exactly its own permissions → minimizing the damage if one pod is compromised.
- **Service Account** — a pod's "identity" inside K8s.

---

## Part 9 — Phase 7
### Observability: Container Insights, ADOT/X-Ray, Managed Grafana, SLO/alarm, k6

> Goal: "see" how the running system is behaving; finish off the portfolio documentation.

### 🎯 Observability — the 3 pillars
**Observability** = the ability to understand *what's happening inside* a system from the signals it emits. 3 kinds of signals:
- **Metrics** — measurements over time (CPU, request count, latency).
- **Logs** — a text-based record of events.
- 🎯 **Traces** — follow **a single request as it passes through multiple services** (e.g. a playback request stopped by catalog → cognito → cloudfront, and how long it spent at each leg). Important in microservices for finding "where the bottleneck is".

### The tools
| Tool | Role |
|---|---|
| **CloudWatch** | AWS's all-in-one logs/metrics/alarm service. |
| **Container Insights** | A CloudWatch feature specialized in collecting EKS metrics/logs (pod, node, cluster). |
| 🎯 **X-Ray** | AWS's **distributed tracing** service — maps out a request's path through the services. |
| **ADOT / OpenTelemetry (OTel)** | **OpenTelemetry** is the open standard for collecting metrics/logs/traces; **ADOT** is AWS's distribution of it. The app emits signals to this standard → pushes them into X-Ray/CloudWatch. |
| **Amazon Managed Grafana** | A tool for **drawing visual dashboards** from metrics — a nice monitoring screen for demos. |

### 🎯 SLO / SLI / SLA & Alarm — the core language of SRE
- **SLI (Service Level Indicator)** — the *metric that measures* service quality (e.g. % of successful requests, p95 latency).
- **SLO (Service Level Objective)** — the *target* set for an SLI (e.g. "99.9% of playback requests < 300ms"). 🎯 This is a central concept you must speak fluently about when applying for SRE roles.
- **SLA (Service Level Agreement)** — a *contractual commitment* to the customer (with compensation if breached). An SLO is usually stricter than an SLA.
- **Error budget** — the remaining "allowed to fail" portion (e.g. an SLO of 99.9% → 0.1% is allowed to fail). Budget used up → prioritize stability over shipping new features.
- **Alarm** — an automatic alert when a metric crosses a threshold (e.g. a sudden spike in errors) → notifies you to act.

### Load test & k6
- **Load test** — fire a large volume of simulated traffic to see how far the system can hold up.
- **k6** — a load-testing tool (scripts written in JavaScript). Used to **prove that HPA/KEDA auto-scale** under load → gather numbers/charts for a blog post. This is strong "evidence" for the portfolio.

### Runbook
A document with step-by-step instructions for handling an incident ("when alarm X fires → do Y"). A signature documentation deliverable of SRE.

---

## Part 10 — Quick-reference table

| Abbreviation | Full name | One line |
|---|---|---|
| **IaC** | Infrastructure as Code | Infrastructure written as code, stood up/torn down automatically. |
| **VPC** | Virtual Private Cloud | Your virtual private network on AWS. |
| **AZ** | Availability Zone | A physical data center within a region. |
| **EKS** | Elastic Kubernetes Service | Kubernetes managed by AWS. |
| **K8s** | Kubernetes | The operating system that orchestrates containers. |
| **ECR** | Elastic Container Registry | The Docker image store. |
| **S3** | Simple Storage Service | File/object storage. |
| **OAC** | Origin Access Control | Only CloudFront can read the private S3. |
| **CDN** | Content Delivery Network | A network that caches content near users. |
| **SQS** | Simple Queue Service | A message queue. |
| **DLQ** | Dead Letter Queue | A queue holding messages that failed repeatedly. |
| **HLS** | HTTP Live Streaming | A video streaming standard that splits into segments. |
| **ABR** | Adaptive Bitrate | Automatically changes video quality based on the network. |
| **KEDA** | Kubernetes Event-Driven Autoscaling | Scales by queue, supports scale-to-zero. |
| **HPA** | Horizontal Pod Autoscaler | Scales by CPU/RAM (K8s default). |
| **CI/CD** | Continuous Integration/Delivery | Automated build/test/deploy. |
| **OIDC** | OpenID Connect | GitHub into AWS without long-lived keys. |
| **ALB** | Application Load Balancer | AWS's HTTP load balancer. |
| **ACM** | AWS Certificate Manager | Issues HTTPS certificates for free. |
| **TLS** | Transport Layer Security | Encrypts the connection (HTTPS). |
| **DNS** | Domain Name System | Translates domain names into IPs. |
| **NS** | Name Server | The record that delegates DNS authority. |
| **JWT** | JSON Web Token | A signed "ticket" proving identity/permissions. |
| **IAM** | Identity and Access Management | AWS's authorization system. |
| **IRSA** | IAM Roles for Service Accounts | Assigns IAM permissions to each pod. |
| **CVE** | Common Vulnerabilities and Exposures | The identifier for a known vulnerability. |
| **SLI/SLO/SLA** | Service Level Indicator/Objective/Agreement | Indicator / target / commitment for quality. |
| **OTel/ADOT** | OpenTelemetry / AWS Distro for OTel | The standard for collecting metrics/logs/traces. |

---

> **Study tip:** don't read it all in one sitting. Before each phase, re-read Part 1 + that phase's specific part. When you hit an unfamiliar term while working, look it up in Part 10 and then return to the detailed section. If you'd like, I can go deeper on *one* specific phase (e.g. drawing the transcode flow diagram, or writing an example Terraform VPC module) — just say which phase.
