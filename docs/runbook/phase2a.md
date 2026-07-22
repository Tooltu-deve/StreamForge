# Runbook — Phase 2a: Ingress Platform (ALB Controller)

> A runbook is an operations handbook. A stranger (or you, 3 months from now) should be able to provision / verify / tear down by reading it.

## 1. Phase objective
Install the AWS Load Balancer Controller into the EKS cluster (via a separate `platform/dev` Terraform state layer) so Phase 2b can turn a Kubernetes `Ingress` into an ALB.

## 2. Prerequisites
- **Tools:** `terraform >= 1.15.0`, `kubectl`, `helm`, `aws` CLI v2. Operator authenticated with credentials able to create IAM + reach the cluster.
- **Phase 1 applied and the cluster is up** — `platform/dev` reads its outputs (`cluster_name`, `cluster_endpoint`, `cluster_ca_data`, `oidc_provider_arn`, `oidc_provider_url`, `vpc_id`) via `terraform_remote_state`.
- Operator public IP is in `env/dev` `public_access_cidrs` (the `helm` provider must reach the cluster API).
- Region `ap-southeast-1`, cluster `streamforge-dev`.

## 3. How to provision (Deploy) — order matters
```bash
# 1. Core first: the cluster must exist before the platform layer can apply.
terraform -chdir=infra/env/dev init -reconfigure
terraform -chdir=infra/env/dev apply
aws eks update-kubeconfig --name streamforge-dev --region ap-southeast-1
kubectl get nodes                       # expect 2 on-demand nodes Ready

# 2. (optional) confirm the chart version is published before apply
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm search repo eks/aws-load-balancer-controller --versions | head   # expect 3.4.2 present

# 3. Platform layer: installs the controller (IRSA role + Helm release).
terraform -chdir=infra/platform/dev init
terraform -chdir=infra/platform/dev apply
```

## 4. How to verify
```bash
# Controller deployment is Available
kubectl get deploy -n kube-system aws-load-balancer-controller
#   expect READY 2/2 (or 1/1)

# Controller logs show it started and can reach AWS — NO permission errors
kubectl logs -n kube-system deploy/aws-load-balancer-controller --tail=30
#   must NOT contain "AccessDenied" / "is not authorized" (would mean a broken IRSA trust/policy)

# No drift on either layer
terraform -chdir=infra/env/dev plan          # No changes.
terraform -chdir=infra/platform/dev plan      # No changes.
```
Checklist:
- [ ] Controller deployment Available.
- [ ] Logs clean (no AccessDenied).
- [ ] Both layers zero-diff.

## 5. How to tear down (Teardown) — platform BEFORE core
```bash
# 1. Destroy the platform layer first (removes the Helm release + IRSA role).
terraform -chdir=infra/platform/dev destroy
terraform -chdir=infra/platform/dev state list     # expect empty

# 2. Then the core layer.
terraform -chdir=infra/env/dev destroy
terraform -chdir=infra/env/dev state list          # expect empty

# 3. Orphan checks (reuse Phase 1 / gd-1 §5): NAT GW, EIP, LB, EBS, ENI.
```
> ⚠️ Destroying `env/dev` before `platform/dev` can strand the Helm release / an ALB and block the VPC delete. Always platform → core.

## 6. Deferred to Phase 2b
- The public DNS record **`subdomain → CloudFront`** is added manually in the parent account's Route53 zone (cross-account) via the console once CloudFront exists.
- Referencing the pre-existing ACM certs (both regions) as CloudFront/ALB inputs.

## 7. Common issues & troubleshooting
| Symptom | Possible cause | Fix |
|---|---|---|
| `platform/dev apply` fails to connect to cluster | Cluster down, or operator IP not in `public_access_cidrs` | Ensure `env/dev` applied + cluster up; add current IP to `public_access_cidrs`, re-apply core |
| `terraform_remote_state` outputs empty / missing key | `env/dev` not applied, or outputs not exported | Apply `env/dev`; confirm Task 1 outputs (`cluster_ca_data`, `oidc_provider_url`, `vpc_id`) exist |
| Controller pod logs `AccessDenied` | IRSA trust/policy wrong (SA subject or OIDC url mismatch) | Verify the IRSA `sub = system:serviceaccount:kube-system:aws-load-balancer-controller` + `iam_policy.json` attached |
| `helm_release` fails: chart version not found | `lbc_chart_version` not published on the repo | `helm search repo eks/aws-load-balancer-controller --versions`; set a published version |
| Auth token error mid long apply | exec token expired | Re-run apply; the exec plugin re-fetches a token |

## 8. CV milestone achieved
Layered Terraform: a pure-AWS core state and a separate cluster-add-on state that installs the AWS Load Balancer Controller via IRSA + Helm — the cluster can now provision ALBs from Kubernetes Ingress, with clean apply/destroy ordering and a security-gated CI.
