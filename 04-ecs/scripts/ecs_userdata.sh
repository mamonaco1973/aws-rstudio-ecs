#!/bin/bash
echo "ECS_CLUSTER=${cluster_name}" >> /etc/ecs/ecs.config
yum install -y amazon-efs-utils nfs-utils
systemctl enable --now ecs
