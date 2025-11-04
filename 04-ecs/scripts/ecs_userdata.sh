#!/bin/bash
set -ex

# Ensure ECS config directory exists
mkdir -p /etc/ecs

# Register this instance with the ECS cluster
echo "ECS_CLUSTER=${cluster_name}" > /etc/ecs/ecs.config

# Optional: enable logging for easier troubleshooting
echo "ECS_ENABLE_CONTAINER_METADATA=true" >> /etc/ecs/ecs.config

# Install required utilities (for EFS mounting, etc.)
yum install -y amazon-efs-utils nfs-utils

# Enable and start the ECS agent service
systemctl enable ecs.service
systemctl start ecs.service
