# Runbook — Phase 1: Core Infrastructure

> A runbook is an operations handbook. A stranger (or you, 3 months from now) should be able to provision / verify / tear down by reading it.

## 1. Phase objective
A single `terraform apply` from `infra/env/dev/` builds the whole StreamForge foundation from scratch — VPC, EKS (2 node groups), S3, DynamoDB, Cognito, ECR — and a single `terraform destroy` tears it down with zero leftover cost-incurring resources.

## 2. Prerequisites
- **Tools:** `terraform >= 1.15.0`, `kubectl`, `aws` CLI v2. Operator authenticated (`aws sso login` / profile) with credentials able to create EKS/IAM/VPC.
- **Phase 0 complete:** S3 remote-state backend live (`tooltu-streamforge-state`), GitHub OIDC + CI role exist.
- **`terraform.tfvars` filled with real values** (not placeholders) — see step 3.0.
- Region: `ap-southeast-1`. Cluster name: `streamforge-dev`.

## 3. How to provision (Deploy)

### 3.0 Pre-flight (do once, before the first apply)
```bash
# a) Confirm the pinned EKS version is GA in this region (ADR-0006 D2).
#    If 1.36 is NOT listed, lower var.cluster_version to the newest available.
aws eks describe-cluster-versions --region ap-southeast-1 \
  --query 'clusterVersions[].clusterVersion' --output table

# b) Fill infra/env/dev/terraform.tfvars with real values:
#    - public_access_cidrs  : your public IP /32
#    - cluster_admin_principal_arns : CI role ARN + your operator ARN
#    Get your public IP:
dig +short myip.opendns.com @resolver1.opendns.com
#    Get your caller ARN (operator):
aws sts get-caller-identity --query Arn --output text
```

### 3.1 Apply
```bash
cd infra/env/dev

terraform init                 # initialises the S3 backend (remote state + native lock)
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan     # review the plan
terraform apply tfplan         # ~15 min: EKS control plane is the slow part
```
`terraform output` prints the values Phase 2 will consume (cluster endpoint/CA, bucket names, table name, pool/client IDs, ECR URLs).

## 4. How to verify

```bash
# 1. Point kubectl at the new cluster
aws eks update-kubeconfig --name streamforge-dev --region ap-southeast-1

# 2. SMOKE: nodes joined and Ready?
kubectl get nodes
#    Expected: 2 nodes (on-demand) STATUS=Ready; spot group shows 0 nodes (desired=0)

# 3. SMOKE: system add-ons Running?
kubectl get pods -n kube-system
#    Expected Running: coredns, aws-node (vpc-cni), kube-proxy, ebs-csi-*

# 4. No drift: plan after apply is clean
terraform plan
#    Expected: "No changes. Your infrastructure matches the configuration."
```

Checklist:
- [ ] `kubectl get nodes` → 2 on-demand Ready, spot 0.
- [ ] `kubectl get pods -n kube-system` → all add-ons Running.
- [ ] `terraform plan` → zero diff.
- [ ] Save evidence (screenshots/logs of the above) to `docs/evidence/gd-1-*`.

## 5. How to tear down (Teardown) — keep cost ~$0
```bash
cd infra/env/dev
terraform destroy

# Confirm nothing survives:
terraform state list            # expected: empty

# Cross-check the usual cost-incurring leftovers in ap-southeast-1:
aws ec2 describe-nat-gateways --filter Name=state,Values=available --region ap-southeast-1
aws ec2 describe-addresses --region ap-southeast-1                 # unattached EIPs
aws elbv2 describe-load-balancers --region ap-southeast-1          # orphan LBs (from CNI/LB controller)
aws ec2 describe-volumes --filters Name=status,Values=available --region ap-southeast-1  # orphan EBS
```
If any orphan LB/ENI blocks the VPC delete, remove it, then re-run `terraform destroy`.

## 6. Common issues & troubleshooting
| Symptom | Possible cause | Fix |
|---|---|---|
| `terraform apply` fails: EKS version not available | 1.36 not GA in `ap-southeast-1` | Set `cluster_version` to newest from step 3.0a |
| Nodes stuck `NotReady` | Node IAM role missing a policy, or CNI can't assign IPs | Verify the 3 node-role policy attachments; check private-subnet free IPs |
| `kubectl` → `Unauthorized` / `You must be logged in` | Your ARN not in `cluster_admin_principal_arns`, or wrong caller | Add ARN to tfvars + re-apply; confirm `aws sts get-caller-identity` |
| `kubectl` connection timeout | Your IP not in `public_access_cidrs` (changed/rotated) | Update `public_access_cidrs` to current IP + re-apply |
| `destroy` hangs on VPC/subnet delete | Orphan ENI/LB left by the LB controller or CNI | Delete the LB/ENI manually, re-run destroy (see §5) |
| State lock error | A previous run left a `.tflock` in the bucket | Ensure no other apply is running, then `terraform force-unlock <ID>` |

## 7. CV milestone achieved
A single `terraform apply` provisions a complete, connectable EKS platform (VPC, cluster, on-demand + spot node groups via modern Access Entries, IRSA-enabled OIDC, S3/DynamoDB/Cognito/ECR), and `terraform destroy` returns the account to ~$0 — 100% custom Terraform modules, checkov hard-gated, verified by a repeatable smoke test.
