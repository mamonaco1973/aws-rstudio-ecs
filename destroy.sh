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
# Author: [Your Name]
# ==============================================================================

# ------------------------------------------------------------------------------
# Global Configuration
# ------------------------------------------------------------------------------
export AWS_DEFAULT_REGION="us-east-1"  # AWS region for all deployed resources
set -euo pipefail                      # Exit on error, unset var, or pipe fail

# ------------------------------------------------------------------------------
# Destroy EKS Cluster
# ------------------------------------------------------------------------------
echo "NOTE: Destroying EKS cluster..."

kubectl delete -f rstudio-app.yaml || echo "WARNING: Delete failed, continuing..."

cd 04-eks || { echo "ERROR: Directory 04-eks not found."; exit 1; }
terraform init
#echo "NOTE: Deleting nginx_ingress..."
#terraform destroy -target=helm_release.nginx_ingress \
#  -auto-approve > /dev/null 2> /dev/null
terraform destroy -auto-approve
cd .. || exit

# ------------------------------------------------------------------------------
# Delete Orphaned Security Groups Named "k8s*"
# ------------------------------------------------------------------------------
# AWS sometimes leaves dangling security groups after EKS deletion.
# This section detects and deletes them.
# ------------------------------------------------------------------------------
group_ids=$(aws ec2 describe-security-groups \
  --query "SecurityGroups[?starts_with(GroupName, 'k8s')].GroupId" \
  --output text)

if [ -z "$group_ids" ]; then
  echo "NOTE: No security groups starting with 'k8s' found."
fi

for group_id in $group_ids; do
  echo "NOTE: Deleting security group: $group_id"
  aws ec2 delete-security-group --group-id "$group_id"

  if [ $? -eq 0 ]; then
    echo "NOTE: Successfully deleted $group_id"
  else
    echo "WARN: Failed to delete $group_id — possibly in use elsewhere"
  fi
done

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
