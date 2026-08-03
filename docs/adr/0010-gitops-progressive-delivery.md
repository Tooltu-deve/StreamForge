# ADR-0010: GitOps delivery with ArgoCD (app-of-apps) + progressive delivery


- **Date:** 2026-08-02
- **Phase:** Phase 4


## Context

Through Phase 3 the app reached the cluster by **push-based deploy**: CI ran `helm upgrade`
straight onto EKS. That couples the CI runner to cluster credentials, leaves no single source
of truth for "what is actually running", and cannot self-heal drift (a manual `kubectl edit`
goes unnoticed). Phase 4 must turn deployment into **GitOps** — Git is the desired state and an
in-cluster agent continuously reconciles the cluster toward it — and then add **progressive
delivery** so a bad `catalog` build rolls back on its own instead of taking all traffic.

Constraints: the cluster is **ephemeral** (apply/destroy ~$0), the project is 100% IaC
(Terraform), GitOps config lives in a **separate repo** (ADR-0002) to avoid a CI→commit→CI
loop, and observability is not built until Phase 7 (so 4b needs its own minimal metric source).

## Options considered

**1. Deploy model — push (`helm upgrade` from CI) vs pull (ArgoCD).**
   - *Push:* simplest, already working; but CI holds cluster creds, no drift detection, no self-heal.
   - *Pull (ArgoCD):* CI never touches the cluster; Git is the source of truth; drift is auto-reverted.

**2. Config repo — mono-repo vs separate (already settled in ADR-0002).** Separate repo
   `StreamForge-Gitops` (public) — avoids the image-bump commit re-triggering the app CI, and
   lets ArgoCD read a public repo with no credentials.

**3. Multi-app management — manual per-app vs app-of-apps.**
   - *Manual:* `kubectl apply` each Application — imperative, defeats the point.
   - *App-of-apps:* one root Application (bootstrapped once by Terraform) discovers child
     Applications under `apps/`; adding a service is one file in Git, no cluster/Terraform change.

**4. Root-app bootstrap in Terraform — `kubernetes_manifest` vs a local Helm chart.**
   - *`kubernetes_manifest`:* validates the resource schema at **plan** time; on a fresh cluster
     the `Application` CRD does not exist yet → plan fails (chicken-and-egg).
   - *Local Helm chart via `helm_release`:* Helm applies at run time, not plan time; ordered
     after the ArgoCD release (which installs the CRD) with `depends_on`. No plan-time CRD needed.

**5. Cross-repo image-tag write — fine-grained PAT vs GitHub App vs deploy key.**
   - Public config repo means ArgoCD reads with no creds; only the **write** side (CI bumping the
     tag) needs auth. A fine-grained PAT (contents:write, that repo only) is the least moving
     parts for a solo ephemeral project; a GitHub App is more robust but heavier setup.

**6. Progressive-delivery metric provider — Prometheus vs CloudWatch vs job-based.**
   Prometheus (kube-prometheus-stack, Grafana/Alertmanager off) — self-contained, clear canary
   story; Grafana deferred to Phase 7. *(Full 4b rationale is filled in when slice 4b lands.)*

## Decision

Adopt **pull-based GitOps with ArgoCD, app-of-apps, and an automated sync policy**, plus (slice
4b) **Argo Rollouts canary with a Prometheus-backed analysis** for `catalog`.

- **ArgoCD installed by Terraform** as a platform add-on (`infra/modules/argocd`, same pattern
  as LBC/KEDA/CA), namespace `argocd`, chart CRDs removed on uninstall (`crds.keep=false`) so
  `terraform destroy` stays clean.
- **One root Application** created by Terraform via a **local Helm chart** (`root-app/`), pointing
  at `StreamForge-Gitops/apps` with `directory.recurse`. It is the single bootstrap seam; every
  other Application is declared in Git.
- **Automated sync everywhere** — `syncPolicy.automated { prune: true, selfHeal: true }` +
  `CreateNamespace=true`, and the `resources-finalizer.argocd.argoproj.io` finalizer for clean
  cascade deletes.
- **Charts copied into the config repo** (ADR-0002); per-service `values/*.yaml` are **seeded
  from Terraform outputs** by `scripts/seed-gitops-values.sh` on each provision (ephemeral infra
  regenerates role ARNs / Cognito IDs). Only `image.tag` changes afterwards, and only via CI.
- **Ingress stays out of GitOps (Phase 4).** The ALB ingress carries an edge secret
  (`originSecret`, the `X-Origin-Secret` header shared with CloudFront) that must not live in
  the **public** config repo, and it has no image to bump. It is deployed out-of-band via
  `helm --set` (sourced from `edge/dev` tfvars), alongside the edge layer, and **joins GitOps in
  Phase 6** once External Secrets can inject the secret. Switching the config repo to private was
  considered but rejected for now: it would hide the resource inventory but still would not make
  plaintext secrets in Git acceptable (permanent history, no encryption/rotation), and it adds an
  ArgoCD repo credential to seed on every ephemeral provision.
- **CI stops deploying.** `build-scan-push.yaml` gains a `bump-gitops` job that writes the new
  `sha-<12>` tag into `StreamForge-Gitops/values/<svc>.yaml` with the `GITOPS_PAT` fine-grained
  token; ArgoCD then auto-syncs. The config repo has its own **offline** gate (`helm template` +
  `kubeconform`) so PRs validate with the cluster down.
- **Progressive delivery (slice 4b):** `catalog` becomes an Argo Rollouts `Rollout` (canary
  10→25→50→100%); an `AnalysisTemplate` queries Prometheus success-rate and **aborts (rolls
  back)** on a bad build. Argo Rollouts + Prometheus are themselves managed by ArgoCD (app-of-apps,
  sync-wave `-1`). *Detailed 4b decisions are appended when that slice is implemented.*

## Consequences

- Positive: CI no longer holds cluster credentials; Git is the single source of truth with full
  history/rollback (`git revert`); drift is auto-reverted (`selfHeal`); adding a workload is a
  one-file Git change; teardown is clean (finalizers + `crds.keep=false`).
- Trade-offs / risks: the `values/*.yaml` **re-seed** is a non-pure-GitOps seam forced by the
  ephemeral cluster (dynamic ARNs/Cognito IDs) — documented as a per-provision step, not
  automated away (the seam only disappears if those IDs become stable, which `user_pool_id`
  cannot). The PAT is a personal token to rotate. Scale-out/rollback has extra latency vs a plain
  push deploy (ArgoCD poll + reconcile).
- Follow-up work this entails: create `StreamForge-Gitops`; add `GITOPS_PAT` secret; (later,
  Phase 6) move app runtime secrets through Secrets Manager + External Secrets — never into the
  public config repo; (optional, post-Phase 6) move `terraform apply` + seed into a gated
  `provision`/`destroy` CI once IAM is least-privileged.

## References

- Design spec: `docs/superpowers/specs/2026-08-02-streamforge-phase4-design.md`
- Implementation plan: `docs/superpowers/plans/2026-08-02-streamforge-phase4a.md`
- Runbook: `docs/runbook/phase4.md`
- ADR-0002 (separate gitops repo), ADR-0007 (platform add-on layering), ADR-0009 (KEDA/CA add-on pattern reused).
