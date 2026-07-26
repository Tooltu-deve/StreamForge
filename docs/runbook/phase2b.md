# Runbook — Phase 2b: App on the cluster, end-to-end

> A runbook is an operations handbook. A stranger (or you, 3 months from now) should be able to provision / verify / tear down by reading it.

## 1. Phase objective
Reach `https://app.<domain>` and complete the flow **login (Cognito) → upload → see the catalog record → watch (playback)**, with **CloudFront as the single public entry** (S3 frontend by default, `/api/*` → ALB, HLS later). No transcoding yet.

## 2. Prerequisites
- **Tools:** `terraform >= 1.15.0`, `kubectl`, `helm`, `aws` CLI v2, `docker`, `jq`, `node`/`npm`. Operator authenticated to the account.
- **Phase 1 + 2a applied** (core cluster + AWS Load Balancer Controller). See `phase2a.md`.
- **ACM certs issued:** us-east-1 wildcard `*.tooltu.io.vn` (for CloudFront). The ALB is HTTP-only, so no ap-southeast-1 ALB cert is needed.
- Region `ap-southeast-1`, account `252773257724`, cluster `streamforge-dev`, namespace `streamforge`.
- Operator public IP in `env/dev` `public_access_cidrs` (helm must reach the cluster API).

Shared env for the commands below:
```bash
export REGION=ap-southeast-1 ACCOUNT=252773257724
export ECR=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/streamforge-dev
export NS=streamforge
```

## 3. How to provision (Deploy) — order matters
The whole point of the layering: **core → platform → images → app(helm) → edge → frontend → DNS**. The edge layer reads the ALB, so the Ingress (which creates the ALB) must exist first.

```bash
# 1. Core (vpc, s3, eks, ecr, dynamodb, cognito)
terraform -chdir=infra/env/dev init && terraform -chdir=infra/env/dev apply
aws eks update-kubeconfig --name streamforge-dev --region $REGION
kubectl get nodes

# 2. Platform (ALB controller + per-service IRSA roles)
terraform -chdir=infra/platform/dev init && terraform -chdir=infra/platform/dev apply

# 3. Build + push service images (build machine may be arm64 -> force amd64)
aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin $ACCOUNT.dkr.ecr.$REGION.amazonaws.com
export TAG=sha-$(git rev-parse --short=12 HEAD)
for s in catalog upload playback; do
  docker build --platform linux/amd64 -f services/$s/Dockerfile -t $ECR/$s:$TAG services/
  docker push $ECR/$s:$TAG
done
# ECR repos are IMMUTABLE: to re-push the same tag, `aws ecr batch-delete-image` first,
# or commit a change so the SHA (and tag) advances. CI (build-scan-push) skips existing tags.

# 4. Deploy services + ingress (helm)
RAW=$(terraform -chdir=infra/env/dev output -json bucket_names | jq -r .raw)
TABLE=$(terraform -chdir=infra/env/dev output -raw table_name)
POOL=$(terraform -chdir=infra/env/dev output -raw user_pool_id)
CLIENT=$(terraform -chdir=infra/env/dev output -raw app_client_id)
R_CAT=$(terraform -chdir=infra/platform/dev output -json svc_role_arns | jq -r .catalog)
R_UP=$(terraform  -chdir=infra/platform/dev output -json svc_role_arns | jq -r .upload)
R_PB=$(terraform  -chdir=infra/platform/dev output -json svc_role_arns | jq -r .playback)
kubectl create namespace $NS 2>/dev/null || true

helm upgrade --install catalog charts/service -n $NS \
  --set name=catalog --set image.repo=$ECR/catalog --set image.tag=$TAG \
  --set serviceAccount.roleArn=$R_CAT \
  --set env.REGION=$REGION --set env.TABLE_NAME=$TABLE

helm upgrade --install upload charts/service -n $NS \
  --set name=upload --set image.repo=$ECR/upload --set image.tag=$TAG \
  --set serviceAccount.roleArn=$R_UP \
  --set env.REGION=$REGION --set env.RAW_BUCKET=$RAW --set env.TABLE_NAME=$TABLE \
  --set env.COGNITO_POOL_ID=$POOL --set env.COGNITO_CLIENT_ID=$CLIENT

helm upgrade --install playback charts/service -n $NS \
  --set name=playback --set image.repo=$ECR/playback --set image.tag=$TAG \
  --set serviceAccount.roleArn=$R_PB \
  --set env.REGION=$REGION --set env.RAW_BUCKET=$RAW --set env.TABLE_NAME=$TABLE \
  --set env.COGNITO_POOL_ID=$POOL --set env.COGNITO_CLIENT_ID=$CLIENT

CFPL=$(aws ec2 describe-managed-prefix-lists --region $REGION \
  --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing \
  --query 'PrefixLists[0].PrefixListId' --output text)
helm upgrade --install ingress charts/ingress -n $NS \
  --set cloudfrontPrefixListId=$CFPL \
  --set originSecret=<origin_secret>   # must match edge/dev tfvars EXACTLY

kubectl get ingress streamforge -n $NS -w   # wait for ADDRESS (ALB) to appear
kubectl get pods -n $NS                      # all 3 Running/Ready

# 5. Edge (CloudFront) — needs the ALB (step 4) + the us-east-1 cert
terraform -chdir=infra/edge/dev init && terraform -chdir=infra/edge/dev apply
export CF=$(terraform -chdir=infra/edge/dev output -raw cloudfront_domain)

# 6. Frontend build -> S3 -> invalidate
cd frontend && npm ci && npm run build   # .env holds VITE_COGNITO_POOL_ID / _CLIENT_ID
aws s3 sync dist/ s3://streamforge-dev-frontend --delete
DIST=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Items[0]=='app.tooltu.io.vn'].Id" --output text)
aws cloudfront create-invalidation --distribution-id $DIST --paths "/*"
cd ..

# 7. DNS (cross-account) — in the account that owns the tooltu.io.vn zone
aws route53 change-resource-record-sets --hosted-zone-id <ZONE_ID> \
  --change-batch '{"Changes":[{"Action":"UPSERT","ResourceRecordSet":{
    "Name":"app.tooltu.io.vn","Type":"CNAME","TTL":300,
    "ResourceRecords":[{"Value":"'"$CF"'"}]}}]}'
```

## 4. How to verify (smoke e2e — the DoD)
Create a test user once:
```bash
aws cognito-idp admin-create-user --user-pool-id $POOL --username you@mail.com --message-action SUPPRESS
aws cognito-idp admin-set-user-password --user-pool-id $POOL --username you@mail.com --password 'Test1234!' --permanent
aws cognito-idp admin-add-user-to-group --user-pool-id $POOL --username you@mail.com --group-name free
```
Then in the browser at `https://app.tooltu.io.vn`: **log in → upload a file → it appears in the list (catalog) → click watch (playback returns a presigned URL).**

Checklist:
- [ ] HTTPS via the custom domain (padlock; CloudFront cert).
- [ ] `/api/*` returns 200 (not 502) — ALB targets healthy.
- [ ] Upload succeeds (presigned PUT to `...s3.ap-southeast-1.amazonaws.com`, no CORS error).
- [ ] DynamoDB record visible via catalog; playback URL resolves.
- [ ] `terraform plan` zero-diff on core / platform / edge.

## 5. How to tear down (Teardown) — reverse order
```bash
# 1. DNS record (parent account) — remove app.tooltu.io.vn
# 2. Edge FIRST, while the ALB still exists (edge reads data.aws_lb.api)
terraform -chdir=infra/edge/dev destroy
# 3. App + ingress (this deletes the ALB)
helm uninstall ingress catalog upload playback -n $NS
# 4. Platform, then core
terraform -chdir=infra/platform/dev destroy
terraform -chdir=infra/env/dev destroy
# 5. Orphan checks: NAT GW, EIP, LB, EBS, ENI, ECR images, frontend bucket objects
```
> ⚠️ Destroy **edge before** deleting the ALB. If the ALB is gone first, `data.aws_lb.api` in edge errors "empty result" and blocks the destroy. This ordering is exactly why CloudFront lives in its own layer (see §7).

## 6. Common issues & troubleshooting
| Symptom | Root cause | Fix |
|---|---|---|
| All `/api/*` return **502**, ALB targets unhealthy | ALB health check defaults to `/`; services only serve `/healthz`,`/readyz`,`/api/*` → 404 → unhealthy | Ingress annotations `healthcheck-path: /healthz` + `success-codes: "200"` (already in `charts/ingress`) |
| **502** from CloudFront even with healthy targets | HTTPS origin: ALB cert `*.tooltu.io.vn` ≠ origin hostname `*.elb.amazonaws.com` → TLS mismatch | CloudFront origin `origin_protocol_policy=http-only` + Ingress `listen-ports [{"HTTP":80}]` (already applied). ALB stays locked by prefix list + `X-Origin-Secret` |
| Upload fails with **"No 'Access-Control-Allow-Origin'"** | boto3 default `addressing_style=auto` rewrites the presigned URL to the global `s3.amazonaws.com` + SigV2 → 301 redirect drops CORS headers | `sf_base.aws.s3()` pins `Config(signature_version="s3v4", s3={"addressing_style":"virtual"})` → regional endpoint. Also ensure the raw-bucket CORS config is applied |
| `403 Forbidden` through CloudFront | `originSecret` in the ingress helm value ≠ `origin_secret` in edge/dev tfvars | Make them identical |
| `docker push` fails: tag exists | ECR repo IMMUTABLE | `aws ecr batch-delete-image` the tag, or advance the git SHA |
| `edge apply` errors "empty result" for `data.aws_lb.api` | Ingress/ALB not created yet | Deploy the ingress (step 4) before edge |
| Frontend blank page | Vite bakes env at build time; `global` undefined for amazon-cognito-identity-js | `vite.config.js` `define: { global: "globalThis" }`; rebuild + re-sync + invalidate after any change |

## 7. CV milestone achieved
A four-layer, fully-IaC deployment (`core → platform → edge` + Helm app) puts a real app behind CloudFront on EKS: login, upload to S3 via presigned URLs, and playback — reachable over HTTPS on a custom domain, with the ALB locked to CloudFront and clean, ordered apply/destroy.
