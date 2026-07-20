# ADR-0006: EKS node groups & cluster access


- **Date:** 2026-07-20
- **Phase:** Phase 1


## Context
The `eks` module must provision a cluster that (a) lets the right IAM principals reach the API, (b) runs the always-on API workload cheaply while (c) reserving cheap, interruptible capacity for the Phase 3 transcode worker without paying for it at rest. Three sub-decisions follow: how to grant cluster access, how to split node capacity, and how to keep spot capacity isolated. Constraints are the usual ones: cost (ephemeral, scale-to-zero at rest), clean `destroy`, and a strong learning/CV signal.

## Options considered

### A. Cluster access — Access Entries vs `aws-auth` ConfigMap
1. **`aws-auth` ConfigMap** — the legacy method: map IAM ARNs to K8s groups inside an in-cluster YAML. A single typo can lock every operator out, and the mapping lives outside Terraform state (no plan/rollback).
2. **EKS Access Entries** (`aws_eks_access_entry` + `aws_eks_access_policy_association`) — the modern AWS API: access is a first-class AWS resource, declarable in Terraform, with state and rollback.

### B. Node capacity — single group vs on-demand + spot split
1. **Single on-demand group** — simplest, but pays full price for burstable transcode capacity and mixes system pods with interruptible ones.
2. **Two groups: on-demand (API) + spot (transcode)** — on-demand keeps system add-ons/API stable; spot (desired 0) carries transcode at ~70% discount and costs nothing at rest.

### C. Spot isolation — taint/label vs unguarded
1. **Unguarded spot** — any pod may land on spot nodes and be killed on interruption.
2. **Taint `dedicated=transcode:NoSchedule` + label `workload=transcode`** — only pods that explicitly tolerate the taint (the transcode worker) schedule there; the label lets them target it.

## Decision
- **A → Access Entries.** Declarative, state-tracked, no risk of a broken ConfigMap locking us out. `AmazonEKSClusterAdminPolicy` is granted at cluster scope to the operator principal and the CI role via `for_each`; scope can be tightened per-namespace later (Phase 6 least-privilege).
- **B → on-demand + spot split.** On-demand `t3.medium` (desired 2 / min 1 / max 3) runs the API and system add-ons. Spot (multiple instance types, desired 0 / min 0 / max 4) proves the group exists with zero spend until Phase 3 wires KEDA.
- **C → taint + label.** The spot group carries `dedicated=transcode:NoSchedule` + `workload=transcode`, so system and API pods never land on interruptible capacity.

## Consequences
- Positive: access is fully IaC and safe to change; no spend for transcode capacity at rest; system workloads isolated from spot interruptions; strong CV signal (modern Access Entries API, spot cost engineering).
- Trade-offs / risks:
  - EKS control-plane version pinned to **1.36** (D2) — must be verified GA in `ap-southeast-1` before the first `apply`; drop to the newest available version if not.
  - Spot capacity can be reclaimed; acceptable because transcode jobs are idempotent and re-queued (Phase 3 handles drain/redrive).
  - `desired_size = 0` on spot: when KEDA/autoscaler manages desired size in Phase 3, add `lifecycle { ignore_changes = [scaling_config[0].desired_size] }` so Terraform stops resetting it to 0.
- Follow-up: node IAM role carries only the three baseline managed policies (worker, CNI, ECR read-only); EBS CSI uses a dedicated IRSA role. Per-service IRSA roles arrive in Phase 2 off the OIDC provider output.

## References
- Design spec §3.2 (EKS module): [../superpowers/specs/2026-07-16-streamforge-phase1-design.md](../superpowers/specs/2026-07-16-streamforge-phase1-design.md)
- Implementation: `infra/modules/eks/main.tf`
- Related: [0004-regional-natgw.md](0004-regional-natgw.md) (network egress the nodes depend on)
