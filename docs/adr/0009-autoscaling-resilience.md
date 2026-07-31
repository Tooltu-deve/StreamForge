# ADR-0009: Autoscaling the transcode worker to zero (KEDA + Cluster Autoscaler)


- **Date:** 2026-07-30
- **Phase:** Phase 3 (slice 3b)


## Context

Worker Transcode is stateless and is an unpredictable workload, which incurs cost even when the worker is in idle. Therefore, it is essential and beneficial to implement a solution to autoscale the worker nodes as well as pods based on a specific metric. The target is to minimize cost to zero while idle in both node and pod level.

Constraints: the eks cluster is using managed node group, minimize operational cost. API services are out of scope in this solution because they are long-term services running continously to process requests from users at any time. Scaling these services down to zero may lead to unwanted slow response or even disconnection from user interface.

Two independent layers must scale for true scale-to-zero: the **pod** layer (worker replicas) and the **node** layer (spot EC2 instances). Scaling only pods leaves them `Pending` on a node group that sits at 0 nodes; scaling only nodes never removes idle worker pods.

## Options considered

1. **Scale pod — KEDA vs HPA**
   - *HPA:* cannot scale-to-zero, only supports scaling based on CPU/memory.
   - *KEDA:* strongly support scale-to-zero and based on queue size, which is more suitable for this project as transcode worker is a consumer of a SQS.

2. **Scale node — Cluster Autoscaler vs Karpenter**
   - *Cluster Autoscaler:* works with the existing managed node group via auto-discovery tags; adjusts the node group's desired capacity when pods are `Pending`; easy to set up on top of what Phase 1 already built.
   - *Karpenter:* provisions right-sized EC2 directly (no node group), faster and more flexible, but replaces the managed-node-group model already in place — more setup and a bigger change than this project needs.

## Decision

Chosen: a **two-layer scale-to-zero** design.

- **Pods — KEDA:** a `ScaledObject` scales the worker Deployment by SQS depth
  (`aws-sqs-queue` trigger, `queueLength=1`), with `minReplicaCount: 0`. KEDA handles the 0↔1
  activation that plain HPA cannot, and manages an HPA underneath for 1→N.
- **Nodes — Cluster Autoscaler:** installed in `kube-system`, it discovers the spot node group via
  the tags `k8s.io/cluster-autoscaler/enabled=true` and `k8s.io/cluster-autoscaler/streamforge-dev=owned`,
  and scales it 0↔4 as worker pods go `Pending` / idle.
- **KEDA identity:** the KEDA operator reads the queue depth through its own IRSA role
  (`identityOwner: operator`), scoped to the minimum `sqs:GetQueueAttributes` on the transcode queue.
- **Worker on spot:** the worker Deployment carries a toleration for the spot taint
  `dedicated=transcode:NoSchedule` and a nodeSelector `workload=transcode`, so it lands only on spot.
- **Both layers are required together:** KEDA alone would leave pods `Pending` on a 0-node group;
  Cluster Autoscaler alone would never remove idle worker pods.

Cluster Autoscaler is chosen over Karpenter to fit the existing managed node group with minimal change.

## Consequences

- Positive: near-$0 while idle within a session (0 worker pods + 0 spot nodes); scales out on demand
  and back to zero automatically; standard, well-understood EKS pattern; the pod-vs-node split maps
  cleanly onto KEDA vs Cluster Autoscaler.
- Trade-offs / risks: two moving parts to operate (KEDA + Cluster Autoscaler); a pod stays `Pending`
  if the spot NG discovery tags or KEDA/CA IRSA are misconfigured; scale-out has extra latency (KEDA
  starts a pod → CA must add a spot node before it can run).
- Scale-in safety: Cluster Autoscaler only removes a node once it is unneeded for its cool-down window,
  and a worker pod actively transcoding **blocks** removal of its node, so in-flight jobs are not cut.
- No-lost-job on an abrupt pod/node loss is guaranteed at the application layer by the SQS visibility
  timeout + the idempotency guard from ADR-0008 (verified by the 3b chaos test), independent of this
  autoscaling decision.

## References
- Design spec: `docs/superpowers/specs/2026-07-29-streamforge-phase3b-design.md`
- Implementation plan: `docs/superpowers/plans/2026-07-29-streamforge-phase3b.md`
- Runbook: `docs/runbook/phase3b.md`
- ADR-0008 (transcode pipeline) — idempotency is the basis for "no lost job".
