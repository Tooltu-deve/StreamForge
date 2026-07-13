# <Type>: <short summary>  (e.g. `feat: module vpc`)

## Phase / Issue
- Phase: Phase N
- Closes #<issue>

## What changed
- ...

## Checklist (Definition of Done)
- [ ] Green CI (fmt/validate/tflint/checkov; image scan if applicable)
- [ ] `terraform plan` shows no unexpected diff / plan attached
- [ ] `terraform apply` builds from scratch **and** `terraform destroy` cleans up (no leftover NAT GW/EIP/LB/EBS)
- [ ] ADR added if this is a technical decision (`docs/adr/`)
- [ ] Phase runbook updated (`docs/runbook/`)
- [ ] No secrets committed (check `.tfvars`, keys, tokens)
- [ ] Evidence saved (`docs/evidence/`) if this is a demo milestone

## How to test / verify
```bash
# commands a reviewer runs to verify for themselves
```

## Notes / risks
- ...
