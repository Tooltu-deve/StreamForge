# ADR-0004: Regional NAT Gateway


- **Date:** 2026-07-17
- **Phase:** Phase 1


## Context
Private-subnet resources (EKS nodes) need outbound internet without exposing their IPs. Constraints: cost (ephemeral, no orphaned billable resources like a dangling EIP), HA across ≥2 AZs, clean Terraform teardown.

## Options considered
1. **Option A** — Multi-NAT (one zonal NAT + EIP per AZ): HA, but N NATs + N EIPs = most expensive, most to clean up.
2. **Option B** — Regional NAT (`availability_mode = "regional"`, auto mode): one AWS-managed resource, HA across AZs by default, no EIP to manage, no public subnet needed. Requires provider ≥ 6.24.0; public-only.
3. **Option C** — Single zonal NAT in one AZ: cheapest raw, but SPOF + cross-AZ data charges + an EIP to manage.

## Decision
I chose **Option B**. It gives AZ-level HA out of the box while being cheaper/simpler than A for the same availability, and avoids the SPOF and cross-AZ charges of C. As an AWS-managed resource it removes `aws_eip` from the stack — one fewer thing to leak on `destroy`. Verified before adopting: `availability_mode` landed in provider v6.24.0; we pin v6.54.0. In auto mode `subnet_id`/`allocation_id`/`aws_eip` are forbidden and `connectivity_type` must be `public` — matches our need.

## Consequences
- Positive: HA egress with zonal affinity; fewer resources → cheaper + cleaner `destroy`; simpler code (one NAT, private RTs point at one ID).
- Trade-offs / risks: depends on provider ≥ 6.24.0 (mitigated by pin); public-only (fine); confirm regional NAT is offered in `ap-southeast-1` before first `apply` — fallback is Option C.
- Follow-up: `depends_on = [aws_internet_gateway.main]`; added VPC endpoints (S3 gateway + ECR/logs interface) to keep pulls/logs off NAT.

## References
- Architecture §3: [../diagrams/architecture.md](../diagrams/architecture.md)

- Implementation: `infra/modules/vpc/main.tf`
