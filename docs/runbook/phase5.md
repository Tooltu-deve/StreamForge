# Runbook — Phase 5a: Tier gating + CloudFront signed cookies

> Provision / verify / tear down the premium access-control layer. Builds on Phase 4 (ArgoCD
> GitOps). payОС is out of scope; premium upgrade is manual.

## 1. Phase objective
Gate all HLS behind CloudFront signed cookies. playback checks the Cognito group vs the video's
`tier_required` and issues a short-lived signed cookie only to authorized users. Premium content
is never publicly fetchable.

## 2. Prerequisites
- Phase 4 stack (env/dev + platform/dev + ArgoCD + edge/dev) provisionable. See `phase4.md` §3.
- Tools: `openssl`, `jq`, AWS CLI (profile `study-user`), `aws cognito-idp`.
- New moving parts this phase adds: a CloudFront key group + a Secrets Manager secret
  `streamforge-dev/cf-signing` (created empty by Terraform, value put via CLI).

## 3. How to provision (order matters — the key ties three layers together)
```bash
# 1. Generate the signing key-pair (public is safe to commit; private is a secret).
openssl genrsa -out cf_private.pem 2048
openssl rsa -in cf_private.pem -pubout -out cf_public.pem

# 2. Put the PUBLIC key into edge/dev tfvars, then apply core + edge + platform.
#    (edit infra/edge/dev/terraform.tfvars: cf_public_key_pem = file("cf_public.pem") or paste PEM)
terraform -chdir=infra/env/dev apply       # creates the empty cf-signing secret
terraform -chdir=infra/edge/dev apply       # creates public key + key group; gates /hls/*
terraform -chdir=infra/platform/dev apply    # playback IRSA gets GetSecretValue

# 3. Put the PRIVATE key + key_pair_id into Secrets Manager as JSON (never in TF state).
KID=$(terraform -chdir=infra/edge/dev output -raw cf_public_key_id)
SEC=$(terraform -chdir=infra/env/dev output -raw cf_signing_secret_name)
aws secretsmanager put-secret-value --region ap-southeast-1 --secret-id "$SEC" \
  --secret-string "$(jq -n --arg k "$KID" --rawfile p cf_private.pem '{key_pair_id:$k, private_key:$p}')"

# 4. Seed gitops values (now includes APP_DOMAIN, CF_SIGNING_SECRET, CF_COOKIE_TTL) + push.
GITOPS_DIR=~/…/streamforge-gitops ./scripts/seed-gitops-values.sh
( cd ~/…/streamforge-gitops && git commit -am "chore: reseed (phase5)" && git push )

# 5. Deploy the new playback image via CI (merge to main → build → bump → ArgoCD sync).
```
> If the CloudFront public key is ever recreated, `key_pair_id` changes → **re-run step 3**
> (`put-secret-value`) or playback signs with a stale id and CloudFront returns 403.

## 4. How to verify (DoD)
```bash
# Upload a video with tier=premium (FE selector, or the upload API with tier_required=premium).
# As a FREE user:
curl -s -H "Authorization: Bearer $ID_TOKEN_FREE" https://app.tooltu.io.vn/api/playback/$VID -o /dev/null -w '%{http_code}\n'   # 403

# Anonymous direct HLS fetch (no cookie):
curl -s https://app.tooltu.io.vn/hls/$VID/master.m3u8 -o /dev/null -w '%{http_code}\n'   # 403

# Upgrade the user to premium, then RE-LOGIN (fresh JWT with cognito:groups=[premium]):
aws cognito-idp admin-add-user-to-group --region ap-southeast-1 \
  --user-pool-id $(terraform -chdir=infra/env/dev output -raw user_pool_id) \
  --username <user> --group-name premium

# As the now-PREMIUM user: /api/playback returns 200 + Set-Cookie: CloudFront-* ; HLS plays.
```
Checklist:
- [ ] free user + premium video → 403 (no cookie).
- [ ] anonymous HLS fetch → 403 (content not public).
- [ ] premium user + premium video → 200 + 3 CloudFront cookies → plays.
- [ ] cookie TTL elapses mid-play → 403 → FE auto-refreshes → resumes.
- [ ] free video still plays for a free user.
- [ ] `terraform destroy` clean (secret `recovery_window_in_days=0` deletes immediately).

## 5. Teardown
Standard Phase 4 order (delete ArgoCD Applications → `platform destroy` → `edge destroy` →
`env destroy`). The `cf-signing` secret deletes immediately (no recovery window). The key group /
public key are removed by `edge destroy`.

## 6. Common issues & troubleshooting
| Symptom | Root cause | Fix |
|---|---|---|
| Premium user still 403 after upgrade | JWT still has the old groups | Re-login to get a fresh ID token (groups are a claim, cached in the token) |
| All HLS 403 even for premium | `key_pair_id` in the secret ≠ the CloudFront public key id | Re-run `put-secret-value` (step 3) with the current `cf_public_key_id` |
| playback 500 reading secret | IRSA missing `GetSecretValue` or wrong secret name | Check platform IRSA + `CF_SIGNING_SECRET` env matches the secret name |
| Cookie not sent by browser | not same-origin / missing `withCredentials` | Ensure `app_domain` fronts both `/api/*` and `/hls/*`; hls.js `xhrSetup` sets `withCredentials` |
| Signature invalid (403 with cookie) | wrong base64 variant or hash | Cookie helper uses CloudFront base64 (`+/=`→`-~_`) + RSA-SHA1 |

## 7. CV milestone achieved
Real premium access control: per-video tier authorization from the Cognito group in the JWT, plus
CloudFront **signed cookies** so premium HLS is never publicly fetchable — with the signing key
held in Secrets Manager and read by playback via IRSA (never in Terraform state or the public
GitOps repo).
