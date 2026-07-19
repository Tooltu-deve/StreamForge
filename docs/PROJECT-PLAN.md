# StreamForge Project Execution Plan — following professional SDLC standards



## Context

StreamForge is a portfolio project that demonstrates **DevOps / Platform / SRE** capabilities: a video-streaming platform (a Netflix/YouTube clone) that runs itself on EKS, is deployed via GitOps, is 100% IaC (Terraform), and is ephemeral (apply/destroy ~ $0). The design doc has finalized the architecture and 8 phases (Phase 0–7).

This document turns that roadmap into a **detailed execution plan**: a 12-week timeline (~20-25h/week), broken down task-by-task, where each phase goes through a **full SDLC cycle** and ends with an independent, **CV-worthy milestone**.

---

## 1. SDLC methodology applied (read first — used for EVERY phase)

### 1.1 Lifecycle of each phase (Phase = one "mini-SDLC")
Each phase, Phase 0–7, runs through 5 steps, with no skipping. The phase's objective and acceptance criteria (DoD) are written directly at the top of the ADR/runbook — **not tracked via GitHub issues** (this is a solo project, so that overhead is dropped).

| Step | Work | Required artifact |
|---|---|---|
| **1. Design** | Finalize objective + acceptance criteria (DoD); architecture diagram for the newly added part + technical decisions (short ADR). | `docs/adr/NNNN-*.md` + diagram. |
| **2. Implement** | Code/IaC on a **feature branch**, small commits, conventional commits. | Branch `feat/gd-N-*`. |
| **3. Test** | Unit + validate + smoke test on ephemeral resources. | Test pass log / green CI. |
| **4. Review** | Open a **PR** → CI gate runs (lint/scan/plan) → self-review checklist → merge. | Merged PR, green CI. |
| **5. Document** | Update the phase README + runbook + record the "CV milestone". | `docs/runbook/gd-N.md`. |

### 1.2 Git & branch conventions
- `main` is protected (no direct pushes); every change goes through a **PR**.
- Branch: `feat/gd-1-vpc-eks`, `fix/...`, `docs/...`, `chore/...`.
- **Conventional Commits**: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`.
- 1 PR = 1 small unit of review; the PR template has a checklist (tests pass? docs updated? `destroy` clean?).

### 1.3 CI gate (enabled from Phase 0, strengthening over time)
- **Phase 0+**: `terraform fmt -check`, `terraform validate`, `tflint`, `checkov`, `terraform plan` auto-commented on the PR.
- **Phase 2+**: build image → `trivy` scan → push ECR (via OIDC, no keys).
- **Phase 4+**: ArgoCD dry-run diff on the PR; Kyverno policy test.
- **Phase 6+**: `cosign` sign + verify; fail the build on HIGH/CRITICAL CVEs.

### 1.4 Shared Definition of Done (every phase)
- [ ] Green CI on the PR; code merged into `main`.
- [ ] `terraform apply` builds everything from scratch; `terraform destroy` cleans up **completely** (no leftover cost-incurring resources: NAT GW, EIP, LB, EBS).
- [ ] An ADR exists for the main technical decision.
- [ ] The phase runbook is updated (how to provision, how to verify, how to tear down).
- [ ] The phase objective is demonstrable (screenshot/log/clip saved to `docs/evidence/`).

### 1.5 Cost management (throughout)
- Default to **destroy at the end of each session**; only apply while actively working.
- Set up an **AWS Budget alarm** right in Phase 0. Tag every resource `project=streamforge`.
- Spot for transcoding; scale-to-zero when idle.

---

## 2. Timeline overview (12 weeks, starting 2026-06-29)

| Week | Date (2026) | Phase | Focus | CV milestone | Status |
|---|---|---|---|---|---|
| **1** | 29/06 – 05/07 | Phase 0 | Foundation: repo, TF backend, Route53, ACM, CI baseline | Domain + secure state | ✅ |
| **2-3** | 06/07 – 19/07 | Phase 1 | Core infrastructure: VPC, EKS, node groups, S3, DynamoDB, Cognito, ECR | `apply` builds the whole foundation | ☐ |
| **4-5** | 20/07 – 02/08 | Phase 2 | Dockerize 5 services + FE, Helm, ALB Ingress, external-dns, cert-manager, CI/CD | Reach `app.<domain>`, upload+watch | ☐ |
| **6-7** | 03/08 – 16/08 | Phase 3 | Transcode pipeline: S3→SQS→FFmpeg worker(spot)→HLS→DynamoDB, KEDA, DLQ | Auto-transcode, ABR streaming | ☐ |
| **8** | 17/08 – 23/08 | Phase 4 | GitOps ArgoCD + Argo Rollouts canary + auto-rollback | Push to Git = deploy, canary | ☐ |
| **9-10** | 24/08 – 06/09 | Phase 5 | Membership: Cognito group, tier_required, CloudFront signed cookie, payOS+webhook | Complete paid tier | ☐ |
| **11** | 07/09 – 13/09 | Phase 6 | DevSecOps: Trivy gate, cosign, Kyverno, External Secrets, IRSA least-privilege | Secure supply chain | ☐ |
| **12** | 14/09 – 20/09 | Phase 7 | Observability: Container Insights, ADOT/X-Ray, Managed Grafana, SLO/alarm, k6, blog | Finalization + documentation | ☐ |

> Buffer: if all 12 weeks are used up, Phase 3 and Phase 5 are the two hardest parts — prioritize buffer there. If short on time, the "advanced" parts can be cut (see YAGNI §9 of the design doc), keeping the backbone intact.
>
> ¹ **Phase 0 done** except **Route53 + ACM**, which are **deferred** (the hosted zone is in a separate AWS account — cross-account access). These must be completed before Phase 2.

---

## 3. Task details by phase

### Phase 0 — Foundation (Week 1)
**Status:** ✅ **Done** — remote state backend (S3 + KMS + native lock), foundation stack (GitHub OIDC provider + CI IAM role), and the Terraform CI workflow (fmt/validate/tflint/checkov + plan-comment, auth via OIDC) are live and green. ⏸️ **Route53 + ACM (tasks 3–4) deferred** — hosted zone is cross-account; complete before Phase 2. AWS Budget was created via the console (task 5; not yet codified in Terraform).

**Requirements:** secure TF state + domain pointing to Route53 + certificates ready + a CI baseline for Terraform.

**Tasks**
1. `chore: repo skeleton` — create the tree `infra/ services/ frontend/ .github/workflows/ docs/`; root README; `.gitignore`; `.editorconfig`; pre-commit (`terraform fmt`, `tflint`). GitOps config lives in a separate repo `streamforge-gitops` (see ADR-0002).
2. `feat: tf remote backend` — S3 bucket (versioned, KMS-encrypted) + DynamoDB lock table; write the `infra/bootstrap/` module. ⚠️ "Chicken-and-egg" loop: bootstrap uses local state, then migrates to remote.
3. `feat: route53 + delegate NS` — Hosted Zone; export the NS record; **manually** update the NS records at the domain provider → verify with `dig NS <domain>`.
4. `feat: acm certs` — 1 cert in `us-east-1` (CloudFront) + 1 cert in `ap-southeast-1` (ALB), DNS-validated automatically via Route53.
5. `chore: aws budget + tagging policy` — Budget alarm at a $ threshold; default tags via the provider's `default_tags`.
6. `ci: terraform pipeline` — workflow: `fmt/validate/tflint/checkov` + `plan` commented on the PR; configure a GitHub→AWS **OIDC role** (no access keys).

**DoD:** `dig` shows Route53 NS records; `terraform apply/destroy` runs with remote state + locking; the first PR has an auto-commented plan; the budget alarm is active.
**ADR:** choice of remote backend S3+DynamoDB; single-env modularization strategy.

---

### Phase 1 — Core infrastructure (Week 2-3)
**Requirements:** a single `terraform apply` builds the entire platform from scratch.

**Tasks**
1. `feat: module vpc` — VPC, public/private subnets across ≥2 AZs, IGW, NAT GW (consider **1 NAT to save cost**), route tables, VPC endpoints (S3/ECR to reduce NAT cost).
2. `feat: module eks` — EKS cluster; **2 managed node groups**: on-demand (API) + spot (transcode, taint+label); OIDC provider for IRSA; aws-auth.
3. `feat: module s3` — raw / transcoded / frontend buckets (private, block public, encrypt, lifecycle to delete raw after N days).
4. `feat: module dynamodb` — catalog/metadata table (PK/SK design, on-demand billing).
5. `feat: module cognito` — User Pool + App Client (`generate_secret=false`, SRP flow) + `free`/`premium` groups. Custom UI via SDK; no Hosted UI domain.
6. `feat: module ecr` — repos for each service; scan-on-push enabled.
7. `refactor: root module wiring` — `infra/env/dev/` assembles the modules; `terraform output` exposes values for later phases.
8. `test: infra validation` — `checkov` passes; `terraform plan` shows zero-diff after apply; smoke: `kubectl get nodes` shows both node groups.

**DoD:** `apply` from scratch produces a running cluster + all resources; `kubectl` can connect; `destroy` is clean.
**ADR:** 1-NAT vs multi-NAT (cost vs HA); DynamoDB key schema; spot taint strategy.

---

### Phase 2 — Package & run the app + CI/CD (Week 4-5)
**Requirements:** reach `app.<domain>` over HTTPS, upload + watch (no transcoding yet).

**Tasks**
1. `feat: services skeleton` — 5 FastAPI services (`catalog/upload/playback/membership/transcode-worker`) with minimal scaffolding + healthz/readyz; a shared `pyproject`.
2. `test: unit tests` — pytest + `moto` mocking S3/DynamoDB for catalog & upload (presigned URL).
3. `feat: dockerize` — multi-stage Dockerfile, non-root, slim; `.dockerignore`.
4. `feat: frontend SPA` — minimal React (list, upload form, player); build → S3 + CloudFront (OAC).
5. `feat: helm charts` — 1 base chart + values for each service (replicas, resources, probes, env).
6. `feat: cloudfront-fronted ingress` — AWS Load Balancer Controller, external-dns, cert-manager. **CloudFront is the single public entry** (default → S3 frontend, `/api/*` → ALB origin, HLS → S3 transcoded via OAC); lock the ALB to CloudFront-only (origin secret header + security-group scoping via the CloudFront managed prefix list). See the data-plane diagram (§ docs/diagrams) + ADR.
7. `ci: build-scan-push` — workflow to build image → trivy scan → push ECR via OIDC; tag by git SHA.
8. `ci: deploy dev` — `helm upgrade` onto the cluster (temporary; Phase 4 will replace this with ArgoCD).
9. `test: smoke e2e` — log in to Cognito → upload a file → see the DynamoDB record → download it back from S3.

**DoD:** HTTPS access via the custom domain; upload works; CI/CD push→deploy is automatic; unit tests are green.
**ADR:** Helm chart structure (umbrella vs per-service); image tagging.

---

### Phase 3 — Transcode pipeline (Week 6-7) 🎯 *the hardest*
**Requirements:** after upload, auto-transcode to multi-bitrate HLS, watch with ABR; resilient to spot interruption.

**Tasks**
1. `feat: s3 event → eventbridge → sqs` — wire S3 raw events → SQS (main queue + **DLQ**, redrive policy, sensible visibility timeout).
2. `feat: transcode-worker` — consume SQS, use FFmpeg to produce 240/480/720/1080p renditions + HLS playlist, write to the transcoded bucket, update DynamoDB status. 🎯 **Idempotent by video ID** (re-runs don't break anything).
3. `feat: keda scaledobject` — scale workers by SQS depth; **scale-to-zero**; install KEDA via Helm.
4. `feat: spot resilience` — node termination handler drain; verify the message returns to the queue when the pod is killed mid-way.
5. `feat: playback HLS` — playback-service returns the manifest; ABR player (hls.js).
6. `test: light chaos` — deliberately kill the worker mid-transcode → the job re-runs on its own, nothing is lost; a failing message → goes to the DLQ after N attempts.
7. `test: light load` — inject many uploads → observe KEDA spinning up workers.

**DoD:** upload → auto-transcode → smooth ABR playback; killing the worker doesn't lose the job; idle → 0 workers.
**ADR:** SQS timeout/redrive params; rendition ladder; idempotency key design.
**Runbook:** "stuck job / full DLQ → how to handle it".

---

### Phase 4 — GitOps + Progressive Delivery (Week 8)
**Requirements:** push to Git = deploy; safe canary upgrades, auto-rollback.

> **Note:** all manifests/charts/policies live in the **separate config repo** `streamforge-gitops` (see ADR-0002), not in this repo. ArgoCD watches the config repo; this repo's CI commits image-tag bumps into it (cross-repo, via a scoped token/PAT).

**Tasks**
1. `feat: argocd install` — install ArgoCD (via Helm/manifest); point it at the `streamforge-gitops` config repo.
2. `refactor: app-of-apps` — move all Phase 2/3 manifests into `streamforge-gitops` under ArgoCD management; remove manual deploy from CI (CI only builds/scans/pushes + bumps the image tag in the config repo).
3. `feat: argo rollouts canary` — move `catalog-service` to a Rollout; canary steps 10→25→50→100%.
4. `feat: auto-rollback` — AnalysisTemplate based on metrics (error rate/latency from Prometheus/CloudWatch); on failure → auto-rollback.
5. `ci: gitops gate` — ArgoCD diff dry-run commented on the PR (in the config repo).
6. `test: real canary` — deploy a "deliberately broken" build → confirm auto-rollback; deploy a good build → promote gradually.

**DoD:** change the image tag in the config repo → ArgoCD auto-syncs; a failing canary rolls back on its own; OutOfSync is detected.
**ADR:** choice of metric provider for analysis; sync policy (auto vs manual prune).

---

### Phase 5 — Membership (Week 9-10) 🎯 *many security building blocks*
**Requirements:** complete free/premium tiers; upgrade via payOS sandbox.

**Tasks**
1. `feat: tier model` — add `tier_required` to a video; playback compares the user's tier (Cognito group in the JWT) vs the video's.
2. `feat: cloudfront signed cookie` — playback-service issues a signed **cookie** scoped by path prefix; key group + public key on CloudFront; **private key in Secrets Manager**.
3. `feat: short-lived cookie flow` — cookie expires → 403 → FE re-requests it automatically.
4. `feat: payos integration` — membership-service creates a payment link (QR); a sandbox checkout page.
5. `feat: payos webhook` — endpoint that receives the webhook; 🎯 **verify the signature** + 🎯 **idempotent by order ID**; return 200 quickly, process asynchronously; on success → change the Cognito group to `premium`.
6. `feat: circuit breaker` — timeout/retry/circuit-breaker when calling payOS.
7. `test: authorization` — a free user can't watch a premium video (403); after payment → they can.
8. `test: webhook` — call the webhook twice (idempotent), wrong signature (rejected), unknown order (ignored).

**DoD:** the full free→pay→premium→watch-premium-video flow works; replaying the webhook doesn't upgrade twice; a forged signature is blocked.
**ADR:** signed cookie vs URL (cookie chosen — record the rationale); webhook idempotency store handling.
**Runbook:** "webhook fail / mass signed-cookie 403s".

---

### Phase 6 — DevSecOps (Week 11)
**Requirements:** a secure supply chain, policies enforced in the cluster, least privilege.

**Tasks**
1. `ci: hard trivy gate` — fail the build on HIGH/CRITICAL CVEs; scan IaC too (`checkov`/`trivy config`).
2. `feat: cosign sign` — sign the image in CI (keyless OIDC if possible); store the signature.
3. `feat: kyverno policies` — only allow signed images + from your own ECR; forbid `:latest`; forbid root; require resource limits & probes; verify on the cluster.
4. `feat: external secrets` — ESO pulls secrets (CloudFront private key, payOS key) from Secrets Manager → K8s Secret; remove all secrets from Git/Helm values.
5. `refactor: irsa least-privilege` — audit each service account, tighten policies to the minimum (e.g., worker: read raw + write transcoded + delete SQS msg). Document the permission matrix.
6. `feat: waf web acl` — attach an AWS WAF web ACL to CloudFront (AWS managed rule sets: common + SQLi + a rate-based rule); protects the public app and the payOS webhook path.
7. `test: policy & perms` — deploy an unsigned image → blocked by Kyverno; a pod missing permissions → clear error (proving least-privilege).

**DoD:** an unsigned image can't be deployed; no secret is in Git; each SA has a minimal policy along with a reference table.
**ADR:** keyless vs key-based cosign; scope of Kyverno enforce vs audit.

---

### Phase 7 — Observability + finalization (Week 12)
**Requirements:** the system is observable; there are SLOs/alarms/dashboards; portfolio documentation.

**Tasks**
1. `feat: container insights` — enable EKS metrics/logs to CloudWatch.
2. `feat: adot + x-ray` — instrument FastAPI with OpenTelemetry; the ADOT collector pushes traces → X-Ray; view the service map.
3. `feat: managed grafana` — dashboards: cluster overview, SQS depth + worker count, API latency/error, canary.
4. `feat: slo + alarm` — define SLIs/SLOs (e.g., playback success 99.9%, p95 latency); CloudWatch alarms + error budget.
5. `test: k6 load test` — playback + upload scenarios; prove HPA/KEDA scaling; save the metrics/charts.
6. `docs: portfolio package` — architecture README + diagram, ADR index, overall runbook, a "platform storytelling" blog post, a demo clip; "how to run from scratch".

**DoD:** live dashboards; alarms fire when thresholds are exceeded; traces span services; a k6 report + autoscale charts; documentation sufficient for a stranger to rebuild it.
**ADR:** choice of SLIs/SLOs & alarm thresholds.

---

## 4. Cross-cutting (done continuously, not a single phase)
- **CI/CD**: runs from Phase 0 (Terraform) → strengthens over time (scan/sign/gitops gate).
- **Documentation**: every PR updates docs; an ADR for every decision; the runbook accumulates.
- **Cost hygiene**: destroy at end of session; budget alarm; tagging; cost review at the end of each week.
- **Security**: least-privilege from the start (don't leave it to the end); never commit secrets.
- **Evidence for the CV**: screenshot/clip/log at each milestone → `docs/evidence/`.

---

## 5. Verification (how to sign off the whole project)
Final success criteria (per §10 of the design doc):
1. `terraform apply` builds the whole platform from scratch; `destroy` cleans up completely (verified via Cost Explorer + an empty `terraform state list`).
2. Upload a video → auto-transcode → watch with ABR over the custom domain (HTTPS).
3. The free/premium tiers work correctly via CloudFront signed cookies + upgrade via payOS sandbox (idempotency + signature tested).
4. Push code → CI scan/sign → ArgoCD deploy → safe canary rollout (auto-rollback tested).
5. Dashboards + SLOs + alarms + a k6 report exist; a blog/docs/runbook exist.

**Sign-off for each phase**: run that phase's DoD checklist (section §3) + save evidence; only move to the next phase once the PR is merged and `destroy` is clean.
