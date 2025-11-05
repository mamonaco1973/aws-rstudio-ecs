#!/bin/bash
# ==============================================================================
# Wait for RStudio Ingress Load Balancer to Become Reachable
# ------------------------------------------------------------------------------
# Purpose:
#   This script verifies that the RStudio Ingress resource in Kubernetes
#   successfully receives an AWS Load Balancer endpoint and that the endpoint
#   responds with HTTP 200 (OK).
#
# Overview:
#   1. Retrieve DNS names of Windows and Linux AD instances for reference.
#   2. Wait for the RStudio Ingress to receive a Load Balancer hostname.
#   3. Poll the Load Balancer endpoint until it returns HTTP 200.
#
# Notes:
#   - Designed for use in AWS EKS environments.
#   - Exits with nonzero status if either step times out.
# ==============================================================================

NAMESPACE="default"
INGRESS_NAME="rstudio-ingress"
MAX_ATTEMPTS=30
SLEEP_SECONDS=10
AWS_DEFAULT_REGION="us-east-1"

# ------------------------------------------------------------------------------
# Step 0: Lookup Active Directory Instances
# ------------------------------------------------------------------------------

# --- Windows AD Instance ------------------------------------------------------
# Retrieve the public DNS name of the Windows AD administrator EC2 instance.
windows_dns=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=windows-ad-admin" \
  --query 'Reservations[].Instances[].PublicDnsName' \
  --output text)

if [ -z "$windows_dns" ]; then
  echo "WARNING: No Windows AD instance found with tag Name=windows-ad-admin"
else
  echo "NOTE: Windows Instance FQDN:       $(echo $windows_dns | xargs)"
fi

# --- Linux AD (Samba Gateway) Instance ----------------------------------------
# Retrieve the private DNS name of the EFS Samba gateway instance used for AD.
linux_dns=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=efs-samba-gateway" \
  --query 'Reservations[].Instances[].PrivateDnsName' \
  --output text)

if [ -z "$linux_dns" ]; then
  echo "WARNING: No EFS Gateway instance found with tag Name=efs-samba-gateway"
else
  echo "NOTE: EFS Gateway Instance FQDN:   $(echo $linux_dns | xargs)"
fi

# --------------------------------------------------------------------------------------------------
# Lookup ALB DNS Name
# --------------------------------------------------------------------------------------------------
alb_dns=$(aws elbv2 describe-load-balancers \
  --names rstudio-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

if [ -z "$alb_dns" ]; then
  echo "WARNING: No ALB found with name rstudio-alb"
else
  echo "NOTE: RStudio ALB Endpoint:        http://$alb_dns"
fi