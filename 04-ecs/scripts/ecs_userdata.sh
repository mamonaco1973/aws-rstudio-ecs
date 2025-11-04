#!/bin/bash
echo "ECS_CLUSTER=${cluster_name}" > /etc/ecs/ecs.config
systemctl enable --now ecs.service
