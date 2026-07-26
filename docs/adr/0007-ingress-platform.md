# ADR-0007: Separate Terraform state layer for cluster add-ons (platform/dev)


- **Date:** 2026-07-22
- **Phase:** Phase 2


## Context

In order for `eks` cluster to create ALB by specifying an ingress in configuration files, a Load Balancer Controller is needed to be installed into the cluster using `helm`. But Load Balancer Controller can only be installed after the creation of the cluster in /env/dev. The problem is to decide whether to configure the code to install Load Balancer Controller in the same directory (/env/dev) or to separate it to another directory (/platform/dev)

The `helm` provider that installs the controller must be configured from the cluster's own outputs (endpoint, CA data), which only exist after the cluster is created.

## Options considered

1. **Same root (`/env/dev`)** — put the `helm` provider and the controller install alongside the AWS resources.
   - Chicken-and-egg: the provider configuration references the cluster's endpoint/CA, which do not exist on the first `apply`, so the provider cannot be resolved.
   - Every pure-AWS `plan`/`apply` afterwards would also need a live, reachable cluster (which is destroyed at rest in this ephemeral project).
   - Larger blast radius (cloud infra + in-cluster in one state) and an error-prone destroy order.

2. **Separate layer (`/platform/dev`)** — a new root holding the `helm` provider, reading the cluster's coordinates from `/env/dev` via `terraform_remote_state`.
   - The cluster always exists before this layer applies, so there is no chicken-and-egg.
   - The pure-AWS layer stays independent of a live cluster.
   - Clean, ordered destroy and a smaller blast radius.

## Decision

Chosen **Option 2** — a separate `/platform/dev` state layer. It reads `/env/dev` outputs through `terraform_remote_state`; the `helm` provider authenticates to the cluster via `aws eks get-token` (exec plugin); and the install logic lives in a reusable `modules/alb-controller` (IRSA role + `helm_release`).

## Consequences

- Positive: no chicken-and-egg; pure-AWS work never depends on a live cluster; the `helm`/cluster concerns are isolated in one state; the `alb-controller` module is reusable across environments.
- Trade-offs / risks:
  - Two states must be applied and destroyed in order — **`platform/dev` before `env/dev`** on teardown.
  - The platform layer can only `plan`/`apply` when the cluster is up, so its CI runs a reduced gate (`fmt` + `validate` + `checkov`, no `plan`).
- Follow-up: add the `hashicorp/kubernetes` provider to this layer only if `kubernetes_*` resources become needed (2b+).

## References

- Design spec: [../superpowers/specs/2026-07-21-streamforge-phase2a-design.md](../superpowers/specs/2026-07-21-streamforge-phase2a-design.md)
- Implementation: `infra/modules/alb-controller/`, `infra/platform/dev/`
- Related: [0006-eks-nodegroups-access.md](0006-eks-nodegroups-access.md) (the OIDC provider this IRSA role builds on)

