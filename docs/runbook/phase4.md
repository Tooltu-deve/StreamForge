# Runbook — Phase 4: GitOps (ArgoCD) + Progressive Delivery

> A runbook is an operations handbook. A stranger (or you, 3 months from now) should be able to
> provision / verify / tear down by reading it. This covers **slice 4a (GitOps foundation)**;
> slice 4b (Argo Rollouts canary) is appended when that slice lands.

## 1. Phase objective (4a)
Replace push-based deploy with **GitOps**: ArgoCD (installed by Terraform) watches the public
config repo `Tooltu-deve/StreamForge-Gitops` and, through an **app-of-apps**, syncs every
workload onto EKS. CI stops running `helm upgrade` and instead **bumps the image tag** in the
config repo; ArgoCD auto-syncs. Drift is auto-reverted (`selfHeal`).

## 2. Prerequisites
- Phase 2/3 core + platform working (`env/dev`, `platform/dev`). See `phase3b.md`.
- Two repos checked out **side by side**:
  ```
  …/Projects/Project_StreamForge     # app + terraform + CI
  …/Projects/streamforge-gitops      # public config repo (GitHub: StreamForge-Gitops)
  ```
- Tools: `helm`, `kubeconform` (`brew install kubeconform`), `yq` (mikefarah, `brew install yq`), `jq`.
- **`GITOPS_PAT` GitHub Actions secret** (only needed before the CI-bump smoke, §4 step 4):
  1. GitHub → Settings → Developer settings → **Fine-grained tokens** → Generate.
  2. Repository access: **only** `Tooltu-deve/StreamForge-Gitops`. Permissions: **Contents: Read and write**.
  3. In the **app repo** → Settings → Secrets and variables → Actions → New secret `GITOPS_PAT` = the token.
- **Verify the ArgoCD chart version before apply** (default in `platform/dev/variables.tf` may be stale):
  ```bash
  helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
  helm search repo argo/argo-cd --versions | head
  ```
  Set `argocd_chart_version` to a published version if the default is not found. Record the installed version here: `argo-cd chart = <fill in after apply>`.

## 3. How to provision (Deploy) — order matters
```bash
# 1. Core + platform. platform/dev now also installs ArgoCD + the root app-of-apps.
terraform -chdir=infra/env/dev apply
terraform -chdir=infra/platform/dev apply
kubectl -n argocd rollout status deploy/argocd-server --timeout=180s
kubectl -n argocd get applications          # streamforge-root appears (children follow)

# 2. Seed the config-repo values from live Terraform outputs (ephemeral infra → dynamic IDs).
GITOPS_DIR=~/Documents/Workspace/Self-study/AWS/Projects/streamforge-gitops \
  ./scripts/seed-gitops-values.sh
( cd ~/Documents/Workspace/Self-study/AWS/Projects/streamforge-gitops \
    && git commit -am "chore: seed values from terraform outputs" && git push )

# 3. ArgoCD detects the pushed values and syncs everything.
kubectl -n argocd get applications          # all Synced / Healthy
kubectl -n streamforge get deploy,svc        # catalog/upload/playback/worker present (NOT ingress)

# 4. Ingress is NOT in GitOps (carries the edge secret) — deploy it out-of-band, as in Phase 2b.
CFPL=$(terraform -chdir=infra/edge/dev output -raw cloudfront_prefix_list_id)   # or the managed CF prefix list
helm upgrade --install ingress charts/ingress -n streamforge \
  --set cloudfrontPrefixListId=$CFPL \
  --set originSecret=<origin_secret>   # must match edge/dev tfvars EXACTLY (do not commit this)
```
> **First provision only:** if you have not pushed any real image yet, `image.tag` is `dev` and
> pods `ImagePullBackOff` until CI pushes a `sha-<12>` image and bumps the tag (§4 step 4). To
> bootstrap manually, set a known existing tag in `values/<svc>.yaml` and push.

> **Re-seed on every recreate.** Role ARNs and `user_pool_id` change each `apply`. Re-run the
> seed script + push after any fresh provision, or the pods get stale IRSA/Cognito config.

Access the ArgoCD UI (port-forward, no ingress — $0):
```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443   # https://localhost:8080
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo  # admin password
```

## 4. How to verify (DoD 4a)
Checklist:
- [ ] `terraform apply` (platform) brings up ArgoCD + `streamforge-root`; the four children (catalog/upload/playback/transcode-worker) reach `Synced / Healthy`.
- [ ] Git → cluster: bump `values/<svc>.yaml` tag → ArgoCD syncs the new image (no `helm`/`kubectl` by hand).
- [ ] `selfHeal`: a manual drift edit is reverted.
- [ ] CI no longer deploys directly (only builds/scans/pushes + bumps the tag).
- [ ] `terraform destroy` is clean (no leftover LB/EBS/ENI, no orphan `argoproj` CRDs).

**Step: auto-sync + selfHeal**
```bash
kubectl -n streamforge scale deploy/catalog --replicas=5   # introduce drift
sleep 20
kubectl -n streamforge get deploy/catalog                  # back to the Git-declared replicas
```

**Step: CI bump → auto-sync** — push a trivial change under `services/catalog/` to `main`; the
`bump-gitops` job commits `sha-<12>` into `values/catalog.yaml`; then:
```bash
kubectl -n streamforge get deploy/catalog -o jsonpath='{..image}'; echo   # tag == new sha-<12>
```

## 5. Teardown (finalizer-safe order)
```bash
# 1. Delete the Applications FIRST so ArgoCD finalizers cascade-remove workloads cleanly.
kubectl -n argocd delete application --all --wait=true
# 2. Then destroy platform (removes ArgoCD + its CRDs because crds.keep=false) and core.
terraform -chdir=infra/platform/dev destroy
terraform -chdir=infra/env/dev destroy
# 3. Orphan check.
kubectl get crd 2>/dev/null | grep argoproj || echo "argo CRDs gone"
# confirm no leftover LB / EBS / ENI / EIP in the console
```
> The config repo `StreamForge-Gitops` is a Git repo — it persists across apply/destroy and costs
> nothing. Only `image.tag` in it is CI-owned; everything else is re-seeded next provision.

## 6. Common issues & troubleshooting
| Symptom | Root cause | Fix |
|---|---|---|
| `terraform plan` fails: CRD not found for `Application` | root app created via `kubernetes_manifest` on a fresh cluster | Root app must come from the local Helm chart `helm_release` ordered after ArgoCD (as built) — not `kubernetes_manifest` |
| Child app `ComparisonError: values file … not found` | wrong relative `valueFiles` path | Path is relative to `source.path` (chart dir): `../../values/<svc>.yaml` from `charts/service` |
| App `OutOfSync` forever / repo not found | `repoURL` casing mismatch across manifests | All `repoURL` must be byte-identical to the real repo (`StreamForge-Gitops`) |
| Pods `ImagePullBackOff`, tag `dev` | no image pushed / tag not bumped yet | Push via CI so `bump-gitops` sets a real `sha-<12>`, or set an existing tag manually once |
| `bump-gitops` push rejected `non-fast-forward` | matrix services pushing concurrently | `concurrency: gitops-bump` serializes them (as built); re-run if it still races |
| Namespace `argocd` stuck `Terminating` on destroy | Applications deleted after ArgoCD, finalizer orphaned | Delete `application --all` **before** `platform destroy`; if stuck, `kubectl patch app <n> -p '{"metadata":{"finalizers":null}}' --type=merge` |
| Pods have stale Cognito/IRSA after recreate | values not re-seeded | Re-run `seed-gitops-values.sh` + push |

## 7. CV milestone achieved (4a)
Push-based deploy replaced by **GitOps**: ArgoCD reconciles the whole app from a public config
repo via app-of-apps, with automated prune + self-heal; CI is reduced to build/scan/push + a
cross-repo image-tag bump and never touches the cluster. Declarative, auditable, drift-correcting
delivery on an ephemeral, $0-idle cluster.
