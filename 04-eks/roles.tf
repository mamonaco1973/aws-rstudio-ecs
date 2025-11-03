# ==============================================================================
# IAM Role: EKS Cluster Role
# ------------------------------------------------------------------------------
# Defines the IAM role used by the EKS control plane to manage resources.
# ==============================================================================
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role" # IAM role for EKS control plane

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow" # Allow role assumption by EKS service
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# Attach Managed Policy to EKS Cluster Role
# ------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ==============================================================================
# IAM Role: EKS Node Group Role
# ------------------------------------------------------------------------------
# Defines the IAM role used by EKS worker nodes (EC2 instances).
# ==============================================================================
resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-group-role" # IAM role for EKS worker nodes

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow" # Allow EC2 to assume this role
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# Attach Managed Policies to EKS Node Group Role
# ------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_registry_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ==============================================================================
# IAM Role: Cluster Autoscaler (IRSA)
# ------------------------------------------------------------------------------
# Creates an IAM role assumed by the Cluster Autoscaler via OIDC.
# ==============================================================================
resource "aws_iam_role" "cluster_autoscaler" {
  name = "EKSClusterAutoscalerRole" # IAM role for Cluster Autoscaler

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow" # Allow assumption via OIDC
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks_oidc_provider.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(
              aws_iam_openid_connect_provider.eks_oidc_provider.url,
              "https://",
              ""
            )}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
          }
        }
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# IAM Policy: Cluster Autoscaler Permissions
# ------------------------------------------------------------------------------
# Grants required permissions for the Cluster Autoscaler to manage node groups.
# ------------------------------------------------------------------------------
resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "EKSClusterAutoscalerPolicy"
  description = "Allows Cluster Autoscaler to manage node group scaling"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeLaunchTemplateVersions",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# Attach Policy to Cluster Autoscaler Role
# ------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "cluster_autoscaler_attach" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

# ------------------------------------------------------------------------------
# Policy: Allow Secrets Manager Read Access
# ------------------------------------------------------------------------------
resource "aws_iam_policy" "secrets_read" {
  name        = "SecretsManagerRead"
  description = "Allow EKS pods to read from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# Attach Policy to Role
# ------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "eks_secrets_read_attach" {
  role       = aws_iam_role.eks_secrets_reader.name
  policy_arn = aws_iam_policy.secrets_read.arn
}

# ==============================================================================
# IAM Role: EKS Secrets Reader (IRSA)
# ------------------------------------------------------------------------------
# Allows pods in EKS to read secrets from AWS Secrets Manager.
# ==============================================================================
resource "aws_iam_role" "eks_secrets_reader" {
  name = "EKSSecretsReaderRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks_oidc_provider.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(
              aws_iam_openid_connect_provider.eks_oidc_provider.url,
              "https://",
              ""
            )}:sub" = "system:serviceaccount:default:secrets-reader-sa"
          }
        }
      }
    ]
  })
}

# ==============================================================================
# Kubernetes Service Account: secrets-reader-sa
# ------------------------------------------------------------------------------
# Creates a Kubernetes service account in the specified namespace
# and binds it to the IAM Role (EKSSecretsReaderRole) via annotation.
# ==============================================================================
resource "kubernetes_service_account" "secrets_reader_sa" {
  provider = kubernetes.eks  # uses your configured EKS kubernetes provider

  metadata {
    name      = "secrets-reader-sa"   # Service account name
    namespace = "default"             # Adjust if needed
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.eks_secrets_reader.arn
    }
  }

  depends_on = [
    aws_iam_role.eks_secrets_reader
  ]
}
