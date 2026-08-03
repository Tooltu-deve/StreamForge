resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_version
  namespace        = "argocd"
  create_namespace = true

  set = [
    { name = "crds.keep", value = "false" }
  ]
}

resource "helm_release" "root_app" {
  name      = "streamforge-root"
  chart     = "${path.module}/root-app"
  namespace = "argocd"

  set = [
    { name = "repoURL", value = var.gitops_repo_url },
    { name = "revision", value = var.gitops_revision },
  ]

  depends_on = [helm_release.argocd]
}
