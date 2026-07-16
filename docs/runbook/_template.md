# Runbook — Phase N: <Phase name>

> A runbook is an operations handbook. A stranger (or you, 3 months from now) should be able to provision / verify / tear down by reading it.

## 1. Phase objective
One sentence: what new capability this phase adds to the system.

## 2. Prerequisites
- Tools: terraform vX, kubectl, helm, aws-cli (already `aws sso login` / profile configured).
- The previous phase is complete (outputs/variables it produces are available).
- Environment variables / secrets required.

## 3. How to provision (Deploy)
```bash
# Commands in exact order
cd infra/env/dev
terraform init
terraform plan
terraform apply
# ... app/helm/argocd steps if any
```

## 4. How to verify
- [ ] Verification command / endpoint + expected result.
- [ ] Specific smoke test.
- Save evidence to `docs/evidence/gd-N-*`.

## 5. How to tear down (Teardown) — important to keep cost ~$0
```bash
terraform destroy
# Check for leftovers: NAT GW, EIP, LB, EBS, ECR images, S3 objects
aws ce ...   # or check Cost Explorer
```

## 6. Common issues & troubleshooting
| Symptom | Possible cause | Fix |
|---|---|---|
| ... | ... | ... |

## 7. CV milestone achieved
A 1-2 line story you can tell in your CV / interview after this phase.
