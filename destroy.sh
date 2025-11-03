#!/bin/bash
# ==============================================================================
# Script Name: destroy.sh
# Description:
#   Destroys all AWS resources created by the RStudio deployment, including:
#     1. EKS cluster and related security groups
#     2. EC2 server instances
#     3. AD domain controller and associated secrets
#     4. ECR repository cleanup
#
# Requirements:
#   - AWS CLI v2 and Terraform installed
#   - AWS credentials with required permissions
#
# ==============================================================================

# ------------------------------------------------------------------------------
# Global Configuration
# ------------------------------------------------------------------------------
export AWS_DEFAULT_REGION="us-east-1"  # AWS region for all deployed resources
set -euo pipefail                      # Exit on error, unset var, or pipe fail

# ------------------------------------------------------------------------------
# Destroy ECS Cluster
# ------------------------------------------------------------------------------
echo "NOTE: Destroying ECS cluster..."

cd 04-ecs || { echo "ERROR: Directory 04-ecs not found."; exit 1; }
terraform init
terraform destroy -auto-approve
cd .. || exit

# ------------------------------------------------------------------------------
# Destroy EC2 Server Instances
# ------------------------------------------------------------------------------
echo "NOTE: Destroying EC2 server instances..."

cd 02-servers || { echo "ERROR: Directory 02-servers not found."; exit 1; }
terraform init
terraform destroy -auto-approve
cd .. || exit

# ------------------------------------------------------------------------------
# Delete AD Secrets and Destroy Domain Controller
# ------------------------------------------------------------------------------
echo "NOTE: Deleting AD-related AWS secrets and parameters..."
# WARNING: These deletions are permanent. No recovery window applies.
# ------------------------------------------------------------------------------
for secret in \
  akumar_ad_credentials \
  jsmith_ad_credentials \
  edavis_ad_credentials \
  rpatel_ad_credentials \
  rstudio_credentials \
  admin_ad_credentials; do

  aws secretsmanager delete-secret \
    --secret-id "$secret" \
    --force-delete-without-recovery
done

aws ecr delete-repository --repository-name "rstudio" --force || {
  echo "WARN: Failed to delete ECR repository. It may not exist."
}

echo "NOTE: Destroying AD instance..."

cd 01-directory || { echo "ERROR: Directory 01-directory not found."; exit 1; }
terraform init
terraform destroy -auto-approve
cd .. || exit

# ------------------------------------------------------------------------------
# Completion
# ------------------------------------------------------------------------------
echo "NOTE: Infrastructure teardown complete."
# ==============================================================================
# End of Script
# ==============================================================================
