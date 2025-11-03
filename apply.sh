#!/bin/bash
# ==============================================================================
# Script Name: apply.sh
# Description:
#   Deploys a full AWS-based RStudio environment using Terraform and Docker.
#   Phases include:
#     1. Active Directory domain controller
#     2. EC2 servers joined to the domain
#     3. RStudio Docker image build and ECR push
#     4. ECS cluster deployment
#
# Requirements:
#   - AWS CLI v2, Terraform, Docker, jq installed
#   - AWS credentials with required permissions
#
# ==============================================================================

# ------------------------------------------------------------------------------
# Global Configuration
# ------------------------------------------------------------------------------
export AWS_DEFAULT_REGION="us-east-1"  # Default AWS region for deployment
set -euo pipefail                      # Exit on error, unset var, or pipe fail

# ------------------------------------------------------------------------------
# Environment Pre-Check
# ------------------------------------------------------------------------------
echo "NOTE: Running environment validation..."
./check_env.sh
if [ $? -ne 0 ]; then
  echo "ERROR: Environment validation failed. Exiting."
  exit 1
fi

# ------------------------------------------------------------------------------
# Phase 1: Build Active Directory Domain Controller
# ------------------------------------------------------------------------------
# Deploys the AD instance using Terraform. This forms the authentication base
# and must complete before dependent components proceed.
echo "NOTE: Building Active Directory instance..."

cd 01-directory || { echo "ERROR: 01-directory not found."; exit 1; }

terraform init
terraform apply -auto-approve

cd .. || exit

# ------------------------------------------------------------------------------
# Phase 2: Build Dependent EC2 Servers
# ------------------------------------------------------------------------------
# These EC2 instances are domain-joined. They depend on AD being healthy and
# available before creation.
echo "NOTE: Building EC2 server instances..."

cd 02-servers || { echo "ERROR: 02-servers not found."; exit 1; }

terraform init
terraform apply -auto-approve

cd .. || exit

# ------------------------------------------------------------------------------
# Phase 3: Build RStudio Docker Image and Push to ECR
# ------------------------------------------------------------------------------
# Builds the RStudio Server Docker image and pushes it to AWS ECR for later use
# in the EKS cluster.
echo "NOTE: Building RStudio Docker image and pushing to ECR..."

cd 03-docker/rstudio || { echo "ERROR: rstudio directory missing."; exit 1; }

# Retrieve AWS Account ID dynamically for ECR reference
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "ERROR: Failed to retrieve AWS Account ID. Exiting."
  exit 1
fi

# Authenticate Docker with AWS ECR using token-based login
aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | \
docker login --username AWS --password-stdin \
"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com" || {
  echo "ERROR: Docker authentication failed. Exiting."
  exit 1
}

# Retrieve RStudio password from Secrets Manager
RSTUDIO_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id rstudio_credentials \
  --query 'SecretString' \
  --output text | jq -r '.password') 

if [ -z "$RSTUDIO_PASSWORD" ] || [ "$RSTUDIO_PASSWORD" = "null" ]; then
  echo "ERROR: Failed to retrieve RStudio password. Exiting."
  exit 1
fi

# ==============================================================================
# Build and Push RStudio Docker Image (only if missing from ECR)
# ==============================================================================

IMAGE_TAG="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/rstudio:rstudio-server-rc1"

echo "NOTE: Checking if image already exists in ECR..."

# Query ECR for the image
if aws ecr describe-images \
    --repository-name rstudio \
    --image-ids imageTag="rstudio-server-rc1" \
    --region "${AWS_DEFAULT_REGION}" >/dev/null 2>&1; then
  echo "NOTE: Image already exists in ECR: ${IMAGE_TAG}"
else
  echo "WARNING: Image not found in ECR. Building and pushing..."

  docker build \
    --build-arg RSTUDIO_PASSWORD="${RSTUDIO_PASSWORD}" \
    -t "${IMAGE_TAG}" . || {
      echo "ERROR: Docker build failed. Exiting."
      exit 1
    }

  docker push "${IMAGE_TAG}" || {
    echo "ERROR: Docker push failed. Exiting."
    exit 1
  }

  echo "NOTE: Image successfully built and pushed to ECR: ${IMAGE_TAG}"
fi

cd ../.. || exit

# ------------------------------------------------------------------------------
# Phase 4: Build ECS Cluster
# ------------------------------------------------------------------------------
echo "NOTE: Building ECS cluster..."

cd 04-ecs || { echo "ERROR: 04-ecs directory missing."; exit 1; }

terraform init
terraform apply -auto-approve

# # Prepare Kubernetes YAML Manifests

# # Export environment variables
# export rstudio_image="${IMAGE_TAG}"
# export domain_fqdn="rstudio.mikecloud.com"
# export admin_secret="admin_ad_credentials"
# export efs_id=$(aws efs describe-file-systems \
#   --query "FileSystems[?Tags[?Key=='Name' && Value=='mcloud-efs']].FileSystemId" \
#   --output text)

# #echo "EFS_ID=${efs_id}"

# # Render template with environment substitution

# envsubst < yaml/rstudio-app.yaml.tmpl > ../rstudio-app.yaml || {
#     echo "ERROR: Failed to generate Kubernetes deployment file. Exiting."
#     exit 1
# }

cd .. || exit

# ------------------------------------------------------------------------------
# Phase 5: Build Validation
# ------------------------------------------------------------------------------
# Runs post-deployment checks for DNS, domain join, and instance health.
echo "NOTE: Running build validation..."

#./validate.sh  # Uncomment once validation script is implemented

# ==============================================================================
# End of Script
# ==============================================================================
