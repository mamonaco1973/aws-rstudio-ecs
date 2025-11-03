# ==============================================================================
# AWS EKS Cluster Configuration
# ------------------------------------------------------------------------------
# Provisions an Amazon EKS cluster, worker node group, OIDC provider, and
# Kubernetes service account for autoscaling.
# ==============================================================================

# ------------------------------------------------------------------------------
# Create an Amazon EKS Cluster
# ------------------------------------------------------------------------------
# Defines the EKS control plane with a specific IAM role and subnet placement.
# ------------------------------------------------------------------------------
resource "aws_eks_cluster" "rstudio_eks" {
  name     = "rstudio-cluster"             # Name of the EKS cluster
  role_arn = aws_iam_role.eks_cluster_role.arn # IAM role for EKS management

  vpc_config {
    subnet_ids = [
      data.aws_subnet.k8s-subnet-1.id,
      data.aws_subnet.k8s-subnet-2.id
    ] # Subnets for EKS control plane
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ] # Ensure IAM policy before creation
}

# ------------------------------------------------------------------------------
# Launch Template for EKS Worker Nodes
# ------------------------------------------------------------------------------
# Defines instance metadata options and tagging for worker nodes.
# ------------------------------------------------------------------------------
resource "aws_launch_template" "eks_worker_nodes" {
  name = "eks-worker-nodes" # Name of the launch template

  metadata_options {
    http_endpoint = "enabled"  # Enable IMDS access
    http_tokens   = "optional" # Allow IMDSv2 but not enforced
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "eks-worker-node-rstudio"
    }
  }
}

# ------------------------------------------------------------------------------
# EKS Node Group
# ------------------------------------------------------------------------------
# Provisions worker nodes for the EKS cluster using the launch template and
# IAM role configuration.
# ------------------------------------------------------------------------------
resource "aws_eks_node_group" "rstudio_nodes" {
  cluster_name    = aws_eks_cluster.rstudio_eks.name # Link to cluster
  node_group_name = "rstudio-nodes"                  # Node group name
  node_role_arn   = aws_iam_role.eks_node_role.arn   # IAM role for nodes
  subnet_ids = [
    data.aws_subnet.k8s-private-subnet-1.id,
    data.aws_subnet.k8s-private-subnet-2.id
  ] # Deploy in private subnets

  instance_types = ["t3.medium"] # Instance type for worker nodes

  launch_template {
    id      = aws_launch_template.eks_worker_nodes.id
    version = aws_launch_template.eks_worker_nodes.latest_version
  }

  scaling_config {
    desired_size = 2 # Desired number of worker nodes
    max_size     = 4 # Maximum scaling size
    min_size     = 2 # Minimum number of nodes
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_registry_policy,
    aws_iam_role_policy_attachment.ssm_policy
  ] # Ensure IAM policies exist

  tags = {
    "k8s.io/cluster-autoscaler/enabled"     = "true"
    "k8s.io/cluster-autoscaler/rstudio-eks" = "owned"
  }

  labels = {
    nodegroup = "rstudio-nodes"
  }
}

# ------------------------------------------------------------------------------
# Retrieve TLS Certificate for EKS OIDC Provider
# ------------------------------------------------------------------------------
# Fetches the OIDC provider’s certificate for secure role assumption.
# ------------------------------------------------------------------------------
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.rstudio_eks.identity[0].oidc[0].issuer
}

# ------------------------------------------------------------------------------
# Create an OIDC Identity Provider for EKS
# ------------------------------------------------------------------------------
# Enables Kubernetes service accounts to assume IAM roles via OIDC.
# ------------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url = aws_eks_cluster.rstudio_eks.identity[0].oidc[0].issuer

  client_id_list = [
    "sts.amazonaws.com"
  ] # Allow STS to assume IAM roles

  thumbprint_list = [
    data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint
  ]
}

# ------------------------------------------------------------------------------
# Kubernetes Provider Configuration
# ------------------------------------------------------------------------------
# Configures the Kubernetes provider to connect to the EKS API server.
# ------------------------------------------------------------------------------
provider "kubernetes" {
  alias = "eks"
  host  = aws_eks_cluster.rstudio_eks.endpoint
  cluster_ca_certificate = base64decode(
    aws_eks_cluster.rstudio_eks.certificate_authority[0].data
  )
  token = data.aws_eks_cluster_auth.rstudio_eks.token
}

# ------------------------------------------------------------------------------
# Kubernetes Service Account for Cluster Autoscaler
# ------------------------------------------------------------------------------
# Creates a service account bound to an IAM role for scaling operations.
# ------------------------------------------------------------------------------
resource "kubernetes_service_account" "cluster_autoscaler" {
  provider = kubernetes.eks

  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler.arn
    }
  }

  depends_on = [aws_eks_cluster.rstudio_eks]
}
