# ==============================================================================
# AWS EFS CSI Driver (Helm + IRSA Integration)
# ------------------------------------------------------------------------------
# Installs the AWS EFS CSI driver with proper IAM permissions (IRSA) and
# StorageClass for dynamic provisioning.
# ==============================================================================

# ------------------------------------------------------------------------------ 
# IAM Policy for Amazon EFS CSI Driver
# ------------------------------------------------------------------------------
resource "aws_iam_policy" "efs_csi_driver_policy" {
  name        = "AmazonEFSCSIDriverPolicyRSTUDIO"
  description = "IAM policy granting permissions to the EFS CSI driver"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
          "elasticfilesystem:DescribeMountTargetSecurityGroups",
          "elasticfilesystem:CreateAccessPoint",
          "elasticfilesystem:DeleteAccessPoint",
          "elasticfilesystem:TagResource",
          "elasticfilesystem:DescribeTags"
        ],
        Resource = "*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------ 
# IAM Role for EFS CSI Driver (IRSA)
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "efs_csi_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks_oidc_provider.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks_oidc_provider.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:efs-csi-controller-sa"]
    }
  }
}

resource "aws_iam_role" "efs_csi_driver_role" {
  name               = "AmazonEFSCSIDriverRoleRSTUDIO"
  assume_role_policy = data.aws_iam_policy_document.efs_csi_assume_role.json
  description        = "IAM role for AWS EFS CSI driver (IRSA integration)"

  depends_on = [
    aws_eks_cluster.rstudio_eks,
    aws_iam_openid_connect_provider.eks_oidc_provider
  ]
}

resource "aws_iam_role_policy_attachment" "efs_csi_policy_attach" {
  role       = aws_iam_role.efs_csi_driver_role.name
  policy_arn = aws_iam_policy.efs_csi_driver_policy.arn
}

# ------------------------------------------------------------------------------ 
# Kubernetes Service Account for EFS CSI Controller
# ------------------------------------------------------------------------------
resource "kubernetes_service_account" "efs_csi_controller_sa" {
  provider = kubernetes.eks

  metadata {
    name      = "efs-csi-controller-sa"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.efs_csi_driver_role.arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.efs_csi_policy_attach,
    aws_eks_cluster.rstudio_eks
  ]
}

# ------------------------------------------------------------------------------ 
# Helm Release: AWS EFS CSI Driver
# ------------------------------------------------------------------------------
resource "helm_release" "aws_efs_csi_driver" {
  name      = "aws-efs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-efs-csi-driver/"
  chart      = "aws-efs-csi-driver"
  version    = "2.5.0"
  namespace  = "kube-system"

  values = [
    yamlencode({
      controller = {
        serviceAccount = {
          create = false                      # Use Terraform-managed SA
          name   = "efs-csi-controller-sa"
        }
      }
    })
  ]

  depends_on = [
    kubernetes_service_account.efs_csi_controller_sa,
    aws_eks_node_group.rstudio_nodes
  ]
}

# ------------------------------------------------------------------------------ 
# DATA SOURCE: Existing EFS File System (lookup by tag)
# ------------------------------------------------------------------------------
data "aws_efs_file_system" "efs" {
  tags = {
    Name = "mcloud-efs"
  }
}

# # ------------------------------------------------------------------------------ 
# # StorageClass for static EFS mounts (shared storage)
# # ------------------------------------------------------------------------------ 
# resource "kubernetes_storage_class" "efs_sc" {
#   provider = kubernetes.eks

#   metadata {
#     name = "efs-sc"
#     annotations = {
#       "storageclass.kubernetes.io/is-default-class" = "true"
#     }
#   }

#   # --------------------------------------------------------------------------
#   # IMPORTANT: Dynamic provisioning (efs-ap) parameters removed.
#   # The EFS CSI driver will now use manually defined PVs (static provisioning).
#   # --------------------------------------------------------------------------
#   storage_provisioner     = "efs.csi.aws.com"
#   mount_options           = ["tls"]
#   reclaim_policy          = "Retain"
#   volume_binding_mode     = "Immediate"
#   allow_volume_expansion  = true

#   # No parameters block — this disables dynamic provisioning

#   depends_on = [
#     helm_release.aws_efs_csi_driver,
#     aws_iam_role_policy_attachment.efs_csi_policy_attach
#   ]
# }

# # ------------------------------------------------------------------------------ 
# # Static Persistent Volume for shared EFS filesystem
# # ------------------------------------------------------------------------------ 
# resource "kubernetes_persistent_volume" "efs_pv" {

#   provider = kubernetes.eks

#   metadata {
#     name = "efs-pv"
#   }

#   spec {
#     capacity = {
#       storage = "1Ti"
#     }
#     access_modes                     = ["ReadWriteMany"]
#     persistent_volume_reclaim_policy = "Retain"
#     storage_class_name               = kubernetes_storage_class.efs_sc.metadata[0].name
#     mount_options                    = ["tls"]  # optional but recommended

#     # <-- This wrapper block is required by the Terraform Kubernetes provider
#     persistent_volume_source {
#       csi {
#         driver        = "efs.csi.aws.com"
#         volume_handle = data.aws_efs_file_system.efs.id  # e.g., fs-0abc123def456
#         read_only     = false
#         # volume_attributes = {}  # optional
#       }
#     }
#   }

#   depends_on = [
#     kubernetes_storage_class.efs_sc
#   ]
# }

