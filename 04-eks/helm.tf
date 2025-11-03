# ==============================================================================
# Helm Provider referencing Kubernetes configuration
# ------------------------------------------------------------------------------
# Configures the Helm provider to interact with the EKS cluster using data
# from the Kubernetes API endpoint, CA certificate, and authentication token.
# ==============================================================================
provider "helm" {
  kubernetes = {
    host = aws_eks_cluster.rstudio_eks.endpoint
    cluster_ca_certificate = base64decode(
      aws_eks_cluster.rstudio_eks.certificate_authority[0].data
    )
    token = data.aws_eks_cluster_auth.rstudio_eks.token
  }
}

# ==============================================================================
# AWS EKS Cluster Authentication
# ------------------------------------------------------------------------------
# Retrieves a temporary authentication token from AWS to allow Terraform to
# interact securely with the EKS cluster using IAM permissions.
# ==============================================================================
data "aws_eks_cluster_auth" "rstudio_eks" {
  name = aws_eks_cluster.rstudio_eks.name
}

# ==============================================================================
# AWS Load Balancer Controller (Helm)
# ------------------------------------------------------------------------------
# Deploys the AWS Load Balancer Controller Helm chart, which manages ALB/NLB
# resources based on Kubernetes Ingress and Service definitions.
# ==============================================================================
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"     # Helm release name
  repository = "https://aws.github.io/eks-charts" # Official AWS chart repo
  chart      = "aws-load-balancer-controller"     # Chart to deploy
  namespace  = "kube-system"                      # Standard namespace for controllers

  values = [
    templatefile("${path.module}/yaml/aws-load-balancer.yaml.tmpl", {
      cluster_name = aws_eks_cluster.rstudio_eks.name # Pass cluster name
      role_arn     = module.load_balancer_controller_irsa.iam_role_arn
    })
  ]

  # Custom values template injects cluster name and IAM role into Helm config

  depends_on = [ aws_eks_node_group.rstudio_nodes ]
}

# ==============================================================================
# Cluster Autoscaler (Helm)
# ------------------------------------------------------------------------------
# Deploys the Kubernetes Cluster Autoscaler Helm chart to monitor resource
# usage and automatically scale node groups in the EKS cluster.
# ==============================================================================
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"                      # Helm release name
  repository = "https://kubernetes.github.io/autoscaler" # Chart repo
  chart      = "cluster-autoscaler"                      # Chart name
  namespace  = "kube-system"                             # Deploy to kube-system namespace
  version    = "9.29.1"                                  # Specific version for reproducibility

  values = [
    templatefile("${path.module}/yaml/autoscaler.yaml.tmpl", {
      cluster_name = aws_eks_cluster.rstudio_eks.name
    })
  ]

  depends_on = [
    kubernetes_service_account.cluster_autoscaler,
    aws_eks_node_group.rstudio_nodes
  ]
}

# ==============================================================================
# NGINX Ingress Controller (Helm)
# ------------------------------------------------------------------------------
# Deploys the NGINX Ingress Controller to manage HTTP/HTTPS routing for
# Kubernetes services exposed externally.
# ==============================================================================
# resource "helm_release" "nginx_ingress" {
#   depends_on = [helm_release.aws_load_balancer_controller]

#   name             = "nginx-ingress"                              # Helm release name
#   namespace        = "ingress-nginx"                              # Isolated namespace for ingress
#   repository       = "https://kubernetes.github.io/ingress-nginx" # Chart repo
#   chart            = "ingress-nginx"                              # Chart name
#   create_namespace = true                                         # Create namespace if missing

#   values = [
#     file("${path.module}/yaml/nginx-values.yaml")
#   ]
# }

