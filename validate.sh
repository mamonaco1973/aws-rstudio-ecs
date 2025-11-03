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

# ------------------------------------------------------------------------------
# Step 1: Wait for Load Balancer Hostname Assignment
# ------------------------------------------------------------------------------
# Polls the RStudio Ingress until AWS assigns a Load Balancer hostname.
# Once available, the hostname is exported as $LB_ADDRESS.
# ------------------------------------------------------------------------------

echo "NOTE: Waiting for Load Balancer address for Ingress: ${INGRESS_NAME}..."

for ((i=1; i<=MAX_ATTEMPTS; i++)); do
  LB_ADDRESS=$(kubectl get ingress ${INGRESS_NAME} \
    --namespace ${NAMESPACE} \
    --output jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

  if [[ -n "$LB_ADDRESS" ]]; then
    echo "NOTE: RStudio Ingress Load Balancer: $LB_ADDRESS"
    export LB_ADDRESS
    break
  fi

  echo "WARNING: Attempt $i/${MAX_ATTEMPTS}: Load Balancer not ready yet... retrying in ${SLEEP_SECONDS}s"
  sleep ${SLEEP_SECONDS}
done

if [[ -z "$LB_ADDRESS" ]]; then
  echo "ERROR: Timed out waiting for Load Balancer hostname."
  exit 1
fi

# ------------------------------------------------------------------------------
# Step 2: Wait for HTTP 200 Response from Load Balancer
# ------------------------------------------------------------------------------
# Once the hostname is available, continuously poll the endpoint until it
# returns HTTP 200, indicating RStudio is reachable via the Load Balancer.
# ------------------------------------------------------------------------------

echo "NOTE: Waiting for Load Balancer endpoint (http://${LB_ADDRESS}) to return HTTP 200..."

for ((j=1; j<=MAX_ATTEMPTS; j++)); do
  STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${LB_ADDRESS}/auth-sign-in")

  if [[ "$STATUS_CODE" == "200" ]]; then
    echo "NOTE: RStudio available at: http://${LB_ADDRESS}"
    exit 0
  fi

  echo "WARNING: Attempt $j/${MAX_ATTEMPTS}: Current status: HTTP ${STATUS_CODE} ... retrying in ${SLEEP_SECONDS}s"
  sleep ${SLEEP_SECONDS}
done

echo "ERROR: Timed out after ${MAX_ATTEMPTS} attempts waiting for HTTP 200 from Load Balancer."
exit 1
